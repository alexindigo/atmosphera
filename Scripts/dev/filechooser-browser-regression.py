#!/usr/bin/env python3
"""Real headed Firefox/Chromium portal, upload, mkdir and overwrite consumers."""
import argparse
import http.server
import json
import os
from pathlib import Path
import re
import subprocess
import threading
import time
import urllib.parse

from filechooser_isolation import enter
from filechooser_profile import current_profile, profile_argument
from filechooser_regression import Run
from qml_probe import inject_probe


def main():
    enter(runtime_seconds=700, oom_floor=True, browser_resources=True, resource_subject=True)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--browser", choices=("firefox", "chromium"), required=True)
    profile_argument(parser)
    args = parser.parse_args()
    run = Run(args.source, args.label)
    events = []
    payload = args.browser + " portal download consumer\n"
    upload = args.browser + " actual upload " + args.label + "\n"
    (run.fixtures / "Upload.txt").write_text(upload)

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_POST(self):
            data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            data["userAgent"] = self.headers.get("User-Agent", "")
            events.append(data)
            self.send_response(204); self.end_headers()
        def do_GET(self):
            if self.path.startswith("/favicon.ico"):
                self.send_response(204); self.end_headers(); return
            query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
            seq, action = query.get("seq", ["initial"])[0], query.get("action", ["open"])[0]
            text = '''<!doctype html><meta charset="utf-8"><title>Browser portal proof</title>
<style>body{background:#20252b;color:#eee;font:18px sans-serif;padding:40px}button,input{font:inherit;margin:16px;padding:12px}</style>
<h1>File chooser browser proof</h1><input id="upload" type="file" accept="text/plain"><button id="save">Save payload</button>
<script>
const seq=SEQ, action=ACTION, payload=PAYLOAD;
const record=data=>fetch('/event',{method:'POST',body:JSON.stringify({...data,seq})});
const input=document.querySelector('#upload'), button=document.querySelector('#save');
const ready=reason=>{const target=action==='open'?input:button;target.focus();record({kind:'ready',reason,action,focused:document.hasFocus()&&document.activeElement===target});};
window.addEventListener('load',()=>{ready('load');requestAnimationFrame(()=>ready('frame'));});window.addEventListener('focus',()=>ready('focus'));
input.onchange=async()=>{try{const file=input.files[0];if(file)await record({kind:'upload',name:file.name,text:await file.text()});}catch(error){record({kind:'upload-error',error:String(error)});}};
button.onclick=event=>{record({kind:'save-start',trusted:event.isTrusted});const link=document.createElement('a');link.href=URL.createObjectURL(new Blob([payload],{type:'text/plain'}));link.download='protected.txt';link.click();setTimeout(()=>URL.revokeObjectURL(link.href),30000);};
</script>'''.replace("SEQ", json.dumps(seq)).replace("ACTION", json.dumps(action)).replace("PAYLOAD", json.dumps(payload))
            body = text.encode()
            self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store"); self.send_header("Content-Length", str(len(body)))
            self.end_headers(); self.wfile.write(body)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": .05}, daemon=True)
    thread.start()
    url = "http://127.0.0.1:" + str(server.server_port) + "/"
    browser = None
    sequence = 0
    return_focus_after = 0
    def wait_for(predicate, seconds=25):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            result = predicate()
            if result: return result
            if browser is not None and browser.poll() is not None:
                raise AssertionError("owned browser exited: " + str(browser.returncode))
            time.sleep(.1)
        raise AssertionError("browser consumer deadline: " + json.dumps(run.state()))
    def request():
        requests = run.state()["requests"]
        return requests[0] if len(requests) == 1 else {}
    def opened(method):
        return run.wait(lambda s: len(s["requests"]) == 1 and s["requests"][0]["method"] == method
                        and s["requests"][0]["status"] == "ready" and s["requests"][0]["nativeActive"], 35)["requests"][0]
    def focus(label):
        for _ in range(50):
            if request().get("focusedControl") == label: return
            run.key(15)
        raise AssertionError("unreachable native chooser control: " + label)
    def navigate(path):
        run.key(38, 29); run.command(["ydotool", "type", str(path)]); run.key(28)
        wait_for(lambda: request().get("path") == str(path) and request().get("status") == "ready")
    def edit_name(name):
        focus("File name"); run.key(30, 29); run.command(["ydotool", "type", name])
        wait_for(lambda: request().get("saveName") == name)
    def visit(action):
        nonlocal sequence, return_focus_after
        if sequence:
            previous = args.browser + "-" + str(sequence)
            wait_for(lambda: any(e.get("kind") == "ready" and e.get("seq") == previous
                     and e.get("reason") == "focus" and e.get("focused") for e in events[return_focus_after:]), 35)
        sequence += 1
        seq = args.browser + "-" + str(sequence)
        target = url + "?" + urllib.parse.urlencode({"seq": seq, "action": action})
        run.key(38, 29); run.command(["ydotool", "type", target]); run.key(28)
        wait_for(lambda: any(e.get("kind") == "ready" and e.get("seq") == seq and e.get("focused") for e in events), 35)
        return_focus_after = len(events)
        run.key(28)
        if action == "save":
            wait_for(lambda: any(e.get("kind") == "save-start" and e.get("seq") == seq and e.get("trusted") for e in events))
        return seq
    try:
        # Observe public view state only in this disposable copy; the production
        # portal keeps the same interface and never reaches into its view tree.
        portal = run.shell / "Portals/FileChooserPortal.qml"
        text = portal.read_text()
        needle = "      Loader {\n        active: entry.output !== null"
        assert text.count(needle) == 1
        text = text.replace(needle, "      Loader {\n        id: observedLoader\n        active: entry.output !== null")
        text = inject_probe(text, "readonly property var observedWindow: observedLoader.item", root_id="entry")
        portal.write_text(text)
        (run.output / "observed-FileChooserPortal.qml").write_text(text)
        probe = (args.source / "Scripts/dev/fixtures/filechooser-browser.qml").read_text()
        run.start(qml=probe)
        profile = run.runtime / (args.browser + "-profile")
        profile.mkdir()
        if args.browser == "firefox":
            preferences = {"browser.shell.checkDefaultBrowser": False, "browser.startup.homepage_override.mstone": "ignore",
                "browser.aboutwelcome.enabled": False, "datareporting.policy.dataSubmissionPolicyBypassNotification": True,
                "datareporting.healthreport.uploadEnabled": False, "toolkit.telemetry.enabled": False,
                "widget.use-xdg-desktop-portal.file-picker": 1, "browser.download.useDownloadDir": False,
                "browser.download.folderList": 2, "browser.download.dir": str(run.fixtures), "browser.download.lastDir": str(run.fixtures),
                "browser.helperApps.neverAsk.saveToDisk": "text/plain", "browser.download.alwaysOpenPanel": False,
                "browser.newtab.preload": False,
                "dom.ipc.processCount": 1, "dom.ipc.processCount.webIsolated": 1,
                "dom.ipc.processPrelaunch.enabled": False, "dom.ipc.processPriorityManager.enabled": False}
            (profile / "user.js").write_text("".join("user_pref(" + json.dumps(k) + "," + json.dumps(v) + ");\n" for k, v in preferences.items()))
            argv = ["firefox", "--no-remote", "--profile", str(profile), url]
        else:
            (profile / "Default").mkdir()
            (profile / "Default/Preferences").write_text(json.dumps({"download": {"prompt_for_download": True,
                "default_directory": str(run.fixtures), "directory_upgrade": True}, "browser": {"check_default_browser": False}}))
            argv = ["chromium", "--ozone-platform=wayland", "--user-data-dir=" + str(profile), "--no-first-run",
                    "--no-default-browser-check", "--password-store=basic", "--disable-background-networking",
                    "--disable-component-update", "--disable-default-apps", "--disable-sync", "--renderer-process-limit=1", url]
            preferences = json.loads((profile / "Default/Preferences").read_text())
        (run.output / "browser-profile.json").write_text(json.dumps({"preferences": preferences,
            "rasterThreads": "1", "rayonThreads": "1", "allocator": run.env["MALLOC_CONF"],
            "THP_enabled": next(line.split()[1] for line in Path('/proc/self/status').read_text().splitlines() if line.startswith('THP_enabled:'))}, indent=2))
        original_env = run.env
        run.env = dict(run.env, TMPDIR=str(current_profile().workspace / "tmp"), MOZ_TMPDIR=str(current_profile().workspace / "tmp"),
                       GTK_USE_PORTAL="1", MOZ_ENABLE_WAYLAND="1", LP_NUM_THREADS="1", RAYON_NUM_THREADS="1")
        browser = run.launch(["timeout", "600", *argv], args.browser + ".log")
        run.env = original_env
        wait_for(lambda: any(e.get("kind") == "ready" and e.get("focused") for e in events), 40)

        visit("open"); opened("open"); navigate(run.fixtures)
        run.key(33, 29); run.command(["ydotool", "type", "UPLOAD"])
        wait_for(lambda: request().get("names") == ["Upload.txt"])
        run.check(args.browser + "-real-open-name-filter", request()["filterText"] == "UPLOAD")
        run.command(["ydotool", "key", "29:1", "42:1", "49:1", "49:0", "42:0", "29:0"])
        wait_for(lambda: request().get("creatingFolder") and request().get("focusedControl") == "Folder name")
        destination = run.fixtures / ("Chosen " + args.browser)
        run.command(["ydotool", "type", destination.name]); run.key(28)
        wait_for(lambda: destination.is_dir() and not request().get("creatingFolder") and request().get("name") == destination.name)
        run.check(args.browser + "-real-open-mkdir", destination.is_dir())
        protected = destination / "protected.txt"
        protected.write_text("ORIGINAL browser target\n")
        run.key(1); run.wait(lambda s: not s["requests"])

        seq = visit("open"); opened("open"); navigate(run.fixtures)
        run.key(33, 29); run.command(["ydotool", "type", "Upload"])
        wait_for(lambda: request().get("names") == ["Upload.txt"])
        run.key(28); run.key(102); run.key(28)
        run.wait(lambda s: not s["requests"])
        wait_for(lambda: any(e.get("kind") == "upload" and e.get("seq") == seq for e in events))
        received = next(e for e in events if e.get("kind") == "upload" and e.get("seq") == seq)
        run.check(args.browser + "-upload-consumer-bytes", received["name"] == "Upload.txt" and received["text"] == upload, received)

        seq = visit("open"); opened("open"); navigate(run.fixtures)
        focus("File name"); run.key(30, 29); run.command(["ydotool", "type", "Upl"])
        wait_for(lambda: request().get("pathEntry", {}).get("name", {}).get("completionOpen"))
        run.key(108); run.key(15); run.key(28)
        run.wait(lambda s: not s["requests"])
        wait_for(lambda: any(e.get("kind") == "upload" and e.get("seq") == seq for e in events))
        received = next(e for e in events if e.get("kind") == "upload" and e.get("seq") == seq)
        run.check(args.browser + "-typed-completed-name-consumer-bytes", received["name"] == "Upload.txt" and received["text"] == upload, received)

        visit("save"); opened("save"); edit_name(str(destination / "typed-path")); run.key(28)
        run.wait(lambda s: not s["requests"])
        typed = destination / "typed-path.txt"
        wait_for(lambda: typed.is_file() and typed.read_text() == payload, 35)
        run.check(args.browser + "-typed-save-path-consumer-bytes", typed.read_text() == payload)

        visit("save"); opened("save"); navigate(destination); edit_name("protected"); run.key(28)
        wait_for(lambda: request().get("replace") == str(protected) and request().get("focusedControl") == "Change name")
        run.check(args.browser + "-extension-final-name-visible", request()["saveName"] == "protected.txt" and request()["autoExtension"])
        run.check(args.browser + "-save-confirmation-before-write", protected.read_text() == "ORIGINAL browser target\n")
        run.command(["grim", run.output / "browser-overwrite-safe-default.png"])
        run.key(28)
        wait_for(lambda: not request().get("replace") and request().get("focus") == "name")
        run.key(28)
        wait_for(lambda: request().get("replace") == str(protected) and request().get("focusedControl") == "Change name")
        run.key(28)
        wait_for(lambda: not request().get("replace") and request().get("focus") == "name")
        run.check(args.browser + "-repeated-Enter-keeps-bytes", protected.read_text() == "ORIGINAL browser target\n" and len(run.state()["requests"]) == 1)
        edit_name("renamed"); run.key(28); run.wait(lambda s: not s["requests"])
        renamed = destination / "renamed.txt"
        wait_for(lambda: renamed.is_file() and renamed.read_text() == payload, 35)
        run.check(args.browser + "-save-into-created-folder-consumer", renamed.read_text() == payload and protected.read_text() == "ORIGINAL browser target\n")

        visit("save"); opened("save"); navigate(destination); edit_name("protected.txt"); run.key(28)
        wait_for(lambda: request().get("replace") == str(protected) and request().get("focusedControl") == "Change name")
        run.key(1)
        wait_for(lambda: not request().get("replace") and request().get("focus") == "name")
        run.check(args.browser + "-Escape-keeps-existing-bytes", protected.read_text() == "ORIGINAL browser target\n")
        run.key(28)
        wait_for(lambda: request().get("replace") == str(protected) and request().get("focusedControl") == "Change name")
        focus("Replace"); run.key(28); run.wait(lambda s: not s["requests"])
        wait_for(lambda: protected.read_text() == payload, 35)
        run.check(args.browser + "-explicit-Replace-consumer-write", protected.read_text() == payload)
        browser.terminate(); browser.wait(timeout=15)
        run.finish()
    except Exception as error:
        run.failure = repr(error)
        if isinstance(error, subprocess.CalledProcessError):
            (run.output / "failed-command.log").write_text(str(error.stdout) + str(error.stderr))
        raise
    finally:
        server.shutdown(); server.server_close(); thread.join(timeout=5)
        (run.output / "browser-events.json").write_text(json.dumps(events, indent=2))
        run.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
