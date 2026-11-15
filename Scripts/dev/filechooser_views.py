"""Native view controls, geometry, thumbnail consumers and preference reload."""
from pathlib import Path
import json
import math
import os
import time


def exercise(runtime, evidence, command, ipc, state, wait, check, open_request, key, focus):
    base = runtime / "Views"
    base.mkdir()
    for i in range(93):
        path = base / f"Entry {i:03}.txt"
        path.write_text("view consumer bytes\n")
        os.utime(path, (1760000000, 1760000000))
    open_request("open", "dev.filechooser.views", str(base), multiple=True)
    ipc("grid")
    check("views-owner-controls-present", lambda s: "zoom" in s.get("views", {}))
    check("view-controls-share-structural-centerline", lambda s: max(c["y"] + c["height"] / 2 for c in s["views"]["controls"])
          - min(c["y"] + c["height"] / 2 for c in s["views"]["controls"]) < .5)
    check("view-controls-do-not-overlap-dialog-resize-hitbox", lambda s: all(
          c["name"] == "Dialog size" or c["x"] + c["width"] <= s["views"]["resize"]["x"]
          or c["x"] >= s["views"]["resize"]["x"] + s["views"]["resize"]["width"]
          or c["y"] + c["height"] <= s["views"]["resize"]["y"]
          or c["y"] >= s["views"]["resize"]["y"] + s["views"]["resize"]["height"]
          for c in s["views"]["controls"]))

    def absolute(rect):
        g = state()["layoutGeometry"]
        return dict(rect, x=rect["x"] + (1280 - g["width"]) / 2,
                    y=rect["y"] + (800 - g["height"]) / 2)

    def click(rect):
        rect = absolute(rect)
        command(["ydotool", "click", int(rect["x"] + rect["width"] / 2), int(rect["y"] + rect["height"] / 2), 272, 0])
        command(["ydotool", "move", 5, 5])

    def header(label):
        click(next(c for c in state()["layoutGeometry"]["header"] if c.get("name") == label))

    def drag(rect, dx, dy=0):
        r = absolute(rect)
        x, y = int(r["x"] + r["width"] / 2), int(r["y"] + r["height"] / 2)
        command(["ydotool", "drag", x, y, x + dx, y + dy, 0])
        command(["ydotool", "move", 5, 5])

    key(102)
    original = state()["views"]["zoom"]
    command(["ydotool", "key", "29:1", "42:1", "13:1", "13:0", "42:0", "29:0"])
    wait(lambda s: s["views"]["zoom"] == original + 1)
    check("Ctrl-plus-renders-larger-artwork", lambda s: s["icons"][0]["artwork"]["width"] == 112)
    key(12, 29)
    check("Ctrl-minus-restores-zoom", lambda s: s["views"]["zoom"] == original)
    g = state()["layoutGeometry"]; v = g["entries"]["viewport"]
    x = int((1280 - g["width"]) / 2 + g["listing"]["x"] + v["x"] + v["width"] / 2)
    y = int((800 - g["height"]) / 2 + g["listing"]["y"] + v["y"] + v["height"] / 2)
    command(["ydotool", "move", x, y])
    command(["ydotool", "scroll-modified", "wheel", -15, 2])
    wait(lambda s: s["views"]["zoom"] == original + 1)
    check("Ctrl-wheel-zooms-without-scrolling", lambda s: s["scroll"]["y"] == 0)
    slider = next(c for c in state()["views"]["controls"] if c["name"] == "Zoom")
    drag(slider, -25)
    check("zoom-slider-pointer-changes-rendered-size", lambda s: s["views"]["zoom"] != original + 1
          and abs(s["icons"][0]["artwork"]["width"] - s["views"]["iconSize"]) < .5)
    focus("Zoom"); key(107)
    check("zoom-slider-keyboard-upper-bound", lambda s: s["views"]["zoom"] == 6)
    check("zoom-maximum-consumer-artwork", lambda s: s["icons"][0]["artwork"]["width"] == 160)
    command(["grim", evidence / "views-grid-large.png"])
    key(102)
    check("zoom-slider-keyboard-lower-bound", lambda s: s["views"]["zoom"] == 0)
    # Reset grid to its default for unchanged downstream scroll/layout journeys.
    for _ in range(3): key(106)
    command(["grim", evidence / "views-grid.png"])
    header("Compact view")
    wait(lambda s: s["view"] == "compact" and len(s["layoutGeometry"]["entries"]["tiles"]) > 2)
    check("compact-is-top-to-bottom-side-artwork", lambda s: s["views"]["flow"] == "columns"
          and s["layoutGeometry"]["entries"]["tiles"][1]["x"] == s["layoutGeometry"]["entries"]["tiles"][0]["x"]
          and s["layoutGeometry"]["entries"]["tiles"][1]["y"] > s["layoutGeometry"]["entries"]["tiles"][0]["y"]
          and s["icons"][0]["artwork"]["width"] == 20)
    ipc("focusListing"); key(102); key(108)
    check("compact-Down-next-row", lambda s: s["cursor"] == 1)
    key(106, 29)
    check("compact-Ctrl-Right-next-column-keeps-selection", lambda s: s["cursor"] == 1 + s["views"]["rows"] and len(s["selected"]) == 1)
    key(107)
    check("compact-End-reveals-horizontal-current", lambda s: s["views"]["x"] > 0 and s["cursor"] == 92)
    key(102)
    g = state()["layoutGeometry"]; v = g["entries"]["viewport"]
    command(["ydotool", "move", int((1280 - g["width"]) / 2 + g["listing"]["x"] + v["x"] + v["width"] / 2),
             int((800 - g["height"]) / 2 + g["listing"]["y"] + v["y"] + v["height"] / 2)])
    command(["ydotool", "scroll", "wheel", 15]); command(["ydotool", "scroll-stop"])
    immediate = state()["views"]["x"]
    time.sleep(.3)
    check("compact-wheel-exact-horizontal-travel-no-tail", lambda s: abs(s["views"]["x"] - s["scroll"]["wheelStep"]) < 1 and abs(s["views"]["x"] - immediate) < .5)
    key(102)
    command(["ydotool", "scroll", "finger", 8]); command(["ydotool", "scroll-stop"])
    immediate = state()["views"]["x"]
    time.sleep(.3)
    check("compact-finger-exact-horizontal-travel-no-tail", lambda s: abs(s["views"]["x"] - 8) < 1 and abs(s["views"]["x"] - immediate) < .5)
    key(102)
    g = state()["layoutGeometry"]; tiles = {t["index"]: t for t in g["entries"]["tiles"]}
    first, third = tiles[0], tiles[2]
    origin = {"x": g["listing"]["x"], "y": g["listing"]["y"]}
    start = absolute(dict(first, x=first["x"] + origin["x"], y=first["y"] + origin["y"]))
    end = absolute(dict(third, x=third["x"] + origin["x"], y=third["y"] + origin["y"]))
    command(["ydotool", "drag", int(start["x"] + 10), int(start["y"] + 10), int(end["x"] + end["width"] - 10), int(end["y"] + end["height"] - 10), 0])
    check("compact-band-uses-column-geometry", lambda s: sorted(Path(p).name for p in s["selected"]) == [f"Entry {i:03}.txt" for i in range(3)])
    key(13, 29)
    check("compact-zoom-is-independent", lambda s: s["views"]["iconSize"] == 24)
    command(["ydotool", "move", 5, 5])
    time.sleep(.3)  # Let the prior native hover tooltip leave the captured frame.
    command(["grim", evidence / "views-compact.png"])
    key(102)
    rows = state()["views"]["rows"]
    for _ in range(rows - 1): key(108)
    for _ in range(math.ceil(93 / rows) - 1): key(106)
    key(105)
    check("compact-incomplete-column-remembers-row", lambda s: s["cursor"] == (math.ceil(93 / rows) - 2) * rows + rows - 1)
    key(102)
    header("List view")
    wait(lambda s: len(s["views"].get("handles", [])) == 2)
    check("details-keeps-its-own-zoom", lambda s: s["views"]["iconSize"] == 20)
    check("details-resizers-stay-in-intercolumn-gaps", lambda s: all(
          handle["x"] >= s["views"]["cells"][i]["x"] + s["views"]["cells"][i]["width"] - .5
          and handle["x"] + handle["width"] <= s["views"]["cells"][i + 1]["x"] + .5
          for i, handle in enumerate(s["views"]["handles"])))
    before = state()["columnGeometry"]["header"]
    drag(state()["views"]["handles"][0], 25)
    check("details-column-pointer-resize-and-shared-geometry", lambda s: s["columnGeometry"]["header"][1] > before[1] + 20
          and all(abs(a-b) < .5 for a, b in zip(s["columnGeometry"]["header"], s["columnGeometry"]["row"])))
    focus("Size column width")
    before_key = state()["views"]["columnShares"]
    key(105)
    check("details-column-keyboard-resize", lambda s: s["views"]["columnShares"] != before_key
          and s["views"]["columnShares"][1] < before_key[1])
    command(["grim", evidence / "views-details.png"])
    before_size = state()["layoutGeometry"]
    ipc("panelWidth", "10000"); ipc("panelHeight", "10000")
    check("dialog-size-is-screen-contained", lambda s: s["layoutGeometry"]["width"] <= 1280 and s["layoutGeometry"]["height"] <= 800)
    # Grow from a smaller preferred size so both resize axes can travel.
    ipc("panelWidth", "1110"); ipc("panelHeight", "680")
    before_size = state()["layoutGeometry"]
    drag(state()["views"]["resize"], 32, 24)
    check("dialog-pointer-resizes-both-axes", lambda s: s["layoutGeometry"]["width"] >= before_size["width"] + 25
          and s["layoutGeometry"]["height"] >= before_size["height"] + 20)
    focus("Dialog size"); before_size = state()["layoutGeometry"]; key(105); key(103)
    check("dialog-keyboard-resizes-both-axes", lambda s: s["layoutGeometry"]["width"] < before_size["width"]
          and s["layoutGeometry"]["height"] < before_size["height"])
    settings = state()["views"]
    ipc("focusListing"); key(102); key(28)
    wait(lambda s: s["settled"])
    open_request("open", "dev.filechooser.views.reopen", str(base), multiple=True)
    check("views-reopen-restores-mode-zooms-columns-and-size", lambda s: all(s["views"][name] == settings[name]
          for name in ("mode", "zooms", "columnShares", "dialogWidth", "dialogHeight")))
    check("views-reopen-renders-size-and-aligned-columns", lambda s: abs(s["layoutGeometry"]["width"] - settings["dialogWidth"]) < 1
          and abs(s["layoutGeometry"]["height"] - settings["dialogHeight"]) < 1
          and all(abs(a-b) < .5 for a, b in zip(s["columnGeometry"]["header"], s["columnGeometry"]["row"])))
    on_disk = json.loads((runtime / "profile/cache/atmosphera/filechooser.json").read_text())
    check("views-persisted-json-matches-consumer", lambda s: on_disk["preferences"]["views"] == s["views"]["preferences"])
    # Real image decoding, then off must remove sources in every presentation.
    open_request("open", "dev.filechooser.views.thumbnails", str(runtime / "Fieldwork"))
    for label in ("Grid view", "Compact view", "List view"):
        header(label)
        wait(lambda s: any(t.get("imageReady") for t in s["thumbnails"]["tiles"]))
        check("thumbnails-on-consumer-" + label, lambda s: any(t.get("imageReady") for t in s["thumbnails"]["tiles"]))
        focus("Thumbnails"); key(57)
        wait(lambda s: not s["views"]["thumbnails"])
        check("thumbnails-off-removes-sources-" + label, lambda s: not s["thumbnails"]["tiles"] and bool(s["thumbnails"]["entries"])
              and all(not t.get("source") and not t.get("imageReady") for t in s["thumbnails"]["entries"]))
        command(["grim", evidence / ("views-no-thumbnails-" + state()["view"] + ".png")])
        key(57)
    ipc("grid"); key(1)
