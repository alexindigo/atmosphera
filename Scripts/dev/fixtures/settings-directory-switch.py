"""Owned fixture filesystem actions; the QML consumer proves their observation."""
from pathlib import Path
import json
import os
import sys

root = Path(sys.argv[1])
assert root.is_symlink() and root.parent.name.startswith("directory-")
phase = int(sys.argv[2])


def write(directory, font):
    directory.mkdir(exist_ok=True)
    (directory / "ui.json").write_text(json.dumps({"fontDefault": font, "opaque": "keep"}))


if phase == 1:
    target = root.resolve() / "sections-b"
    write(target, "I4 Directory B")
    link = root / "settings.next"
    link.symlink_to(target)
    os.replace(link, root / "settings")
elif phase == 2:
    temporary = root / "settings/ui.next"
    temporary.write_text(json.dumps({"fontDefault": "I4 Directory C", "opaque": "keep"}))
    os.replace(temporary, root / "settings/ui.json")
elif phase == 3:
    (root / "settings").rename(root / "settings.old")
    write(root / "settings", "I4 Directory D")
elif phase == 4:
    target = root.parent / "config-b"
    target.mkdir()
    write(target / "settings", "I4 Directory E")
    link = root.parent / "config.next"
    link.symlink_to(target)
    os.replace(link, root)
elif phase == 5:
    temporary = root / "settings/ui.next"
    temporary.write_text(json.dumps({"fontDefault": "I4 Directory F", "opaque": "keep"}))
    os.replace(temporary, root / "settings/ui.json")
elif phase == 6:
    target = root.resolve() / "sections-g"
    write(target, "I4 Directory G")
    (root / "settings").rename(root / "settings.retained")
    (root / "settings").symlink_to(target)
else:
    raise ValueError("Unknown fixture phase")
