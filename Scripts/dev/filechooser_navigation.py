"""Native mouse bands, independent keyboard focus and dialog navigation."""
import subprocess

from filechooser_isolation import input_command


def exercise(runtime, evidence, command, ipc, state, wait, check, open_request, key, focus):
    large, small = runtime / "Nav files", runtime / "Nav small"
    large.mkdir(); small.mkdir()
    for i in range(39): (large / f"File {i:02d}.txt").write_text("navigation fixture\n")
    for i in range(3): (small / f"Small {i}.txt").write_text("navigation fixture\n")

    def opened(view, folder=large, multiple=True):
        open_request("open", "dev.filechooser.navigation", str(folder), multiple=multiple)
        ipc(view)
        return wait(lambda s: s["ready"] and s["view"] == view and len(s["layoutGeometry"]["entries"]["tiles"]) >= 3)
    def screen(g, x, y):
        return [int((1280 - g["width"]) / 2 + g["listing"]["x"] + x),
                int((800 - g["height"]) / 2 + g["listing"]["y"] + y)]
    def click(index, modifiers=0):
        g = state()["layoutGeometry"]; t = next(t for t in g["entries"]["tiles"] if t["index"] == index)
        command(["ydotool", "click", *screen(g, t["x"] + t["width"] / 2, t["y"] + t["height"] / 2), 272, modifiers])
    def band(modifiers=0, capture=None):
        s = state(); g = s["layoutGeometry"]; tiles = g["entries"]["tiles"]
        columns = len({round(t["x"], 2) for t in tiles})
        first = next(t for t in tiles if t["index"] == 0)
        last = next(t for t in tiles if t["index"] == (columns + 1 if columns > 1 else 4))
        x0, y0 = first["x"] + 5, first["y"] + 5
        x1, y1 = last["x"] + last["width"] / 2, last["y"] + last["height"] / 2
        hits = {t["path"] for t in tiles if t["x"] < x1 and t["x"] + t["width"] > x0
                and t["y"] < y1 and t["y"] + t["height"] > y0}
        argv = ["ydotool", "drag", *screen(g, x0, y0), *screen(g, x1, y1), modifiers]
        if capture:
            # Observe the live rectangle while the real held mouse gesture is
            # still running, then reap this exact client before continuing.
            process = subprocess.Popen(["timeout", "12", *input_command(list(map(str, argv)))], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                wait(lambda s: s["scroll"]["bandActive"])
                command(["grim", evidence / capture])
            finally:
                stdout, stderr = process.communicate(timeout=18)
                assert process.returncode == 0, (stdout, stderr)
        else:
            command(argv)
        return hits

    for view in ("grid", "list"):
        s = opened(view); names = s["names"]
        first, second = str(large / names[0]), str(large / names[1])
        key(102); key(106, 29)
        check(view + "-Ctrl-Right-focus-only", lambda s: s["cursor"] == 1 and s["selected"] == [first])
        key(57, 29)
        check(view + "-Ctrl-Space-adds-not-preview", lambda s: set(s["selected"]) == {first, second} and not s["preview"])
        key(57, 29)
        check(view + "-Ctrl-Space-removes", lambda s: s["selected"] == [first])
        key(28, 29)
        check(view + "-modified-Enter-no-accept", lambda s: not s["settled"])
        if view == "grid":
            columns = len({round(t["x"], 2) for t in state()["layoutGeometry"]["entries"]["tiles"]})
            key(102)
            for _ in range(columns - 1): key(106)
            for _ in range((39 - 1) // columns): key(108)
            key(103)
            check("grid-incomplete-row-remembers-column", lambda s: s["cursor"] == ((39 - 1) // columns - 1) * columns + columns - 1)

        opened(view)
        hits = band(capture=view + "-rubber-band-active.png")
        check(view + "-rubber-band-exact-intersections", lambda s: set(s["selected"]) == hits and len(hits) > 1 and not s["settled"])
        command(["grim", evidence / (view + "-rubber-band-selection.png")])
        click(0); hits = band(2)
        check(view + "-Ctrl-band-symmetric-difference", lambda s: set(s["selected"]) == hits ^ {first})
        click(0); hits = band(1)
        check(view + "-Shift-band-additive", lambda s: set(s["selected"]) == hits | {first})

        opened(view)
        g = state()["layoutGeometry"]; v = g["entries"]["viewport"]
        command(["ydotool", "drag", *screen(g, v["x"] + 5, v["y"] + 5),
                 *screen(g, v["x"] + v["width"] / 2, v["y"] + v["height"] - 2), 0])
        check(view + "-band-edge-autoscroll", lambda s: s["scroll"]["y"] > 0 and len(s["selected"]) > 5)

        opened(view); click(0)
        before = state()["selected"]
        g = state()["layoutGeometry"]; v = g["entries"]["viewport"]
        x, y = screen(g, v["x"] + v["width"] / 2, v["y"] + v["height"] - 60)
        ipc("touchStart", str(x), str(y))
        for move in range(1, 9): ipc("touchMove", str(x), str(y - move * 30))
        ipc("touchEnd", str(x), str(y - 240))
        wait(lambda s: s["scroll"]["y"] > 0)
        check(view + "-touch-flick-not-band", lambda s: s["selected"] == before and not s["scroll"]["bandActive"])

        for multiple in (True, False):
            opened(view, small, multiple)
            click(0)
            before = state()["selected"]
            g = state()["layoutGeometry"]; v = g["entries"]["viewport"]
            point = screen(g, v["x"] + v["width"] / 2, v["y"] + v["height"] - 15)
            command(["ydotool", "click", *point, 272, 2])
            check(view + f"-background-modified-preserves-{multiple}", lambda s: s["selected"] == before)
            command(["ydotool", "click", *point, 272, 0])
            check(view + f"-background-clears-{multiple}", lambda s: s["selected"] == [] and not s["settled"])

        opened(view, large, False); click(0); band()
        check(view + "-single-no-band-accumulation", lambda s: len(s["selected"]) == 1 and not s["settled"])
        focus("Sort by"); key(35, 29)
        check(view + "-hidden-shortcut-dialog-scoped", lambda s: s["hidden"])
        key(35, 29)
        ipc("failFolder"); wait(lambda s: bool(s["error"]))
        key(63)
        wait(lambda s: s["ready"] and not s["error"])
        check(view + "-F5-reloads-from-control-focus", lambda s: s["path"] == str(large))

    tree = runtime / "History"
    (tree / "A/B").mkdir(parents=True); (tree / "Peer").mkdir()
    open_request("save", "dev.filechooser.navigation", str(tree / "A/B"), current_name="keep.txt")
    key(38, 29); command(["ydotool", "type", str(tree / "Peer")]); key(28)
    wait(lambda s: s["ready"] and s["path"] == str(tree / "Peer"))
    ipc("focusListing"); key(14)
    wait(lambda s: s["ready"] and s["path"] == str(tree / "A/B"))
    check("Backspace-is-history-not-parent", lambda s: s["saveName"] == "keep.txt")
    focus("File name"); key(30, 29); command(["ydotool", "type", "keep.txt"]); key(14)
    check("Backspace-in-name-edits-only", lambda s: s["saveName"] == "keep.tx" and s["path"] == str(tree / "A/B"))
    key(106, 56)
    wait(lambda s: s["ready"] and s["path"] == str(tree / "Peer"))
    key(105, 56)
    wait(lambda s: s["ready"] and s["path"] == str(tree / "A/B"))
    key(103, 56)
    wait(lambda s: s["ready"] and s["path"] == str(tree / "A"))
    check("Alt-navigation-scoped-while-editing", lambda s: s["saveName"] == "keep.tx" and not s["settled"])
    command(["ydotool", "move", 5, 5])
    ipc("open", "open"); wait(lambda s: s["ready"] and s["focus"] == "listing")
