# Socket worker; this module never imports or calls pymxs or UI APIs.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import json
import os
from pathlib import Path
import re
import select
import socket
import threading
import uuid

from .wire import BoundedQueue, FrameReader, encode, decode, MAX_FRAME
from .processes import LifecycleMutex, launch_helper


def control(port, operation, payload="", token="", timeout=0.5):
    fields = ["CONTROL", "1", "bootstrap-control", operation]
    if payload or token:
        fields.append(encode(payload))
    if token:
        fields.append(encode(token))
    with socket.create_connection(("127.0.0.1", port), timeout) as connection:
        connection.sendall(("\t".join(fields) + "\n").encode("ascii"))
        with connection.makefile("rb") as stream:
            line = stream.readline(MAX_FRAME + 2)
        if len(line) > MAX_FRAME or not line.endswith(b"\n"):
            raise ValueError("Invalid control response size")
        response = line.decode("ascii").rstrip("\r\n").split("\t")
        if len(response) != 4 or response[:2] != ["CONTROL_RESPONSE", "bootstrap-control"]:
            raise ValueError("Endpoint identity not verified")
        content = decode(response[3])
        if response[2] != "ok":
            raise ValueError(content)
        return content


def probe(port):
    try:
        raw = control(port, "probe")
        result = json.loads(raw)
        if result.get("server") == "max-ultra-mcp" and result.get("healthy") is True:
            return "healthy", raw
    except ConnectionRefusedError:
        return "closed", ""
    except ValueError as error:
        if "Unknown control operation 'probe'" in str(error):
            try:
                raw = control(port, "list")
                inventory = json.loads(raw)
                if "instances" in inventory and "selectedInstanceId" in inventory:
                    return "legacy", raw
            except (OSError, ValueError):
                pass
    except OSError:
        # Windows can time out a refused loopback connect before reporting 10061.
        # An exclusive bind proves the port is free without trusting that timeout.
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as reservation:
                if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
                    reservation.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
                reservation.bind(("127.0.0.1", port))
            return "closed", ""
        except OSError:
            pass
    return "occupied", ""


class Transport:
    def __init__(self, root, state_directory, port, hello, restart=False, allow_launch=True, visible=False):
        self.root, self.state_directory = Path(root), Path(state_directory)
        self.port, self.hello = int(port), hello
        self.restart, self.allow_launch, self.visible = restart, allow_launch, visible
        self.inbound, self.outbound = BoundedQueue(), BoundedQueue()
        self.stop_event = threading.Event()
        self.connection = None
        self.error = None
        self.owner_token = uuid.uuid4().hex
        self.thread = threading.Thread(target=self._run, name="MaxUltraTransport", daemon=True)

    def start(self):
        self.thread.start()

    def stop(self):
        self.stop_event.set()
        connection = self.connection
        if connection is not None:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

    def token(self):
        token = os.environ.get("MAX_ULTRA_MCP_CONTROL_TOKEN", "")
        if not token:
            filename = os.environ.get("MAX_ULTRA_MCP_TOKEN_FILE", str(Path(os.environ["LOCALAPPDATA"]) / "3DGROUND/MaxUltraMCP/runtime/state/control-token"))
            token = Path(filename).read_text(encoding="utf-8-sig").strip()
        if not re.fullmatch("[a-fA-F0-9]{64}", token):
            raise ValueError("Installation control token unavailable")
        return token.lower()

    def event(self, category, message):
        self.inbound.put("EVENT\t{}\t{}".format(category, encode(message)))

    def _prepare(self):
        with LifecycleMutex(self.port):
            state, identity = probe(self.port)
            if self.restart and state == "healthy":
                inventory = json.loads(control(self.port, "list"))
                count = inventory.get("count")
                if not isinstance(count, int):
                    raise ValueError("Connected instance count could not be verified")
                if count <= 1:
                    control(self.port, "shutdown_owned", identity, self.token())
                    for delay in (0.05, 0.1, 0.15, 0.25, 0.35, 0.5, 0.75, 1, 1):
                        if self.stop_event.wait(delay):
                            return False
                        state, identity = probe(self.port)
                        if state == "closed":
                            break
                    if state != "closed":
                        raise TimeoutError("Verified server did not stop")
                else:
                    self.event("warning", "Shared server reused without interrupting other Max instances")
            if state == "occupied" or (self.restart and state == "legacy"):
                if not self.allow_launch:
                    raise RuntimeError("Configured endpoint is not a verified server")
                for port in range(self.port + 1, min(65535, self.port + 10) + 1):
                    state, identity = probe(port)
                    if state == "closed":
                        self.port = port
                        self.event("port_changed", str(port))
                        break
                else:
                    raise RuntimeError("No free fallback port in the next 10 loopback ports")
            if state == "closed":
                if not self.allow_launch:
                    raise RuntimeError("Server is not running; run the entry script to start it")
                ownership = self.state_directory / "ownership"
                ownership.mkdir(parents=True, exist_ok=True)
                process = launch_helper(self.root, "start-server.ps1", ["--port", str(self.port), "--owner-file", str(ownership / ("max-ultra-mcp-owned-{}.json".format(self.port))), "--owner-token", self.owner_token, "--owner-max-pid", str(os.getpid())], self.visible)
                for delay in (0.15, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 5):
                    if self.stop_event.wait(delay):
                        return False
                    state, identity = probe(self.port)
                    if state == "healthy":
                        break
                    # A newly bound daemon can still be initializing its probe
                    # handler. Wait for verified identity until the same bounded
                    # deadline; never attach to or terminate an unknown occupant.
                    if process.poll() is not None:
                        raise RuntimeError("Server launcher exited with code {}".format(process.returncode))
                if state != "healthy":
                    raise TimeoutError("Server startup deadline exceeded")
            return not self.stop_event.is_set()

    def _run(self):
        try:
            if not self._prepare():
                return
            with socket.create_connection(("127.0.0.1", self.port), 2) as connection:
                self.connection = connection
                connection.settimeout(1)
                connection.sendall((self.hello + "\n").encode("ascii"))
                self.event("connected", "Connected to local MCP server")
                reader = FrameReader()
                while not self.stop_event.is_set():
                    for _ in range(16):
                        line = self.outbound.pop()
                        if line is None:
                            break
                        connection.sendall((line + "\n").encode("ascii"))
                    readable, _, _ = select.select([connection], [], [], 0.02)
                    if readable:
                        chunk = connection.recv(65536)
                        if not chunk:
                            raise ConnectionError("Local MCP server disconnected")
                        for line in reader.feed(chunk):
                            self.inbound.put(line)
                    reader.check_deadline()
        except Exception as error:
            if not self.stop_event.is_set():
                self.error = str(error)
        finally:
            self.connection = None
