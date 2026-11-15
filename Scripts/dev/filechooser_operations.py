"""Native keyboard/mouse file-operation journeys and filesystem outcomes."""
from pathlib import Path
import os


def exercise(runtime, evidence, command, ipc, state, wait, check, open_request, key, focus):
    base = runtime / "Operations"
    base.mkdir()
    (base / "Folder").mkdir()
    os.utime(base / "Folder", (1760000000, 1760000000))
    for name in ("Alpha.txt", "Beta.txt", "Taken.txt"):
        (base / name).write_text(name + " consumer bytes\n")
        os.utime(base / name, (1760000000, 1760000000))

    def current(name):
        ipc("focusListing"); key(102)
        names = state()["names"]
        for _ in range(names.index(name)):
            key(108 if state()["view"] == "list" else 106)

    def menu(key_name=None):
        # XKB's physical Menu key is evdev COMPOSE; KEY_MENU is XF86MenuKB.
        key(127)
        wait(lambda s: s.get("operations", {}).get("menu", {}).get("open", False))
        if key_name:
            pick(key_name)

    def pick(key_name):
        entries = state()["operations"]["menu"]["entries"]
        key(102)
        for _ in range(next(i for i, row in enumerate(entries) if row["key"] == key_name)):
            key(108)
        key(28)

    def menu_contained(s):
        rect = s["operations"]["menu"]["frame"]
        return rect["x"] >= 0 and rect["y"] >= 0 and rect["x"] + rect["width"] <= 1280 and rect["y"] + rect["height"] <= 800

    def click(rect, button=273, modifiers=0):
        command(["ydotool", "click", int(rect["x"] + rect["width"] / 2), int(rect["y"] + rect["height"] / 2), button, modifiers])
        command(["ydotool", "move", 5, 5])

    def entry_rect(name):
        s = state(); g = s["layoutGeometry"]
        row = next(t for t in g["entries"]["tiles"] if Path(t["path"]).name == name)
        return dict(row, x=(1280 - g["width"]) / 2 + g["listing"]["x"] + row["x"], y=(800 - g["height"]) / 2 + g["listing"]["y"] + row["y"])

    open_request("save", "dev.filechooser.operations", str(base), current_name="draft.txt")
    ipc("grid")
    current("Alpha.txt"); key(60)
    wait(lambda s: s.get("operations", {}).get("renaming", False) and s["focusedControl"] == "New name")
    check("F2-inline-rename-stem-selected", lambda s: s["operations"]["renameSelection"] == [0, 5] and s["saveName"] == "Alpha.txt")
    check("inline-rename-hides-unavailable-accept", lambda s: "Save" not in [c["name"] for c in s["layoutGeometry"]["footer"]])
    command(["grim", evidence / "operations-inline-rename.png"])
    key(30, 29); command(["ydotool", "type", "Taken.txt"]); key(28)
    wait(lambda s: s["operations"]["renameError"])
    check("rename-existing-inline-error-keeps-editor", lambda s: s["operations"]["renaming"] and (base / "Taken.txt").read_text() == "Taken.txt consumer bytes\n")
    command(["grim", evidence / "operations-rename-error.png"])
    key(30, 29); command(["ydotool", "type", "../outside"]); key(28)
    check("rename-invalid-stays-inline", lambda s: bool(s["operations"]["renameError"]) and not (runtime / "outside").exists())
    key(30, 29); command(["ydotool", "type", "Renamed #%.txt"]); key(28)
    wait(lambda s: s["ready"] and not s["operations"]["busy"] and not s["operations"]["renaming"] and s["name"] == "Renamed #%.txt")
    check("rename-reconciles-save-name-and-consumer-bytes", lambda s: s["saveName"] == "Renamed #%.txt" and s["selected"] == [str(base / "Renamed #%.txt")] and not (base / "Alpha.txt").exists() and (base / "Renamed #%.txt").read_text() == "Alpha.txt consumer bytes\n")
    menu()
    command(["grim", evidence / "operations-item-menu.png"])
    check("item-menu-core-actions", lambda s: {"rename", "trash", "delete", "new", "copy", "hidden", "sort", "view"} <= {r["key"] for r in s["operations"]["menu"]["entries"]})
    check("item-menu-frame-within-screen", menu_contained)
    pick("copy")
    check("copy-item-path-clipboard-bytes", lambda s: command(["wl-paste", "--no-newline"]) == str(base / "Renamed #%.txt"))
    check("context-menu-focus-return", lambda s: s["focus"] == "listing")
    menu("sort")
    wait(lambda s: s["operations"]["menu"]["depth"] == 1)
    command(["grim", evidence / "operations-sort-submenu.png"])
    pick("sort-size")
    check("sort-submenu-applies-to-model", lambda s: s["sort"] == "size")
    menu("view"); pick("view-list")
    wait(lambda s: s["view"] == "list")
    check("view-submenu-keeps-current-item", lambda s: s["name"] == "Renamed #%.txt")
    key(60); wait(lambda s: s["focusedControl"] == "New name")
    key(1)
    check("inline-rename-Escape-only-editor", lambda s: not s["operations"]["renaming"] and not s["settled"] and s["focus"] == "listing")
    key(111, 42)
    wait(lambda s: s["operations"]["pendingDelete"])
    check("Shift-Delete-safe-default-and-keeps-file", lambda s: s["focusedControl"] == "Cancel" and (base / "Renamed #%.txt").is_file())
    command(["grim", evidence / "operations-delete-confirmation.png"])
    key(15); key(15)
    check("delete-confirmation-Tab-contained", lambda s: s["focusedControl"] == "Cancel")
    key(1)
    check("delete-confirmation-Escape-preserves-request", lambda s: not s["operations"]["pendingDelete"] and not s["settled"] and s["focus"] == "listing")
    key(111, 42); wait(lambda s: s["operations"]["pendingDelete"])
    key(15); key(28)
    wait(lambda s: s["ready"] and not s["operations"]["busy"] and "Renamed #%.txt" not in s["names"])
    check("confirmed-delete-filesystem-and-selection", lambda s: not (base / "Renamed #%.txt").exists() and s["selected"] == [] and not s["settled"])

    open_request("open", "dev.filechooser.operations", str(base), multiple=True)
    ipc("grid"); current("Beta.txt")
    click(entry_rect("Beta.txt"))
    wait(lambda s: s["operations"]["menu"]["open"])
    check("right-click-targets-item", lambda s: s["selected"] == [str(base / "Beta.txt")])
    # Mouse-only submenu selection, using real popup row geometry.
    click(next(r for r in state()["operations"]["menu"]["rows"] if r["key"] == "view"), 272)
    wait(lambda s: s["operations"]["menu"]["depth"] == 1)
    click(next(r for r in state()["operations"]["menu"]["rows"] if r["key"] == "view-list"), 272)
    wait(lambda s: s["view"] == "list")
    current("Beta.txt"); key(111)
    wait(lambda s: s["ready"] and not s["operations"]["busy"] and "Beta.txt" not in s["names"])
    trash = runtime / "profile/data/Trash"
    check("Delete-moves-to-recoverable-trash", lambda s: not (base / "Beta.txt").exists() and any(p.read_text() == "Beta.txt consumer bytes\n" for p in (trash / "files").iterdir()) and any("Beta.txt" in p.read_text() for p in (trash / "info").glob("*.trashinfo")))
    g = state()["layoutGeometry"]; viewport = g["entries"]["viewport"]
    blank = {"x": (1280 - g["width"]) / 2 + g["listing"]["x"] + viewport["x"], "y": (800 - g["height"]) / 2 + g["listing"]["y"] + viewport["y"] + viewport["height"] - 15, "width": viewport["width"], "height": 2}
    click(blank)
    wait(lambda s: s["operations"]["menu"]["open"])
    command(["grim", evidence / "operations-background-menu.png"])
    check("background-menu-hides-item-actions", lambda s: not {"rename", "trash", "delete"} & {r["key"] for r in s["operations"]["menu"]["entries"]})
    check("background-menu-frame-within-screen", menu_contained)
    pick("copy")
    check("copy-background-path-clipboard-bytes", lambda s: command(["wl-paste", "--no-newline"]) == str(base))
    key(68, 42); wait(lambda s: s["operations"]["menu"]["open"])
    pick("hidden")
    check("context-show-hidden-applies", lambda s: s["hidden"])
    menu("new")
    wait(lambda s: s["creatingFolder"] and s["focusedControl"] == "Folder name")
    command(["ydotool", "type", "From menu"]); key(28)
    wait(lambda s: s["ready"] and not s["creatingFolder"] and "From menu" in s["names"])
    check("context-new-folder-filesystem-and-current", lambda s: (base / "From menu").is_dir() and s["name"] == "From menu")
    key(1)

    for name in ("multi-a.txt", "multi-b.txt", "stay.txt"):
        (base / name).write_text(name + " mouse bytes\n")
    open_request("open", "dev.filechooser.operations.mouse", str(base), multiple=True)
    ipc("grid")
    click(entry_rect("multi-a.txt"), 272)
    click(entry_rect("multi-b.txt"), 272, 2)
    click(entry_rect("multi-a.txt"))
    wait(lambda s: s["operations"]["menu"]["open"])
    check("right-click-preserves-multiple-selection", lambda s: sorted(Path(p).name for p in s["selected"]) == ["multi-a.txt", "multi-b.txt"])
    check("multiple-menu-hides-single-item-rename", lambda s: "rename" not in [r["key"] for r in s["operations"]["menu"]["entries"]])
    click(next(r for r in state()["operations"]["menu"]["rows"] if r["key"] == "trash"), 272)
    wait(lambda s: s["ready"] and not s["operations"]["busy"] and "multi-a.txt" not in s["names"] and "multi-b.txt" not in s["names"])
    check("mouse-trash-entire-selection", lambda s: not (base / "multi-a.txt").exists() and not (base / "multi-b.txt").exists() and s["selected"] == [])
    click(entry_rect("stay.txt"))
    wait(lambda s: s["operations"]["menu"]["open"])
    click(next(r for r in state()["operations"]["menu"]["rows"] if r["key"] == "rename"), 272)
    wait(lambda s: s["focusedControl"] == "New name")
    key(30, 29); command(["ydotool", "type", "Mouse renamed.txt"]); key(28)
    wait(lambda s: s["ready"] and not s["operations"]["renaming"] and "Mouse renamed.txt" in s["names"])
    check("mouse-context-rename-filesystem", lambda s: (base / "Mouse renamed.txt").read_text() == "stay.txt mouse bytes\n" and not (base / "stay.txt").exists())
    click(entry_rect("Mouse renamed.txt"))
    wait(lambda s: s["operations"]["menu"]["open"])
    click(next(r for r in state()["operations"]["menu"]["rows"] if r["key"] == "delete"), 272)
    wait(lambda s: s["operations"]["pendingDelete"])
    click(next(r for r in state()["operations"]["deleteButtons"] if r["name"] == "Cancel"), 272)
    wait(lambda s: not s["operations"]["pendingDelete"])
    check("mouse-delete-cancel-keeps-file", lambda s: (base / "Mouse renamed.txt").is_file() and not s["settled"])
    click(entry_rect("Mouse renamed.txt"))
    wait(lambda s: s["operations"]["menu"]["open"])
    click(next(r for r in state()["operations"]["menu"]["rows"] if r["key"] == "delete"), 272)
    wait(lambda s: s["operations"]["pendingDelete"])
    click(next(r for r in state()["operations"]["deleteButtons"] if r["name"] == "Delete permanently"), 272)
    wait(lambda s: s["ready"] and not s["operations"]["busy"] and "Mouse renamed.txt" not in s["names"])
    check("mouse-confirmed-delete-filesystem", lambda s: not (base / "Mouse renamed.txt").exists() and s["selected"] == [])
    key(1)
