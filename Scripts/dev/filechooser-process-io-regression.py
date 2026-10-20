#!/usr/bin/env python3
"""Verify native child I/O and private virtual-input resource lifetimes."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from filechooser_isolation import ROOT, enter, input_command, profile_env


def main():
    enter()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--legacy-keyboard", action="store_true", help="reproduce transient-keyboard FD retention")
    args = parser.parse_args()
    runtime, output = ROOT / "runtime" / args.label, ROOT / "evidence" / args.label
    runtime.mkdir(); output.mkdir()
    shell = runtime / "shell"
    shutil.copytree(args.source.resolve(), shell, symlinks=True)
    env = profile_env(runtime / "profile")
    rows = []
    for mode, streams in (("none", ""), ("stdout", "stdout: StdioCollector {}"),
                          ("both", "stdout: StdioCollector {} stderr: StdioCollector {}"), ("detached", ""),
                          ("keyboard", ""), ("owned", "")):
        probe = shell / (mode + ".qml")
        run = ("OwnedProcess.run(root, ['/usr/bin/true'], null, function(result) { root.completed++; });"
               if mode == "owned" else "var child = factory.createObject(root); child.running = true;")
        if mode == "detached":
            run = "Quickshell.execDetached(['/usr/bin/true']); root.completed++;"
        if mode == "keyboard":
            run = "root.completed++;"
        probe.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
''' + ('import "Helpers/OwnedProcess.js" as OwnedProcess\n' if mode == "owned" else '') + '''
ShellRoot {
  id: root
  property int completed: 0
  property string typed: ""
  property bool typingFocused: false
  Component {
    id: factory
    Process {
      command: ["/usr/bin/true"]
      ''' + streams + '''
      onExited: { root.completed++; destroy(); }
    }
  }
  ''' + ('''FloatingWindow {
    visible: true
    implicitWidth: 320
    implicitHeight: 200
    TextInput {
      anchors.fill: parent
      focus: true
      onActiveFocusChanged: root.typingFocused = activeFocus
      onTextChanged: root.typed = text
    }
  }''' if mode == "keyboard" else '') + '''
  IpcHandler {
    target: "processIo"
    function run(): void { ''' + run + ''' }
    function state(): string { return JSON.stringify({completed: root.completed, pid: Quickshell.processId, typed: root.typed, focused: root.typingFocused}); }
    function quit(): void { Qt.quit(); }
  }
}
''')
        def ipc(member):
            return subprocess.run(["timeout", "8", "qs", "-p", str(probe), "ipc", "call", "processIo", member],
                                  env=env, capture_output=True, text=True, check=True, timeout=12).stdout.strip()
        def state():
            return json.loads(ipc("state"))
        with (output / (mode + ".log")).open("w") as log:
            probe_env = dict(env, WAYLAND_DEBUG="client") if mode == "keyboard" else env
            process = subprocess.Popen(["timeout", "70", "qs", "-p", str(probe)], env=probe_env, stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 12
                while True:
                    try:
                        before = state()
                        break
                    except (subprocess.CalledProcessError, json.JSONDecodeError):
                        assert time.monotonic() < deadline
                        time.sleep(.1)
                pid = before["pid"]
                def send_input(*values):
                    subprocess.run(["timeout", "10", *input_command(["ydotool", *values])], env=env, check=True, timeout=15)
                def wait_text(expected):
                    deadline = time.monotonic() + 5
                    while state()["typed"] != expected:
                        assert time.monotonic() < deadline, state()
                        time.sleep(.05)
                if mode == "keyboard":
                    deadline = time.monotonic() + 5
                    while not state()["focused"]:
                        assert time.monotonic() < deadline
                        time.sleep(.05)
                    # Observe the actual TextInput consumer, including Unicode,
                    # modifiers and deletion, before the repeated-key FD probe.
                    send_input("type", "Field notes résumé 日本語 #?% →")
                    wait_text("Field notes résumé 日本語 #?% →")
                    send_input("key", "29:1", "30:1", "30:0", "29:0")
                    send_input("key", "14:1", "14:0")
                    wait_text("")
                    send_input("key", "42:1", "30:1", "30:0", "42:0")
                    wait_text("A")
                    time.sleep(.2)
                def descriptors():
                    result = {}
                    for fd in Path(f"/proc/{pid}/fd").iterdir():
                        try:
                            result[fd.name] = os.readlink(fd)
                        except FileNotFoundError:
                            pass
                    return result
                start = descriptors()
                for _ in range(25):
                    if mode == "keyboard":
                        if args.legacy_keyboard:
                            subprocess.run(["timeout", "5", "wtype", "-k", "Shift_L"], env=env, check=True, timeout=8)
                        else:
                            send_input("key", "42:1", "42:0")
                    ipc("run")
                deadline = time.monotonic() + 12
                while state()["completed"] != 25:
                    assert time.monotonic() < deadline
                    time.sleep(.1)
                time.sleep(.5)
                end = descriptors()
                row = {"mode": mode, "launcher_pid": process.pid, "renderer_pid": pid,
                       "before": start, "after": end, "delta": len(end) - len(start),
                       "consumer_text": state()["typed"], "legacy_keyboard": args.legacy_keyboard,
                       "no_keymap_events": (output / (mode + ".log")).read_text().count(".keymap(0,"),
                       "null_delta": sum(p == "/dev/null" for p in end.values()) - sum(p == "/dev/null" for p in start.values())}
                rows.append(row)
                print(json.dumps({k: v for k, v in row.items() if k not in ("before", "after")}), flush=True)
            finally:
                ipc("quit"); process.wait(timeout=12)
    passed = all(row["delta"] == 0 and row["null_delta"] == 0 and row["no_keymap_events"] == 0 for row in rows)
    (output / "result.json").write_text(json.dumps({"passed": passed, "rows": rows}, indent=2))
    assert passed, "child I/O or virtual input retained descriptors"


if __name__ == "__main__":
    main()
