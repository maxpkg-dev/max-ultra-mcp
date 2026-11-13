# Bounded asynchronous package helper operations with cooperative cancellation.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from pathlib import Path
import time
import uuid
import configparser
import json

from .processes import launch_helper, launch_node, bundled_node
from .settings import read_ini

SKILL_APPEARANCE = ["--background", "28,28,26", "--foreground", "232,227,218", "--buttonBackground", "48,46,41", "--buttonHover", "65,56,45"]


def skills_command(operation, arguments=None):
    """Translate a Skills window operation into skills-cli.js arguments; None when it has no direct form."""
    values = dict(zip((arguments or [])[0::2], (arguments or [])[1::2]))
    forms = {
        "list": ("list",), "community-list": ("community-list",), "community-sync": ("community-sync",),
        "delete": ("delete", "-SkillId"), "add-folder": ("add-folder", "-Source"), "add-zips": ("add-zips-file", "-Source"),
        "community-install": ("community-install", "-SkillId", "-Source", "-Revision"),
        "community-delete": ("community-delete", "-SkillId", "-Source", "-Revision"),
        "community-page": ("community-page", "-SkillId"),
    }
    form = forms.get(operation)
    if form is None or any(not values.get(name) for name in form[1:]):
        return None
    return [form[0]] + [values[name] for name in form[1:]] + SKILL_APPEARANCE


class Helper:
    def __init__(self, root, directory, filename, arguments, result_argument="-ResultPath", timeout=75, node=None):
        self.result = Path(directory) / ("operation-" + uuid.uuid4().hex + ".ini")
        self.started = time.monotonic()
        self.timeout = timeout
        self.cancelled = False
        if node is not None and bundled_node(root) is not None:
            # Same script and result file as the PowerShell helper, started without its wrapper.
            self.process = launch_node(root, node[0], list(node[1]) + ["--result", str(self.result)])
        else:
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

    def read_progress(self):
        try:
            with self.result.with_name(self.result.name + ".progress.json").open(encoding="utf-8") as stream:
                return json.loads(stream.read(1024))
        except (OSError, ValueError):
            return None

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
        for filename in [self.result.with_name(self.result.name + suffix) for suffix in ("", ".txt", ".html", ".cancel", ".progress.json", ".progress.json.tmp")] + self.temporary_files:
            try:
                filename.unlink()
            except FileNotFoundError:
                pass

    def dispose(self):
        # The job contains only this operation and descendants; never the daemon.
        self.process.owned_job.close()
        self.cleanup()
