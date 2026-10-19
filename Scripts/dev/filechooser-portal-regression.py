#!/usr/bin/env python3
"""FileChooser frontend/wire regressions in the assigned filechooser VM.

python3 -B Scripts/dev/filechooser-portal-regression.py --source sources/LABEL --label portal-LABEL
Uses a private bus and real xdg-desktop-portal, never another backend.
"""

import argparse
import json
import os
from pathlib import Path
import sys
import time
import uuid

from filechooser_regression import Run, guest


def portal_call():
    guest()
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    p = argparse.ArgumentParser()
    p.add_argument("--call", choices=["OpenFile", "SaveFile", "SaveFiles"], required=True)
    p.add_argument("--options", required=True)
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    values = json.loads(a.options)
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    token = "filechooser_" + uuid.uuid4().hex
    predicted = "/org/freedesktop/portal/desktop/request/" + conn.get_unique_name()[1:].replace(".", "_") + "/" + token
    options = {"handle_token": GLib.Variant("s", token)}
    types = {"multiple": "b", "directory": "b", "modal": "b", "accept_label": "s", "current_name": "s",
             "filters": "a(sa(us))", "current_filter": "(sa(us))", "choices": "a(ssa(ss)s)"}
    for key, value in values.items():
        if key in ("current_folder", "current_file"):
            options[key] = GLib.Variant("ay", os.fsencode(value) + b"\0")
        elif key == "files":
            options[key] = GLib.Variant("aay", [os.fsencode(n) + b"\0" for n in value])
        elif key in types:
            options[key] = GLib.Variant(types[key], value)
    loop = GLib.MainLoop()
    out = {"method": a.call, "predicted": predicted, "response": None, "results": None, "types": {}, "count": 0}
    def write():
        pending = a.out.with_name(a.out.name + ".pending")
        pending.write_text(json.dumps(out, indent=2))
        pending.replace(a.out)
    def response(conn, sender, path, iface, signal, params):
        out["count"] += 1
        out["response"], out["results"] = params.unpack()
        d = params.get_child_value(1)
        out["types"] = {d.get_child_value(i).get_child_value(0).get_string(): d.get_child_value(i).get_child_value(1).get_variant().get_type_string() for i in range(d.n_children())}
        write()
        GLib.timeout_add(500, lambda: (loop.quit(), False)[1])
    conn.signal_subscribe("org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request", "Response", predicted, None, Gio.DBusSignalFlags.NONE, response)
    reply = conn.call_sync("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.FileChooser", a.call,
                           GLib.Variant("(ssa{sv})", (values.get("parent_window", ""), "File chooser " + a.call, options)),
                           GLib.VariantType("(o)"), Gio.DBusCallFlags.NONE, 10000, None)
    out["handle"] = reply.unpack()[0]
    assert out["handle"] == predicted
    write()
    if values.get("close"):
        def close():
            conn.call_sync("org.freedesktop.portal.Desktop", out["handle"], "org.freedesktop.portal.Request", "Close", None, None, Gio.DBusCallFlags.NONE, 5000, None)
            out["closed"] = True
            write()
            GLib.timeout_add(500, lambda: (loop.quit(), False)[1])
            return False
        GLib.timeout_add(1200, close)
    GLib.timeout_add_seconds(30, lambda: (loop.quit(), False)[1])
    loop.run(); write()
    assert out.get("closed") or out["count"] == 1, out
    return 0


def suite(r):
    folder = str(r.fixtures)
    filters = [["Text", [[0, "*.txt"]]], ["Images", [[1, "image/*"]]]]
    choices = [["quality", "Quality", [["full", "Full"], ["small", "Small"]], "small"], ["metadata", "Metadata", [], "true"]]
    proc, out = r.call("OpenFile", current_folder=folder, accept_label="Choose this", modal=False,
                       parent_window="wayland:test-parent", filters=filters, current_filter=filters[0], choices=choices)
    s = r.state()["requests"][0]
    r.check("title-label-parent-modal", s["label"] == "Choose this" and s["parent"] == "wayland:test-parent" and s["modal"] is False, s)
    r.check("current-filter-preselected", s["filter"] == filters[0] and s["names"] == ["Chosen.txt"], s)
    r.check("choices-initial-values", s["choices"] == {"quality": "small", "metadata": "true"}, s)
    r.key(102); r.key(28)
    data = r.result(proc, out)
    r.check("OpenFile-consumer-uri-and-read", data["response"] == 0 and data["results"]["uris"] == [(r.fixtures / "Chosen.txt").as_uri()] and (r.fixtures / "Chosen.txt").read_text() == "File chooser consumer fixture\n", data)
    r.check("OpenFile-types-and-options", data["types"] == {"uris": "as", "choices": "a(ss)", "current_filter": "(sa(us))"} and data["results"]["choices"] == [["quality", "small"], ["metadata", "true"]] and data["results"]["current_filter"] == filters[0], data)
    # writable is consumed by the frontend. Assert the implementation wire, not
    # a frontend key which the FileChooser XML deliberately doesn't expose.
    wire = [json.loads(l) for l in (r.output / "wire.jsonl").read_text().splitlines() if l.startswith("{")]
    replies = [x for x in wire if x.get("type") == "method_return" and x.get("payload", {}).get("type") == "ua{sv}"]
    r.check("backend-writable-bool", any(x["payload"]["data"][1].get("writable") == {"type": "b", "data": True} for x in replies), replies)
    proc, out = r.call("OpenFile", current_folder=folder, filters=filters, current_filter=filters[0], choices=choices)
    r.ipc("filter"); r.ipc("choice", "quality", "full"); r.ipc("choice", "metadata", "false")
    r.wait(lambda s: s["requests"][0]["names"] == ["Icon.png"])
    r.ipc("select", str(r.fixtures / "Icon.png")); r.ipc("accept")
    data = r.result(proc, out)
    r.check("changed-filter-and-choices-returned", data["results"]["current_filter"] == filters[1] and data["results"]["choices"] == [["quality", "full"], ["metadata", "false"]] and data["results"]["uris"] == [(r.fixtures / "Icon.png").as_uri()], data)
    proc, out = r.call("OpenFile", current_folder=folder, multiple=True)
    r.key(30, 29); r.ipc("accept"); data = r.result(proc, out)
    r.check("multiple-selection", data["response"] == 0 and sorted(data["results"]["uris"]) == sorted(p.as_uri() for p in r.fixtures.iterdir()), data)
    proc, out = r.call("OpenFile", current_folder=folder, directory=True, modal=True)
    r.check("modal-true", r.state()["requests"][0]["modal"] is True)
    r.ipc("accept"); data = r.result(proc, out)
    r.check("directory-current-folder", data["results"]["uris"] == [r.fixtures.as_uri()], data)
    for name in ("Saved.txt", "日本語.txt", "a#b?c%20d e.txt"):
        proc, out = r.call("SaveFile", current_folder=folder, current_name=name, accept_label="Store")
        r.check("SaveFile-name-and-label", r.state()["requests"][0]["saveName"] == name and r.state()["requests"][0]["label"] == "Store")
        r.key(28); data = r.result(proc, out)
        target = r.fixtures / name
        r.check("SaveFile-uri-no-premature-write", data["response"] == 0 and data["results"]["uris"] == [target.as_uri()] and not target.exists(), data)
        target.write_text("File chooser saved by consumer\n")
        r.check("SaveFile-consumer-write-read", target.read_text() == "File chooser saved by consumer\n")
        target.unlink()
    proc, out = r.call("SaveFile", current_file=str(r.fixtures / "Chosen.txt"))
    s = r.wait(lambda s: s["requests"][0]["selected"] == [str(r.fixtures / "Chosen.txt")])["requests"][0]
    r.check("current-file-preselection-and-name", s["saveName"] == "Chosen.txt", s)
    r.key(28)
    r.wait(lambda s: s["requests"][0]["replace"] == str(r.fixtures / "Chosen.txt"))
    r.check("SaveFile-awaits-Replace", json.loads(out.read_text())["count"] == 0 and proc.poll() is None)
    r.key(28); data = r.result(proc, out)
    r.check("SaveFile-current-file-replaced", data["response"] == 0 and data["results"]["uris"] == [(r.fixtures / "Chosen.txt").as_uri()], data)
    names = ["second #.txt", "first.txt", "日本語.txt"]
    for n in names[:2]:
        (r.fixtures / n).write_text("existing " + n)
    proc, out = r.call("SaveFiles", current_folder=folder, files=names)
    r.ipc("accept")
    for n in names[:2]:
        r.wait(lambda s: s["requests"][0]["replace"] == str(r.fixtures / n))
        r.check("SaveFiles-each-name-awaits-Replace", json.loads(out.read_text())["count"] == 0)
        r.ipc("replace")
    data = r.result(proc, out)
    r.check("SaveFiles-app-names-and-order", data["response"] == 0 and data["results"]["uris"] == [(r.fixtures / n).as_uri() for n in names], data)
    r.check("SaveFiles-does-not-create-or-replace", not (r.fixtures / names[2]).exists() and all((r.fixtures / n).read_text() == "existing " + n for n in names[:2]))
    proc, out = r.call("OpenFile", current_folder=folder)
    before = r.state()["requests"][0]
    r.ipc("navigate", folder + "/Missing")
    s = r.wait(lambda s: bool(s["requests"][0]["error"]))["requests"][0]
    r.check("failed-folder-keeps-path-and-listing", s["path"] == before["path"] and s["names"] == before["names"], s)
    r.key(1); data = r.result(proc, out)
    r.check("Escape-cancel", data["response"] == 1 and not data["results"].get("uris"), data)
    proc, out = r.call("OpenFile", current_folder=folder)
    r.ipc("cancelTwice"); data = r.result(proc, out)
    r.check("cancel-twice-single-settle", data["response"] == 1, data)
    proc, out = r.call("OpenFile", current_folder=folder, close=True)
    proc.wait(timeout=15)
    r.wait(lambda s: not s["requests"])
    data = json.loads(out.read_text())
    # Close suppresses the frontend Response by contract; the implementation
    # returns cancellation exactly once (assert below at its wire boundary).
    r.check("frontend-Close-cleans-request", proc.returncode == 0 and data.get("closed") and data["count"] == 0, data)
    proc, out = r.call("OpenFile", current_folder=folder)
    proc.terminate(); proc.wait(timeout=5)
    r.wait(lambda s: not s["requests"])
    r.check("app-exit-cleans-request", not r.state()["requests"])
    time.sleep(.5)
    wire = [json.loads(l) for l in (r.output / "wire.jsonl").read_text().splitlines() if l.startswith("{")]
    calls = [x for x in wire if x.get("type") == "method_call" and x.get("interface") == "org.freedesktop.impl.portal.FileChooser" and x.get("member") in ("OpenFile", "SaveFile", "SaveFiles")]
    counts = [{"handle": x["payload"]["data"][0], "method": x["member"], "replies": sum(y.get("type") == "method_return" and y.get("destination") == x["sender"] and y.get("reply_cookie") == x["cookie"] for y in wire)} for x in calls]
    r.check("every-backend-request-settles-exactly-once-including-Close", bool(counts) and all(x["replies"] == 1 for x in counts), counts)
    r.check("daemon-explicit-Atmosphera-route", "Using atmosphera.portal for org.freedesktop.impl.portal.FileChooser" in (r.output / "portal.log").read_text())


def main():
    if "--call" in sys.argv:
        return portal_call()
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--label", required=True)
    a = p.parse_args()
    r = Run(a.source, a.label)
    try:
        r.start(); suite(r); r.finish()
    except Exception as error:
        r.failure = repr(error)
        raise
    finally:
        r.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
