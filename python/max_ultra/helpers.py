# Bounded asynchronous package helper operations with cooperative cancellation.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from pathlib import Path
import time
import uuid
import configparser

from .processes import launch_helper
from .settings import read_ini


class Helper:
    def __init__(self, root, directory, filename, arguments, result_argument="-ResultPath", timeout=75):
        self.result = Path(directory) / ("operation-" + uuid.uuid4().hex + ".ini")
        self.started = time.monotonic()
        self.timeout = timeout
        self.cancelled = False
        self.process = launch_helper(root, filename, list(arguments) + [result_argument, str(self.result)], managed=True)
        self.snapshot = None
        self.temporary_files = []

    def read(self):
        if self.result.exists():
            try:
                self.snapshot = read_ini(self.result)
            except (OSError, UnicodeError, configparser.Error):
                if self.process.poll() is not None:
                    raise
        return self.snapshot

    def cancel(self):
        self.cancelled = True
        self.result.with_name(self.result.name + ".cancel").write_text("cancel", encoding="utf-8")

    def poll(self):
        self.read()
        code = self.process.poll()
        if code is None and time.monotonic() - self.started > self.timeout:
            self.cancel()
            self.process.owned_job.close()
            raise TimeoutError("Operation timed out; refresh status before retrying")
        return code

    def cleanup(self):
        self.process.owned_job.close()
        for filename in [self.result.with_name(self.result.name + suffix) for suffix in ("", ".txt", ".html", ".cancel")] + self.temporary_files:
            try:
                filename.unlink()
            except FileNotFoundError:
                pass

    def dispose(self):
        # The job contains only this operation and descendants; never the daemon.
        self.process.owned_job.close()
        self.cleanup()
