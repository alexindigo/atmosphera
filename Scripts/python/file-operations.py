#!/usr/bin/env python3
"""Local chooser mutations. JSON in/out; never execute a filename as code.

GIO owns freedesktop Trash placement, escaping, collisions and mount policy.
There is deliberately no permanent-delete fallback when Trash is unavailable.
"""

import ctypes
import errno
import json
import os
import shutil
import stat
import subprocess
import sys


def identity(fd, name):
    value = os.stat(name, dir_fd=fd, follow_symlinks=False)
    # QML's JSON numbers are doubles. Keep identities lossless across the UI
    # confirmation round trip (nanosecond timestamps exceed 2**53).
    return [str(value.st_dev), str(value.st_ino), str(value.st_mode), str(value.st_ctime_ns)]


def valid_name(name):
    return isinstance(name, str) and name not in ("", ".", "..") and "/" not in name and "\0" not in name


def reason(error):
    return {errno.EEXIST: "exists", errno.ENOTEMPTY: "exists", errno.EACCES: "permission",
            errno.EPERM: "permission", errno.EROFS: "readonly", errno.ENAMETOOLONG: "long",
            errno.ENOENT: "missing", errno.ESTALE: "changed", errno.EINVAL: "invalid"}.get(error.errno, "unavailable")


def operate(request):
    kind, folder = request["kind"], request["folder"]
    if not os.path.isabs(folder) or "\0" in folder:
        raise ValueError("invalid")
    names = request.get("names", [])
    if kind not in ("create", "rename", "inspect", "delete", "trash") or not names or not all(valid_name(n) for n in names) or len(set(names)) != len(names):
        raise ValueError("invalid")
    if kind in ("create", "rename") and len(names) != 1:
        raise ValueError("invalid")
    if kind == "rename" and not valid_name(request.get("name")):
        raise ValueError("invalid")
    fd = os.open(folder, os.O_RDONLY | os.O_DIRECTORY)
    try:
        if kind == "inspect":
            return {"ok": True, "identities": [identity(fd, name) for name in names]}
        if kind == "delete":
            expected = request.get("identities", [])
            if len(expected) != len(names) or any(identity(fd, n) != e for n, e in zip(names, expected)):
                raise OSError(errno.ESTALE, "The selection changed. Review it before deleting.")
        completed, errors = [], []
        for index, name in enumerate(names):
            try:
                if kind == "create":
                    os.mkdir(name, dir_fd=fd)
                elif kind == "rename":
                    # Unlike os.rename, RENAME_NOREPLACE cannot clobber a target
                    # that appears between validation and the filesystem call.
                    libc = ctypes.CDLL(None, use_errno=True)
                    rename = libc.renameat2
                    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
                    rename.restype = ctypes.c_int
                    if name != request["name"] and rename(fd, os.fsencode(name), fd, os.fsencode(request["name"]), 1):
                        number = ctypes.get_errno()
                        raise OSError(number, os.strerror(number))
                elif kind == "trash":
                    result = subprocess.run(["gio", "trash", "--", os.path.join(folder, name)],
                                            env=dict(os.environ, GIO_USE_VFS="local"), capture_output=True, text=True, check=False)
                    if result.returncode:
                        errors.append({"name": name, "reason": "trash", "detail": result.stderr.strip()})
                        continue
                elif kind == "delete":
                    if identity(fd, name) != request["identities"][index]:
                        raise OSError(errno.ESTALE, "The selection changed. Review it before deleting.")
                    if stat.S_ISDIR(os.stat(name, dir_fd=fd, follow_symlinks=False).st_mode):
                        # Python's fd-based rmtree does not follow replaced links.
                        if not shutil.rmtree.avoids_symlink_attacks:
                            raise OSError(errno.ENOTSUP, "Safe directory deletion is unavailable")
                        shutil.rmtree(name, dir_fd=fd)
                    else:
                        os.unlink(name, dir_fd=fd)
                completed.append(name)
            except OSError as error:
                errors.append({"name": name, "reason": reason(error)})
        return {"ok": not errors, "completed": completed, "errors": errors}
    finally:
        os.close(fd)


def main():
    try:
        result = operate(json.load(sys.stdin))
    except ValueError:
        result = {"ok": False, "reason": "invalid"}
    except OSError as error:
        result = {"ok": False, "reason": reason(error)}
    print(json.dumps(result))


if __name__ == "__main__":
    main()
