# Bounded framing and queues for the unchanged Max Ultra MCP wire protocol.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import base64
import collections
import threading
import time

MAX_FRAME = 4194304
MAX_QUEUED_BYTES = 8388608
MAX_QUEUED_ITEMS = 64


def encode(content):
    return base64.b64encode(str(content).encode("utf-8")).decode("ascii") or "-"


def decode(content):
    return "" if content in ("", "-") else base64.b64decode(content, validate=True).decode("utf-8")


class FrameReader:
    def __init__(self):
        self.buffer = bytearray()
        self.started = None

    def feed(self, chunk, now=None):
        now = time.monotonic() if now is None else now
        if not self.buffer:
            self.started = now
        self.buffer.extend(chunk)
        frames = []
        while True:
            end = self.buffer.find(b"\n")
            if end < 0:
                break
            if end > MAX_FRAME:
                raise ValueError("REQUEST_TOO_LARGE: transport frame exceeds 4 MiB")
            frames.append(bytes(self.buffer[:end]).rstrip(b"\r").decode("ascii"))
            del self.buffer[:end + 1]
            self.started = now if self.buffer else None
        if len(self.buffer) > MAX_FRAME:
            raise ValueError("REQUEST_TOO_LARGE: transport frame exceeds 4 MiB")
        self.check_deadline(now)
        return frames

    def check_deadline(self, now=None):
        now = time.monotonic() if now is None else now
        if self.started is not None and now - self.started > 5:
            raise TimeoutError("Incomplete transport frame timed out")


class BoundedQueue:
    def __init__(self):
        self._items = collections.deque()
        self._bytes = 0
        self._lock = threading.Lock()

    def put(self, line):
        length = len(line.encode("ascii"))
        with self._lock:
            if length > MAX_FRAME or len(self._items) >= MAX_QUEUED_ITEMS or self._bytes + length > MAX_QUEUED_BYTES:
                raise BufferError("BRIDGE_BUSY: transport queue limit exceeded")
            self._items.append((line, length))
            self._bytes += length

    def pop(self):
        with self._lock:
            if not self._items:
                return None
            line, length = self._items.popleft()
            self._bytes -= length
            return line

    def clear(self):
        with self._lock:
            self._items.clear()
            self._bytes = 0

    def empty(self):
        with self._lock:
            return not self._items
