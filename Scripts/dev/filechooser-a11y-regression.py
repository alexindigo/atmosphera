#!/usr/bin/env python3
"""AT-SPI and Orca consumer proof in the existing private guest session."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time

from filechooser_isolation import enter, input_command
from filechooser_profile import current_profile, exact_source, profile_argument
from filechooser_regression import SCRIPTS, guest


def main():
    enter(resource_subject=True)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--inspect", action="store_true", help="Preserve the initial consumer tree before asserting")
    profile_argument(parser)
    args = parser.parse_args()
    guest()
    source = args.source.resolve()
    assert exact_source(source)
    assert re.fullmatch(r"[a-z0-9][a-z0-9.-]*", args.label)
    runtime = current_profile().runtime / args.label
    evidence = current_profile().evidence / args.label
    probe = runtime / "shell/filechooser-harness.qml"
    env = dict(os.environ, GSETTINGS_BACKEND="memory", ATSPI_DBUS_IMPLEMENTATION="dbus-daemon")
    stack = current_profile().runtime / (args.label + "-a11y")
    stack.mkdir()
    # The native launcher overrides accessibility.conf's default listen address
    # with its XDG_RUNTIME_DIR/at-spi/bus. Neither bus reaches a login session.
    env["AT_SPI_BUS_ADDRESS"] = "unix:path=" + str(Path(env["XDG_RUNTIME_DIR"]) / "at-spi/bus")
    children, logs, cases, events = [], [], [], []
    complete, failure, registry_thread = False, "", None

    def start(argv, name):
        log = (stack / (name + ".log")).open("w")
        logs.append(log)
        child = subprocess.Popen(argv, env=env, stdout=log, stderr=subprocess.STDOUT)
        children.append(child)
        return child

    def command(argv):
        if argv[0] == "ydotool":
            argv = input_command(argv)
        return subprocess.run(["timeout", "12", *map(str, argv)], env=env,
                              capture_output=True, text=True, check=True, timeout=18).stdout.strip()

    def ipc(member, *values):
        return command(["qs", "-p", probe, "ipc", "call", "filechooserHarness", member, *values])

    def state():
        return json.loads(ipc("state"))

    def wait(predicate, seconds=15):
        end = time.monotonic() + seconds
        last = None
        while time.monotonic() < end:
            try:
                last = state()
                if predicate(last):
                    return last
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            time.sleep(.15)
        raise AssertionError("Timed out: " + json.dumps(last))

    def key(code, mod=None):
        command(["ydotool", "key", *([f"{mod}:1"] if mod else []), f"{code}:1", f"{code}:0", *([f"{mod}:0"] if mod else [])])
        time.sleep(.25)

    def check(name, value):
        cases.append({"case": name, "pass": bool(value)})
        print(name, "PASS" if value else "FAIL", flush=True)
        if not value:
            cases[-1]["state"] = state()
            dump("failure-tree")
        assert value, name

    try:
        assert len(env["AT_SPI_BUS_ADDRESS"].removeprefix("unix:path=")) < 100
        start(["/usr/lib/at-spi-bus-launcher", "--launch-immediately"], "bus")
        end = time.monotonic() + 10
        while not Path(env["AT_SPI_BUS_ADDRESS"].removeprefix("unix:path=")).exists():
            assert children[0].poll() is None and time.monotonic() < end, "private accessibility bus unavailable"
            time.sleep(.05)
        start(["/usr/lib/at-spi2-registryd"], "registry")
        end = time.monotonic() + 10
        while "org.a11y.atspi.Registry" not in command(["busctl", "--address", env["AT_SPI_BUS_ADDRESS"], "list"]):
            assert children[-1].poll() is None and time.monotonic() < end, "private AT-SPI registry unavailable"
            time.sleep(.05)
        # espeak-ng feeds only the supervisor's private PipeWire null sink.
        config = stack / "speech-config"
        config.mkdir()
        (config / "speechd.conf").write_text('AddModule "espeak-ng" "sd_espeak-ng" "espeak-ng.conf"\nDefaultModule espeak-ng\nAudioOutputMethod "pipewire"\n')
        env["SPEECHD_ADDRESS"] = "unix_socket:" + str(stack / "speech.sock")
        start(["speech-dispatcher", "-s", "-C", str(config), "-S", str(stack / "speech.sock"),
               "-P", str(stack / "speech.pid"), "-L", str(stack), "-l", "2"], "speech")
        end = time.monotonic() + 10
        while not (stack / "speech.sock").exists():
            assert children[-1].poll() is None and time.monotonic() < end, "private speech dispatcher unavailable"
            time.sleep(.05)
        orca = start(["orca", "--debug-file", str(stack / "orca-debug.log")], "orca")
        # Import after establishing the native bus. The GLib event loop is
        # required for real focus/announcement events, not pumpQueuedEvents().
        os.environ["AT_SPI_BUS_ADDRESS"] = env["AT_SPI_BUS_ADDRESS"]
        import pyatspi
        from gi.repository import GLib

        def event_received(event):
            try:
                events.append({"type": event.type, "name": event.source.name,
                               "role": event.source.getRoleName(), "detail1": event.detail1,
                               "data": str(event.any_data)})
            except Exception as error:
                events.append({"error": repr(error)})

        pyatspi.Registry.registerEventListener(event_received, "object:state-changed:focused", "object:announcement")
        registry_thread = threading.Thread(target=pyatspi.Registry.start, daemon=True)
        registry_thread.start()
        harness = start([sys.executable, "-B", str(SCRIPTS / "filechooser-harness.py"),
                         "--source", str(source), "--label", args.label], "harness")
        wait(lambda s: s["ready"] and s["nativeActive"], 40)
        time.sleep(2)

        def tree():
            result = []
            def visit(node, ancestors, depth=0):
                if depth > 24:
                    raise AssertionError("accessibility tree cycle")
                try:
                    role, name, states = node.getRoleName(), node.name, node.getState()
                    row = {"name": name, "role": role, "ancestors": ancestors,
                           "focused": states.contains(pyatspi.STATE_FOCUSED),
                           "selected": states.contains(pyatspi.STATE_SELECTED),
                           "showing": states.contains(pyatspi.STATE_SHOWING),
                           "sensitive": states.contains(pyatspi.STATE_SENSITIVE), "object": node}
                    result.append(row)
                    for child in node:
                        if child is not None:
                            visit(child, ancestors + [name or role], depth + 1)
                except GLib.Error:
                    pass  # A retired native accessible is not a current control.
            visit(pyatspi.Registry.getDesktop(0), [])
            return result

        def dump(name):
            rows = [{k: v for k, v in row.items() if k != "object"} for row in tree()]
            (evidence / (name + ".json")).write_text(json.dumps(rows, indent=2))
            return rows

        def focused(name, role=None):
            return any(row["focused"] and row["name"] == name and (role is None or row["role"] == role) for row in tree())

        def focus(name):
            for _ in range(60):
                if state()["focusedControl"] == name:
                    return
                key(15)
            raise AssertionError("Unreachable control: " + name)

        def open_request(method, **options):
            options.setdefault("filters", [["All files", [[0, "*"]]]])
            options.update(current_folder=list(os.fsencode(runtime / "Fieldwork") + b"\0"), title="Accessible file chooser")
            ipc("openRequest", method, "dev.filechooser.a11y", json.dumps(options))
            wait(lambda s: s["ready"] and s["nativeActive"] and not s["settled"]
                 and s["focus"] == ("name" if method == "save" else "listing"))

        dump("initial-tree")
        if args.inspect:
            complete = True
            return 0
        key(102)
        s = state()
        interactive = {"button", "combo box", "check box", "text", "scroll bar", "menu item", "list item", "slider"}
        check("AT-SPI-visible-controls-and-items-named", all(row["name"] for row in tree() if row["showing"] and row["sensitive"] and row["role"] in interactive))
        check("AT-SPI-current-grid-item-focus", focused(s["name"], "list item"))
        check("AT-SPI-list-role-and-name", any(row["role"] == "list" and row["name"] == "Files" for row in tree()))
        key(107); key(105, 29)
        s = state()
        check("AT-SPI-cursor-is-not-selection", focused(s["name"], "list item") and s["name"] not in [Path(p).name for p in s["selected"]])
        key(57, 29)
        check("AT-SPI-selection-state", any(row["name"] == s["name"] and row["selected"] and row["focused"] for row in tree()))
        ipc("list"); key(107)
        check("AT-SPI-current-detail-item-focus", focused(state()["name"], "list item"))
        dump("details-tree")
        # The same accessible action as a pointer press selects; it must not
        # accept the request or invoke a caller-specific shortcut.
        item = next(row["object"] for row in tree() if row["name"] == state()["name"] and row["role"] == "list item")
        action = item.queryAction()
        check("AT-SPI-item-action-exposed", action.nActions > 0)
        action.doAction(0)
        wait(lambda s: s["selected"])
        check("AT-SPI-item-action-selects-without-accept", not state()["settled"])
        Path(state()["selected"][0]).unlink()
        wait(lambda s: s["count"] == 10 and s["cursor"] == -1)
        check("AT-SPI-removed-cursor-focus-returns-to-list", focused("Files", "list"))
        focus("Sort by"); key(57); key(108); key(1)
        check("AT-SPI-combo-focus-return", focused("Sort by", "combo box"))
        # Tab order is traversed in both directions through real native input.
        open_request("open", multiple=True)
        key(15)
        check("focus-order-listing-to-footer", state()["focusedControl"] == "File type")
        key(15, 42)
        check("focus-order-footer-to-current-item", state()["focus"] == "listing")
        order = []
        for _ in range(60):
            key(15)
            if state()["focus"] == "listing":
                break
            name = state()["focusedControl"]
            order.append(name)
            assert name and name != "unnamed" and any(row["focused"] and row["showing"] and row["sensitive"] for row in tree()), name
        else:
            raise AssertionError("Tab did not cycle to the listing")
        reverse = []
        for _ in range(len(order)):
            key(15, 42)
            reverse.append(state()["focusedControl"])
        key(15, 42)
        (stack / "focus-order.json").write_text(json.dumps({"forward": order, "reverse": reverse}, indent=2))
        check("focus-order-named-visible-reversible-cycle", reverse == list(reversed(order)) and state()["focus"] == "listing")
        key(38, 29)
        check("AT-SPI-location-field-name", focused("Location", "text"))
        key(1)
        check("AT-SPI-location-Escape-returns-current-item", state()["focus"] == "listing")
        command(["ydotool", "key", "29:1", "42:1", "49:1", "49:0", "42:0", "29:0"])
        wait(lambda s: s["focusedControl"] == "Folder name")
        command(["ydotool", "type", "."]); key(28)
        wait(lambda s: bool(s["createFolderError"]))
        time.sleep(.5)
        check("AT-SPI-inline-error-announcement", any("Enter a name" in e.get("data", "") for e in events))
        key(1)
        check("AT-SPI-new-folder-Escape-focus-return", state()["focus"] == "listing")
        focus("Filter names"); command(["ydotool", "type", "no-match-xyz"])
        wait(lambda s: s["count"] == 0)
        time.sleep(1)
        check("AT-SPI-count-announcement", any("0" in e.get("data", "") and "item" in e.get("data", "") for e in events))
        key(1)
        # Native child menus must expose a focused MenuItem, then return to
        # their actual trigger on Escape rather than an unrelated field.
        focus("Ancestor folders"); key(28)
        wait(lambda s: s["pathEntry"]["location"]["menuOpen"])
        check("AT-SPI-menu-current-row-focus", any(row["role"] == "menu item" and row["focused"] for row in tree()))
        key(1)
        check("AT-SPI-menu-focus-return", focused("Ancestor folders"))
        open_request("open")
        key(102); key(106)
        key(127)
        wait(lambda s: s["operations"]["menu"]["open"])
        check("AT-SPI-file-actions-menu-named", any(row["role"] == "popup menu" and row["name"] == "File actions" for row in tree()))
        check("AT-SPI-file-actions-current-row", focused("Rename", "menu item"))
        for _ in range(next(i for i, row in enumerate(state()["operations"]["menu"]["entries"]) if row["key"] == "sort")):
            key(108)
        key(106)
        wait(lambda s: s["operations"]["menu"]["depth"] == 1)
        check("AT-SPI-sort-submenu-current-row", focused("Name", "menu item"))
        dump("file-actions-submenu-tree")
        key(1)
        check("AT-SPI-submenu-Escape-returns-parent-menu", state()["operations"]["menu"]["open"] and state()["operations"]["menu"]["depth"] == 0 and focused("Rename", "menu item"))
        key(1)
        check("AT-SPI-file-actions-focus-return", focused(state()["name"], "list item"))
        key(60); wait(lambda s: s["operations"]["renaming"])
        check("AT-SPI-inline-rename-named-field", focused("New name", "text"))
        command(["ydotool", "type", "../invalid"]); key(28)
        wait(lambda s: s["operations"]["renameError"])
        time.sleep(.5)
        check("AT-SPI-rename-error-announced", any("Enter a name" in e.get("data", "") for e in events))
        key(1)
        check("AT-SPI-inline-rename-focus-return", focused(state()["name"], "list item"))
        key(111, 42); wait(lambda s: s["operations"]["pendingDelete"])
        check("AT-SPI-delete-confirmation-safe-default", focused("Cancel", "button"))
        check("AT-SPI-delete-confirmation-named", any(row["role"] == "dialog" and row["name"] == "Delete permanently?" for row in tree()))
        key(15); key(15)
        check("AT-SPI-delete-Tab-contained", focused("Cancel", "button"))
        dump("delete-confirmation-tree")
        key(1)
        check("AT-SPI-delete-cancel-restores-current-item", focused(state()["name"], "list item") and not state()["settled"])
        open_request("save", current_name="Field notes.md")
        key(28); wait(lambda s: bool(s["replace"]))
        check("AT-SPI-confirmation-safe-focus", focused("Change name", "button"))
        check("AT-SPI-confirmation-named-dialog", any(row["role"] == "dialog" and row["name"] == "Replace existing file" for row in tree()))
        dump("confirmation-tree")
        key(15); key(15)
        check("confirmation-Tab-contained", state()["focusedControl"] == "Change name")
        key(1)
        check("AT-SPI-confirmation-return-to-name", focused("File name", "text") and not state()["settled"])
        open_request("open")
        ipc("focusListing"); key(102); key(57)
        wait(lambda s: s["preview"])
        key(15); key(15)
        check("preview-Tab-contained", any(row["focused"] and row["name"] == "Close" and "Empty" in row["ancestors"] for row in tree()))
        key(1)
        check("AT-SPI-preview-focus-return", state()["focus"] == "listing" and focused(state()["name"], "list item"))
        focus("Compact view"); key(28)
        ipc("focusListing"); key(102); key(108)
        check("AT-SPI-compact-current-item-focus", state()["view"] == "compact" and focused(state()["name"], "list item"))
        focus("Zoom")
        check("AT-SPI-zoom-named-slider", focused("Zoom", "slider"))
        key(107)
        slider = next(row["object"] for row in tree() if row["name"] == "Zoom" and row["role"] == "slider")
        check("AT-SPI-zoom-native-value-and-rendered-consumer", slider.queryValue().currentValue == 6 and state()["views"]["iconSize"] == 64)
        focus("Thumbnails"); key(57)
        check("AT-SPI-thumbnail-toggle", focused("Thumbnails", "check box") and not state()["views"]["thumbnails"])
        focus("List view"); key(28)
        focus("Name column width"); before = state()["columnGeometry"]["header"][1]; key(106)
        check("AT-SPI-column-resizer-keyboard", focused("Name column width") and state()["columnGeometry"]["header"][1] > before)
        focus("Dialog size"); before = state()["layoutGeometry"]["height"]; key(103)
        check("AT-SPI-dialog-resizer-keyboard", focused("Dialog size") and state()["layoutGeometry"]["height"] < before)
        dump("view-controls-tree")
        dump("final-tree")
        ipc("quit"); harness.wait(timeout=15)
        check("a11y-runtime-clean", harness.returncode == 0 and not re.search(r"TypeError|ReferenceError|Cannot assign|Binding loop|Unable to assign", (evidence / "harness.log").read_text()))
        time.sleep(1)
        debug = (stack / "orca-debug.log").read_text()
        check("Orca-real-focus-events", "object:state-changed:focused" in debug and "Field notes.md" in debug)
        check("Orca-generated-speech", bool(re.search(r"SPEECH OUTPUT.*(?:Field|Folder|file|Files)", debug)))
        check("Orca-spoke-errors-and-counts", bool(re.search(r"SPEECH OUTPUT.*Enter a name", debug)) and bool(re.search(r"SPEECH OUTPUT.*0 items", debug)))
        check("Orca-still-running", orca.poll() is None)
        complete = True
    except Exception as error:
        failure = repr(error)
        raise
    finally:
        if probe.exists():
            try:
                ipc("quit")
            except subprocess.CalledProcessError:
                pass
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=12)
        if registry_thread is not None:
            pyatspi.Registry.stop()
            registry_thread.join(timeout=5)
        for log in logs:
            log.close()
        result = {"complete": complete, "failure": failure, "cases": cases, "events": events}
        (stack / "result.json").write_text(json.dumps(result, indent=2))
        print(json.dumps({"complete": complete, "cases": len(cases), "failure": failure}), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
