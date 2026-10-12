# Confirm MaxPkg installation and remove only unchanged obsolete package assets.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat

from .settings import read_ini


def installed_identity(root, temp_root):
    root, temp_root = Path(root).absolute(), Path(temp_root).resolve()
    manifest = root / "manifest.ini"
    if not manifest.is_file():
        return None
    package = read_ini(manifest)
    guid = package.get("package", "packageGuid", fallback="")
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", guid):
        raise ValueError("Invalid installed package identity")
    if root.name.lower() != guid.lower() or root.parent.resolve() != temp_root:
        return None  # A source checkout is never an installed cleanup target.
    if root.is_symlink() or getattr(root.lstat(), 'st_file_attributes', 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT:
        raise ValueError("Installed package root must not be a link")
    version = package.get("package", "version", fallback="")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid installed package version")
    return {"guid": guid, "version": version}


def installation_ready(root, temp_root):
    identity = installed_identity(root, temp_root)
    if identity is None:
        return True
    try:
        return json.loads((Path(root) / ".installation-complete.json").read_text(encoding="utf-8")) == identity
    except (OSError, ValueError):
        return False


def complete_installation(root, temp_root):
    root = Path(root).absolute()
    identity = installed_identity(root, temp_root)
    if identity is None:
        raise ValueError("Cleanup requires the installed MaxPkg directory")
    # Do not mark a partially extracted package as installed.
    required = (root / "maxpkg-files.txt").read_text(encoding="utf-8").splitlines()
    for relative in required:
        relative = relative.strip()
        if not relative or relative.startswith('#'):
            continue
        parts = PurePosixPath(relative)
        if parts.is_absolute() or '..' in parts.parts or '\\' in relative or ':' in relative:
            raise ValueError("Unsafe required package path")
        if not root.joinpath(*parts.parts).is_file():
            raise ValueError("Required installed file is missing: " + relative)
    inventory = json.loads((root / "assets/obsolete-1.4.7.json").read_text(encoding="utf-8"))
    removed, preserved = [], []
    for relative, expected in inventory.items():
        parts = PurePosixPath(relative)
        if parts.is_absolute() or '..' in parts.parts or '\\' in relative or ':' in relative:
            raise ValueError("Unsafe obsolete package path")
        target = root.joinpath(*parts.parts)
        for component in [target] + list(target.parents):
            if component == root:
                break
            if component.exists() or component.is_symlink():
                if component.is_symlink() or getattr(component.lstat(), 'st_file_attributes', 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT:
                    raise ValueError("Obsolete package path must not traverse a link")
        if not target.exists():
            continue
        if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != expected:
            preserved.append(relative)
            continue
        target.unlink()
        removed.append(relative)
    # The standard MaxPkg hook calls this only after installation confirmation.
    receipt = root / ".installation-complete.json"
    temporary = root / ".installation-complete.tmp"
    temporary.write_text(json.dumps(identity), encoding="utf-8")
    os.replace(str(temporary), str(receipt))
    return {"removed": removed, "preserved": preserved}
