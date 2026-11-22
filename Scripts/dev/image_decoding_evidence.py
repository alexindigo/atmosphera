"""Exact file/mode identities for independent image qualification inputs."""
import hashlib
import json
import os
from pathlib import Path
import stat


def source_manifest(root):
    root = Path(root)
    rows = {}
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if any(part in ('.git', '.envrc', '__pycache__') for part in relative.parts):
            continue
        info = path.lstat()
        if path.is_symlink():
            rows[str(relative)] = dict(type='link', target=os.readlink(path), mode=stat.S_IMODE(info.st_mode))
        elif path.is_file():
            rows[str(relative)] = dict(type='file', sha256=hashlib.sha256(path.read_bytes()).hexdigest(), mode=stat.S_IMODE(info.st_mode))
    digest = hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()
    return dict(sha256=digest, files=rows)
