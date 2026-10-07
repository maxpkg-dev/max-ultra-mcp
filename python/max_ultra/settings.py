# Atomic settings compatible with the existing MaxScript panel INI.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import configparser
import io
import os
from pathlib import Path
import uuid


def read_ini(filename):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    raw = Path(filename).read_bytes()
    encoding = "utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
    parser.read_string(raw.decode(encoding))
    return parser


class Settings:
    def __init__(self, filename):
        self.filename = Path(filename)
        self.data = read_ini(filename) if self.filename.exists() else configparser.ConfigParser(interpolation=None)

    def get(self, section, key, default=""):
        return self.data.get(section, key, fallback=str(default))

    def boolean(self, section, key, default=False):
        return self.get(section, key, str(default)).lower() == "true"

    def integer(self, section, key, default=0):
        try:
            return int(self.get(section, key, default))
        except ValueError:
            return default

    def set_many(self, section, values):
        if not self.data.has_section(section):
            self.data.add_section(section)
        for key, value in values.items():
            self.data.set(section, key, str(value).lower() if isinstance(value, bool) else str(value))
        self.filename.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.filename.with_name(self.filename.name + "." + uuid.uuid4().hex + ".tmp")
        try:
            with temporary.open("w", encoding="utf-8", newline="\n") as stream:
                self.data.write(stream)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(str(temporary), str(self.filename))
        finally:
            if temporary.exists():
                temporary.unlink()
