"""Native favorite controls, history viewport/selection and external Wayland drop."""
import json
import os
from pathlib import Path
import subprocess
import time


def exercise(runtime, evidence, command, ipc, state, wait, check, open_request, key, focus):
    base = runtime / "Places"
    (base / "Child").mkdir(parents=True)
    for i in range(70): (base / f"Place {i:03}.txt").write_text("history fixture\n")
    open_request("open", "dev.filechooser.places", str(base), multiple=True)
    check("places-edit-controls-present", lambda s: "favorites" in s.get("placesState", {}))
    focus("Add current folder to favorites"); key(28)
    wait(lambda s: any(p["path"] == str(base) for p in s["placesState"]["favorites"]) and not s["placesState"]["busy"])
    bookmarks = runtime / "profile/config/gtk-3.0/bookmarks"
    check("favorite-add-persists-GTK-bookmark", lambda s: base.as_uri() in bookmarks.read_text())
    focus("Places"); ipc("refreshPlaces")
    wait(lambda s: not s["placesLoading"])
    check("places-unchanged-refresh-retains-native-focus", lambda s: s["focusedControl"] == "Places")
    key(103, 56)  # Alt+Up, then add another folder through the same control.
    wait(lambda s: s["ready"] and s["path"] == str(runtime))
    focus("Add current folder to favorites"); key(28)
    wait(lambda s: len(s["placesState"]["favorites"]) == 2 and not s["placesState"]["busy"])

    def click(rect, button=272):
        g = state()["layoutGeometry"]
        command(["ydotool", "click", int((1280-g["width"])/2+rect["x"]+rect["width"]/2),
                 int((800-g["height"])/2+rect["y"]+rect["height"]/2), button, 0])
        command(["ydotool", "move", 5, 5])

    def menu(action, pointer=False):
        if pointer:
            click(next(row for row in state()["placesState"]["rows"] if row["kind"] == "bookmark" and row["path"] == str(base)), 273)
        else:
            focus("Places"); key(68, 42)
        wait(lambda s: s["placesState"]["menu"]["open"])
        menu = state()["placesState"]["menu"]
        index = next(i for i, e in enumerate(menu["entries"]) if e["key"] == action)
        if pointer: click(next(row for row in menu["rows"] if row["key"] == action))
        else:
            key(102)
            for _ in range(index): key(108)
            key(28)
        wait(lambda s: not s["placesState"]["menu"]["open"] and not s["placesState"]["busy"])

    menu("down")
    check("favorite-keyboard-reorder-persists", lambda s: s["placesState"]["favorites"][-1]["path"] == str(base)
          and bookmarks.read_text().splitlines()[-1] == base.as_uri())
    check("favorite-reorder-returns-visible-focus", lambda s: s["focusedControl"] == "Places")
    menu("up", pointer=True)
    check("favorite-mouse-reorder-up-persists", lambda s: s["placesState"]["favorites"][0]["path"] == str(base))
    focus("Places"); key(28)
    wait(lambda s: s["ready"] and s["path"] == str(base))
    command(["grim", evidence / "places-favorites.png"])

    def header(name):
        s = state(); g = s["layoutGeometry"]
        rect = next(c for c in g["header"] if c.get("name") == name)
        command(["ydotool", "click", int((1280-g["width"])/2+rect["x"]+rect["width"]/2),
                 int((800-g["height"])/2+rect["y"]+rect["height"]/2), 272, 0])
        command(["ydotool", "move", 5, 5])

    for name, mode in [("Grid view", "grid"), ("List view", "list"), ("Compact view", "compact")]:
        header(name); ipc("focusListing"); key(107); key(105, 42)
        s = state(); selected, cursor = s["selected"], s["cursor"]
        g = s["layoutGeometry"]; viewport = g["entries"]["viewport"]
        command(["ydotool", "move", int((1280-g["width"])/2+g["listing"]["x"]+viewport["x"]+viewport["width"]/2),
                 int((800-g["height"])/2+g["listing"]["y"]+viewport["y"]+viewport["height"]/2)])
        command(["ydotool", "scroll", "finger", -17]); command(["ydotool", "scroll-stop"])
        saved = state(); x, y = saved["views"]["x"]-saved["views"]["originX"], saved["scroll"]["y"]-saved["views"]["originY"]
        key(38, 29); command(["ydotool", "type", str(base / "Child")]); key(28)
        wait(lambda s: s["ready"] and s["path"] == str(base / "Child"))
        key(105, 56)
        wait(lambda s: s["ready"] and s["path"] == str(base) and s["cursor"] == cursor)
        time.sleep(.25)
        (evidence / ("history-" + mode + ".json")).write_text(json.dumps({"saved": saved, "restored": state()}, indent=2))
        check("history-restores-" + mode + "-selection-and-exact-scroll", lambda s: s["selected"] == selected
              and abs(s["views"]["x"]-s["views"]["originX"]-x) < 1 and abs(s["scroll"]["y"]-s["views"]["originY"]-y) < 1)
        before = {t["path"]: t for t in saved["layoutGeometry"]["entries"]["tiles"]}
        check("history-restores-" + mode + "-visible-file-geometry", lambda s: bool(before)
              and {t["path"] for t in s["layoutGeometry"]["entries"]["tiles"]} == set(before) and all(
              abs(t["x"]-before[t["path"]]["x"]) < 1 and abs(t["y"]-before[t["path"]]["y"]) < 1
              for t in s["layoutGeometry"]["entries"]["tiles"]))
        key(106, 56)
        wait(lambda s: s["ready"] and s["path"] == str(base / "Child"))
        key(105, 56); wait(lambda s: s["ready"] and s["path"] == str(base))

    menu("remove", pointer=True)
    check("favorite-remove-persists", lambda s: not any(p["path"] == str(base) for p in s["placesState"]["favorites"])
          and base.as_uri() not in bookmarks.read_text())
    check("favorite-remove-returns-neighbor-focus", lambda s: s["focusedControl"] == runtime.name)
    exercise_drop(runtime, evidence, command, ipc, state, wait, check, key)


def exercise_drop(runtime, evidence, command, ipc, state, wait, check, key):
    # A separate GTK client sends the real Wayland text/uri-list offer. It does
    # not advertise Qt's document-portal filetransfer MIME on this private bus.
    sender = runtime / "drop-source.py"
    uri = (runtime / "Fieldwork/Read me.txt").as_uri()
    sender.write_text('''import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, Gdk, GtkLayerShell
window = Gtk.Window()
GtkLayerShell.init_for_window(window)
GtkLayerShell.set_layer(window, GtkLayerShell.Layer.OVERLAY)
GtkLayerShell.set_anchor(window, GtkLayerShell.Edge.TOP, True)
GtkLayerShell.set_anchor(window, GtkLayerShell.Edge.LEFT, True)
GtkLayerShell.set_keyboard_mode(window, GtkLayerShell.KeyboardMode.NONE)
window.set_default_size(140, 60)
item = Gtk.EventBox()
item.set_size_request(140, 60)
item.add(Gtk.Label(label="External file"))
item.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, [Gtk.TargetEntry.new("text/uri-list", 0, 0)], Gdk.DragAction.COPY)
item.connect("drag-begin", lambda *args: print("DRAG_BEGIN", flush=True))
item.connect("drag-end", lambda *args: print("DRAG_END", flush=True))
def data(widget, context, selection, info, time):
    print("DRAG_DATA_GET", flush=True)
    selection.set_uris([''' + json.dumps(uri) + '''])
item.connect("drag-data-get", data)
window.add(item)
window.show_all()
Gtk.main()
''')
    with (evidence / "drop-source.log").open("w") as log:
        child = subprocess.Popen(["timeout", "30", "python3", "-B", str(sender)], stdout=log, stderr=subprocess.STDOUT)
        try:
            time.sleep(1)
            command(["grim", evidence / "drop-source-ready.png"])
            command(["ydotool", "drag", 65, 30, 500, 400, 0])
            wait(lambda s: s["ready"] and s["path"] == str(runtime / "Fieldwork") and s["name"] == "Read me.txt")
            check("external-Wayland-drop-locates-without-accept", lambda s: s["selected"] == [str(runtime / "Fieldwork/Read me.txt")] and not s["settled"])
        finally:
            child.terminate(); child.wait(timeout=10)
    key(1)
    ipc("open", "open"); wait(lambda s: s["ready"] and s["focus"] == "listing")
