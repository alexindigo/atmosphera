"""Keyboard-only and mouse-only selection consumer walks for the UI runner."""
import math
import os


def exercise(runtime, evidence, command, ipc, state, wait, check, open_request, key):
    files = runtime / "Selection files"
    folders = runtime / "Selection folders"
    files.mkdir(); folders.mkdir()
    for i in range(40):
        path = files / f"File {i:02d}.txt"
        path.write_text("selection fixture\n")
        os.utime(path, (1792260000, 1792260000))
    for i in range(4):
        (folders / f"Folder {i}").mkdir()

    def click(index, modifiers=0):
        s = state(); g = s["layoutGeometry"]; listing = g["listing"]
        tile = next(t for t in g["entries"]["tiles"] if t["index"] == index)
        x = int((1280 - g["width"]) / 2 + listing["x"] + tile["x"] + tile["width"] / 2)
        y = int((800 - g["height"]) / 2 + listing["y"] + tile["y"] + tile["height"] / 2)
        command(["ydotool", "click", x, y, 272, modifiers])

    def open_view(view, multiple=True, directory=False):
        folder = folders if directory else files
        open_request("open", "dev.filechooser.selection", str(folder), multiple=multiple, directory=directory)
        ipc(view)
        return wait(lambda s: s["view"] == view and len(s["layoutGeometry"]["entries"]["tiles"]) >= 4)

    for view in ("grid", "list"):
        s = open_view(view)
        names = s["names"]
        expected = lambda first, last: {str(files / name) for name in names[first:last + 1]}
        def selected(s, first, last):
            return set(s["selected"]) == expected(first, last) and not s["settled"]
        geometry = s["layoutGeometry"]["entries"]
        ys = sorted({round(t["y"], 3) for t in geometry["tiles"]})
        stride = min(b - a for a, b in zip(ys, ys[1:]) if b > a)
        columns = len({round(t["x"], 3) for t in geometry["tiles"]})
        page = max(1, math.floor(geometry["viewport"]["height"] / stride)) * columns
        check(view + "-page-step-is-viewport-sized", lambda s: s["scroll"]["pageStep"] == page)
        key(102); key(106, 42)
        check(view + "-Shift-Right-range", lambda s: selected(s, 0, 1))
        key(108, 42)
        check(view + "-Shift-Down-extends-anchor", lambda s: selected(s, 0, 1 + columns))
        key(102, 42)
        check(view + "-Shift-Home-shrinks-range", lambda s: selected(s, 0, 0))
        key(107, 42)
        check(view + "-Shift-End-range", lambda s: selected(s, 0, 39))
        key(104, 42)
        check(view + "-Shift-PageUp-range", lambda s: selected(s, 0, max(0, 39 - page)))
        key(102); key(109, 42)
        check(view + "-Shift-PageDown-range", lambda s: selected(s, 0, min(39, page)))
        key(104, 42)
        check(view + "-Shift-PageUp-keeps-anchor", lambda s: selected(s, 0, 0))
        key(30, 29)
        check(view + "-Ctrl-A-selects-all", lambda s: selected(s, 0, 39))

        # A fresh view makes this walk mouse-only, including anchor creation.
        s = open_view(view)
        click(0); wait(lambda s: len(s["selected"]) == 1)
        click(6, 1); wait(lambda s: len(s["selected"]) == 7)
        check(view + "-mouse-Shift-click-range", lambda s: selected(s, 0, 6))
        if view == "grid":
            wait(lambda s: {name for name in names[:7]} <= {icon["name"] for icon in s["icons"]})
            command(["grim", evidence / "selection-grid-range.png"])
        click(3, 2); wait(lambda s: len(s["selected"]) == 6)
        check(view + "-mouse-Ctrl-click-removes", lambda s: set(s["selected"]) == expected(0, 6) - expected(3, 3))
        click(3, 2); wait(lambda s: len(s["selected"]) == 7)
        check(view + "-modified-double-click-does-not-accept", lambda s: selected(s, 0, 6) and s["path"] == str(files))

        open_view(view, multiple=False)
        click(0); click(3, 1)
        check(view + "-single-mouse-range-keeps-one", lambda s: selected(s, 3, 3))
        key(107, 42)
        check(view + "-single-Shift-End-keeps-one", lambda s: selected(s, 39, 39))
        key(104, 42)
        check(view + "-single-Shift-PageUp-keeps-one", lambda s: len(s["selected"]) == 1)
        key(30, 29)
        check(view + "-single-Ctrl-A-does-not-accumulate", lambda s: len(s["selected"]) == 1)

        folder_names = open_view(view, directory=True)["names"]
        click(0); click(2, 1)
        check(view + "-folder-mouse-range", lambda s: set(s["selected"]) == {str(folders / name) for name in folder_names[:3]})
        click(1, 2); wait(lambda s: len(s["selected"]) == 2)
        click(1, 2); wait(lambda s: len(s["selected"]) == 3)
        check(view + "-folder-toggle-does-not-navigate", lambda s: s["path"] == str(folders) and not s["settled"])
        if view == "grid":
            first = open_view(view)["names"][0]
            click(0); click(0)
            wait(lambda s: s["settled"])
            check("unmodified-double-click-still-accepts", lambda s: s["replies"][0]["response"] == 0
                  and s["replies"][0]["results"]["uris"] == [(files / first).as_uri()])

    command(["ydotool", "move", 5, 5])
    ipc("open", "open")
    wait(lambda s: s["ready"] and s["focus"] == "listing")
