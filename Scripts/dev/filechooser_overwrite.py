"""Overwrite UI safety walks; the browser suite proves actual consumer writes."""
import os


def exercise(runtime, evidence, command, ipc, state, wait, check, open_request, key, focus):
    folder = runtime / "Overwrite"
    folder.mkdir()
    protected = folder / "protected.txt"
    protected.write_text("ORIGINAL protected bytes\n")
    (folder / "other.txt").write_text("ORIGINAL other bytes\n")
    (folder / "a.txt").write_text("case-sensitive fixture\n")
    (folder / "directory").mkdir()
    (folder / "unwritable.txt").write_text("read only\n")
    (folder / "unwritable.txt").chmod(0o444)
    os.mkfifo(folder / "fifo")
    (folder / "dangling").symlink_to(folder / "missing")
    (folder / "directory-link").symlink_to(folder / "directory", target_is_directory=True)
    (folder / "regular-link").symlink_to(protected)

    def save(name):
        return open_request("save", "dev.filechooser.overwrite", str(folder), current_name=name)
    def pending(name):
        return wait(lambda s: s["replace"] == str(folder / name) and s["focusedControl"] in ("Change name", "Back", "Replace"))

    save("protected.txt"); key(28); pending("protected.txt")
    check("overwrite-default-is-change-name", lambda s: s["focusedControl"] == "Change name" and not s["replies"])
    command(["grim", evidence / "overwrite-safe-default.png"])
    key(28)
    wait(lambda s: not s["replace"] and s["focus"] == "name")
    check("overwrite-Enter-returns-to-name", lambda s: not s["settled"] and s["saveName"] == "protected.txt" and s["nameSelection"] == [0, 9])
    key(28); pending("protected.txt"); key(28)
    wait(lambda s: not s["replace"] and s["focus"] == "name")
    check("overwrite-repeated-Enter-never-confirms", lambda s: not s["settled"] and not s["replies"])
    key(30, 29); command(["ydotool", "type", "protected.txt"]); key(28); pending("protected.txt")
    key(1)
    wait(lambda s: not s["replace"] and s["focus"] == "name")
    check("overwrite-Escape-returns-to-name-with-filter", lambda s: s["saveName"] == "protected.txt" and s["nameSelection"] == [0, 9] and not s["settled"])
    key(30, 29); command(["ydotool", "type", "new name.txt"]); key(28)
    wait(lambda s: s["settled"])
    check("overwrite-change-name-final-target", lambda s: s["replies"][0]["response"] == 0 and s["replies"][0]["results"]["uris"] == [(folder / "new name.txt").as_uri()])

    save("protected.txt"); key(28); pending("protected.txt")
    focus("Replace"); key(28); wait(lambda s: s["settled"])
    check("overwrite-explicit-replace-only", lambda s: s["replies"][0]["response"] == 0 and s["replies"][0]["results"]["uris"] == [protected.as_uri()])
    for name in ("directory", "unwritable.txt", "fifo", "dangling", "directory-link"):
        save(name); key(28)
        wait(lambda s: bool(s["error"]))
        check("overwrite-refuses-" + name, lambda s: not s["replace"] and not s["settled"] and not s["replies"])
    save("regular-link"); key(28); pending("regular-link")
    check("overwrite-regular-symlink-needs-confirmation", lambda s: not s["settled"] and not s["replies"])
    key(1); wait(lambda s: not s["replace"] and s["focus"] == "name")
    save("A.txt"); key(28); wait(lambda s: s["settled"])
    check("overwrite-Linux-case-sensitive", lambda s: s["replies"][0]["response"] == 0 and s["replies"][0]["results"]["uris"] == [(folder / "A.txt").as_uri()])

    names = ["protected.txt", "other.txt"]
    open_request("saveFiles", "dev.filechooser.overwrite", str(folder), files=[list(os.fsencode(name) + b"\0") for name in names])
    focus("Save"); key(28); pending("protected.txt")
    check("overwrite-saveFiles-default-back", lambda s: s["focusedControl"] == "Back")
    focus("Replace"); key(28); pending("other.txt")
    check("overwrite-saveFiles-no-partial-result", lambda s: not s["replies"] and s["focusedControl"] == "Back")
    key(28); wait(lambda s: not s["replace"] and s["focus"] == "listing")
    check("overwrite-saveFiles-back-keeps-request", lambda s: not s["settled"] and not s["replies"])
    focus("Save"); key(28); pending("protected.txt")
    check("overwrite-saveFiles-back-clears-approvals", lambda s: not s["replies"])
    focus("Replace"); key(28); pending("other.txt")
    focus("Replace"); key(28); wait(lambda s: s["settled"])
    check("overwrite-saveFiles-every-target-approved", lambda s: s["replies"][0]["response"] == 0 and s["replies"][0]["results"]["uris"] == [(folder / name).as_uri() for name in names])
    check("overwrite-backend-never-writes-targets", lambda s: protected.read_text() == "ORIGINAL protected bytes\n" and (folder / "other.txt").read_text() == "ORIGINAL other bytes\n" and not (folder / "new name.txt").exists())
    ipc("open", "open")
    wait(lambda s: s["ready"] and s["focus"] == "listing")
