# Verify staged MaxPkg archives before invoking the upstream installer.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import hashlib
from pathlib import Path
import re
import zipfile

GUID = "c6977570-25a6-41b0-b9bb-b3be8101123c"


def staged_version(filename):
    match = re.fullmatch(r"max-ultra-mcp@(\d+\.\d+\.\d+)@" + GUID + r"\.mzp", Path(filename).name)
    if not match:
        raise ValueError("Invalid staged package filename")
    return match.group(1)


def verify_package(filename, directory, version):
    package = Path(filename).resolve()
    staging = Path(directory).resolve()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid staged version")
    if staging not in package.parents or not package.is_file() or package.name != "max-ultra-mcp@{}@{}.mzp".format(version, GUID):
        raise ValueError("Staged package rejected by path validation")
    checksum = Path(str(package) + ".sha256").read_text(encoding="utf-8-sig").strip()
    match = re.fullmatch(r"([a-fA-F0-9]{64})\s+\*?([^\r\n]+)", checksum)
    if not match or match.group(2) != package.name:
        raise ValueError("Invalid staged checksum filename")
    digest = hashlib.sha256()
    with package.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != match.group(1).lower():
        raise ValueError("Staged MZP SHA-256 no longer matches")
    if not zipfile.is_zipfile(str(package)):
        raise ValueError("Staged MZP is not a package archive")
    return package
