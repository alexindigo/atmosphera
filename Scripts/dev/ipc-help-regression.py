#!/usr/bin/env python3
"""IPC help-text regression runner (plan: post-071, B+ row 4).

The custom-button IPC help must name the actual shell (`qs -c atmosphera`)
while retaining the real `cb` protocol and argument order.

--case source (per --source tree):
  For every Assets/Translations/*.json carrying the key:
  * file parses; the key exists under bar.custom-button.
  * the value contains exactly `qs -c atmosphera ipc call cb [action] [identifier]`
    (baseline FAILS: `qs -c atmosphera-shell ...`).
  * no `atmosphera-shell` token remains anywhere in the file.
  * `cb` precedes `[action]` precedes `[identifier]`; prose wraps the command.
  * the affected-file count is reported (24 at plan time).

--case vm (consumers):
  * I18n consumer: a disposable shell copy resolves the key through the real
    I18n.tr path for English and a supported non-English locale (de).
  * Documented IPC consumer: a harmless CustomButton is added to the
    production guest shell's bar (backup/restore of settings/bar.json via
    the shell's own external-edit reload), then the literal documented
    command `qs -c atmosphera ipc call cb left <id>` must trigger the
    button's command, which writes a unique marker file.
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROBE_SRC = SCRIPT_DIR / "fixtures" / "i18n-help-probe.qml"
PROBE_NAME = "i18n-help-probe.qml"

KEY_PATH = ("bar", "custom-button", "ipc-identifier-description")
CORRECT_CMD = "qs -c atmosphera ipc call cb [action] [identifier]"
GUEST_BAR_JSON = Path.home() / ".config" / "atmosphera" / "settings" / "bar.json"


class Blocked(Exception):
    pass


def _value(data):
    cur = data
    for k in KEY_PATH:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur if isinstance(cur, str) else None


def case_source(source, failures, notes):
    files = sorted((source / "Assets" / "Translations").glob("*.json"))
    affected = 0
    for f in files:
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            failures.append(f"{f.name}: does not parse: {e}")
            continue
        v = _value(data)
        if v is None:
            continue  # locale lacks the key — not an affected file
        affected += 1
        if "atmosphera-shell" in f.read_text(encoding="utf-8"):
            failures.append(f"{f.name}: 'atmosphera-shell' token still present")
        # The corrected shell token + cb protocol, in order. Placeholder
        # names are localized — assert the two-bracket structure, not the
        # English literals (en/en-GB get the exact check below).
        anchor = "qs -c atmosphera ipc call cb"
        if anchor not in v:
            failures.append(f"{f.name}: description lacks the corrected command {anchor!r} ...: {v[:90]!r}")
            continue
        m = re.search(re.escape(anchor) + r"\s+(\[[^\]]+\])\s+(\[[^\]]+\])", v)
        if not m:
            failures.append(f"{f.name}: cb no longer followed by action-before-identifier placeholders: {v[:90]!r}")
            continue
        if f.name in ("en.json", "en-GB.json") and CORRECT_CMD not in v:
            failures.append(f"{f.name}: English placeholders changed: {v[:90]!r}")
        if not (v[:m.start()].strip() and v[m.end():].strip()):
            failures.append(f"{f.name}: localized prose no longer wraps the command: {v[:90]!r}")
    notes.append(f"affected translation files: {affected}")
    if affected == 0:
        failures.append("no translation file carries the key — fixture drift?")


def _run_probe(source, output, language):
    case_dir = output / f"i18n-{language or 'en'}"
    if case_dir.exists():
        shutil.rmtree(case_dir)
    shell_dir = case_dir / "shell"
    shutil.copytree(source, shell_dir, ignore=shutil.ignore_patterns(".git"),
                    ignore_dangling_symlinks=True)
    shutil.copy(PROBE_SRC, shell_dir / PROBE_NAME)
    (case_dir / "config" / "settings").mkdir(parents=True)
    (case_dir / "cache").mkdir(parents=True)
    if language:
        (case_dir / "config" / "settings" / "general.json").write_text(
            json.dumps({"language": language}) + "\n")
    socks = sorted(glob.glob("/run/user/1000/niri.*.sock"))
    if len(socks) != 1:
        raise Blocked(f"expected exactly one niri socket, found {socks}")
    env = dict(os.environ)
    env.update({
        "XDG_RUNTIME_DIR": "/run/user/1000",
        "WAYLAND_DISPLAY": "wayland-1",
        "NIRI_SOCKET": socks[0],
        "ATMOSPHERA_CONFIG_DIR": str(case_dir / "config"),
        "ATMOSPHERA_CACHE_DIR": str(case_dir / "cache"),
        "ATMOSPHERA_SETTINGS_FILE": str(case_dir / "config" / "settings.json"),
        "ATMOSPHERA_DEBUG": "0",
        "PROBE_EXPECT_LANG": language or "",
    })
    proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(shell_dir / PROBE_NAME)],
                          env=env, capture_output=True, text=True, timeout=90)
    log = proc.stdout + proc.stderr
    (case_dir / "run.log").write_text(log)
    text = None
    lang_seen = None
    for line in log.splitlines():
        i = line.find("I18NHELP|TEXT|")
        if i >= 0:
            text = line[i + 14:].strip()
        j = line.find("I18NHELP|LANG|")
        if j >= 0:
            lang_seen = line[j + 14:].strip()
    return text, lang_seen


def case_vm_i18n(source, output, failures):
    for tool in ("qs", "dbus-run-session"):
        if shutil.which(tool) is None:
            raise Blocked(f"missing tool: {tool}")
    for lang, label in (("", "en"), ("de", "de")):
        text, lang_seen = _run_probe(source, output, lang)
        if text is None:
            failures.append(f"I18n consumer ({label}) never reported (see i18n-*/run.log)")
            continue
        if lang_seen != label:
            failures.append(f"I18n consumer ({label}) actually resolved lang={lang_seen!r} — "
                            "the non-English leg did not exercise the non-English locale")
        expected = CORRECT_CMD if label == "en" else "qs -c atmosphera ipc call cb"
        if expected not in text:
            failures.append(f"I18n consumer ({label}) resolved stale text (expected {expected!r}): {text[:100]!r}")
        if "atmosphera-shell" in text:
            failures.append(f"I18n consumer ({label}) still shows atmosphera-shell: {text[:100]!r}")


def case_vm_cb(output, failures, notes):
    """The literal documented command against the production atmosphera instance."""
    env = dict(os.environ)
    env.update({"XDG_RUNTIME_DIR": "/run/user/1000", "WAYLAND_DISPLAY": "wayland-1"})
    r = subprocess.run(["qs", "-c", "atmosphera", "ipc", "call", "cb"],
                       env=env, capture_output=True, text=True, timeout=15)
    if "Function required" not in (r.stdout + r.stderr):
        raise Blocked("production 'atmosphera' instance's cb handler not reachable — "
                      "ambiguous or missing IPC instance selection")
    if not GUEST_BAR_JSON.exists():
        raise Blocked(f"production bar.json not found at {GUEST_BAR_JSON}")

    marker = output / f"cb-marker-{int(time.time())}"
    identifier = "post071cbtest"
    backup = output / "bar.json.backup"
    shutil.copy(GUEST_BAR_JSON, backup)

    def restore():
        shutil.copy(backup, GUEST_BAR_JSON)
    # restore happens in finally below AND must be durable across failures

    try:
        data = json.loads(GUEST_BAR_JSON.read_text())
        data.setdefault("widgets", {}).setdefault("right", []).append({
            "id": "CustomButton",
            "ipcIdentifier": identifier,
            "leftClickExec": f"sh -c 'echo triggered > {marker}'",
            "icon": "heart",
        })
        tmp = GUEST_BAR_JSON.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(data, indent=2) + "\n")
        os.replace(tmp, GUEST_BAR_JSON)
        notes.append("transient CustomButton added to the production bar (backup taken)")
        # Let the shell's external-edit reload apply it
        time.sleep(4)
        r = subprocess.run(["qs", "-c", "atmosphera", "ipc", "call", "cb", "left", identifier],
                           env=env, capture_output=True, text=True, timeout=15)
        deadline = time.time() + 8
        while time.time() < deadline and not marker.exists():
            time.sleep(0.5)
        if not marker.exists():
            failures.append("documented command `qs -c atmosphera ipc call cb left <id>` did not "
                            f"trigger the button (stdout={r.stdout.strip()!r} stderr={r.stderr.strip()!r})")
        elif marker.read_text().strip() != "triggered":
            failures.append(f"cb marker content wrong: {marker.read_text()!r}")
        else:
            notes.append("documented command reached the test custom button; marker written")
    finally:
        restore()
        time.sleep(3)  # let the reload remove the button again


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--case", required=True, choices=["source", "vm", "all"])
    args = ap.parse_args()

    source = Path(args.source)
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    failures, notes = [], []
    blocked = None
    try:
        if args.case in ("source", "all"):
            case_source(source, failures, notes)
        if args.case in ("vm", "all"):
            case_vm_i18n(source, output, failures)
            case_vm_cb(output, failures, notes)
    except Blocked as b:
        blocked = str(b)

    for n in notes:
        print(f"note: {n}")
    for f in failures:
        print(f"FAIL: {f}")
    if blocked:
        print(f"BLOCKED: {blocked}")
    (output / "ipc-help-result.json").write_text(json.dumps(
        {"case": args.case, "failures": failures, "blocked": blocked, "notes": notes}, indent=2) + "\n")
    if failures or blocked:
        print("IPC_HELP_REGRESSION: " + ("FAIL" if failures else "BLOCKED"))
        sys.exit(1)
    print("IPC_HELP_REGRESSION: PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
