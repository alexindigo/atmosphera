#!/usr/bin/env python3
"""Guest-only unit check: portal byte path and file URI helper (M17).

Run with --source TREE in the Qt612 niri VM. Helpers/PortalPaths.js and
Scripts/dev/fixtures/portal-paths.qml are copied into a private runtime tree
under ROOT/runtime/<unique name>, the fixture runs there with `qs -p`, and every
printed case is compared with the expectations written below. A case passes
when each expected field equals the observed field (extra observed fields are
ignored). Exit 0 only if every expected case is present exactly once, matches,
the fixture exits 0 and prints its DONE marker, and no error line appears.
Nothing is written into --source. --output is optional: when given it must not
exist and receives a copy of result.json.
"""
import argparse
import glob
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path("/home/tester/Projects/qt612-atmocolor/081-integrity")
FILES = [
    "Helpers/PortalPaths.js",
    "Scripts/dev/fixtures/portal-paths.qml",
]
FIXTURE = "Scripts/dev/fixtures/portal-paths.qml"
PREFIX = "PORTAL_PATHS|"
DONE = "PORTAL_PATHS_DONE"
ERRORS = re.compile(r"ReferenceError|TypeError|SyntaxError|Component is not ready|is not a function|Failed to load|PORTAL_PATHS_ERROR|\"threw\"")

NUL = "\x00"
R = str(ROOT)
JP = "\u65e5\u672c\u8a9e"
EMOJI = "\U0001F600"


def ok_path(path):
    return {"ok": True, "path": path}


def ok_bytes(values):
    return {"ok": True, "bytes": values}


def ok_uri(uri):
    return {"ok": True, "uri": uri}


def err(error):
    return {"ok": False, "error": error}


BYTES_TMP_JP = [0x2F, 0x74, 0x6D, 0x70, 0x2F, 0xE6, 0x97, 0xA5, 0xE6, 0x9C, 0xAC, 0xE8, 0xAA, 0x9E]
BYTES_TMP_EMOJI = [0x2F, 0x74, 0x6D, 0x70, 0x2F, 0xF0, 0x9F, 0x98, 0x80]
ROUND_TRIP = ["/tmp/a", "/tmp/" + JP, "/tmp/a#b?c%20d e", "/tmp/A-z_0.9~", "/tmp/" + EMOJI]


def expectations():
    tmp_a = "/tmp/a"
    cases = {
        # Byte input forms, /tmp/a with and without the terminator.
        "ab-ascii-nul": ok_path(tmp_a),
        "ab-ascii": ok_path(tmp_a),
        "u8-ascii-nul": ok_path(tmp_a),
        "u8-ascii": ok_path(tmp_a),
        "arr-ascii-nul": ok_path(tmp_a),
        "arr-ascii": ok_path(tmp_a),
        "ab-embedded-nul": err("embedded NUL"),
        "ab-two-trailing-nul": err("embedded NUL"),
        "ab-empty": ok_path(""),
        "arr-lone-nul": ok_path(""),
        # Multibyte folder and a 4-byte character.
        "ab-jp-nul": ok_path("/tmp/" + JP),
        "ab-jp": ok_path("/tmp/" + JP),
        "arr-emoji-nul": ok_path("/tmp/" + EMOJI),
        # Strict UTF-8.
        "ab-invalid-ff": err("invalid UTF-8"),
        "ab-truncated": err("invalid UTF-8"),
        "ab-overlong": err("invalid UTF-8"),
        "ab-surrogate": err("invalid UTF-8"),
        # Non-byte input types never become a path.
        "type-number": err("unsupported input type"),
        "type-object": err("unsupported input type"),
        "type-null": err("unsupported input type"),
        "arr-bad-value": err("invalid byte value"),
        # String inputs, including the M16 table as strings.
        "str-nul-trailing": ok_path(R + "/fc/downloads"),
        "str-plain": ok_path(R + "/fc/downloads"),
        "str-embedded-nul": err("embedded NUL"),
        "str-lone-nul": ok_path(""),
        "str-leading-nul": err("embedded NUL"),
        "str-file-nul": ok_path(R + "/fc/downloads/existing.html"),
        "str-two-nul": err("embedded NUL"),
        "str-jp-nul": ok_path("/tmp/" + JP),
        "str-hash-plain": ok_path("/tmp/a#b?c%20d e"),
        # encodeBytePath: exact bytes, terminator included.
        "enc-ascii": ok_bytes([0x2F, 0x74, 0x6D, 0x70, 0x2F, 0x61, 0x00]),
        "enc-jp": ok_bytes(BYTES_TMP_JP + [0x00]),
        "enc-emoji": ok_bytes(BYTES_TMP_EMOJI + [0x00]),
        "enc-embedded-nul": err("embedded NUL"),
        "enc-lone-surrogate": err("invalid UTF-16"),
        # pathToUri: exact outputs.
        "uri-hash-space-percent": ok_uri("file:///tmp/a%23b%3Fc%2520d%20e"),
        "uri-jp": ok_uri("file:///tmp/%E6%97%A5%E6%9C%AC%E8%AA%9E"),
        "uri-unreserved": ok_uri("file:///tmp/A-z_0.9~"),
        "uri-emoji": ok_uri("file:///tmp/%F0%9F%98%80"),
        "uri-relative": err("not an absolute path"),
        "uri-empty": err("not an absolute path"),
        "uri-embedded-nul": err("embedded NUL"),
        "uri-type-number": err("unsupported input type"),
        # uriToPath: accepted forms.
        "path-plain": ok_path("/tmp/x"),
        "path-localhost": ok_path("/tmp/x"),
        "path-jp": ok_path("/tmp/" + JP),
        "path-lowercase": ok_path("/tmp/\u65e5"),
        "path-escapes": ok_path("/tmp/a#b?c%20d e"),
        "path-raw-utf8": ok_path("/tmp/" + JP),
        # uriToPath: rejected forms.
        "path-bad-hex": err("invalid escape"),
        "path-lone-percent": err("invalid escape"),
        "path-truncated-utf8": err("invalid UTF-8"),
        "path-overlong": err("invalid UTF-8"),
        "path-escaped-nul": err("embedded NUL"),
        "path-other-host": err("unsupported host"),
        "path-localhost-lookalike": err("unsupported host"),
        "path-http": err("not a file URI"),
        "path-relative": err("not a file URI"),
        "path-raw-hash": err("query or fragment not allowed"),
        "path-raw-query": err("query or fragment not allowed"),
        "path-raw-space": err("forbidden character"),
        "path-type-number": err("unsupported input type"),
    }
    # Round trips: decode(encode(p)) and uriToPath(pathToUri(p)) give p back.
    for k, path in enumerate(ROUND_TRIP):
        cases[f"rt-bytes-{k}"] = ok_path(path)
        cases[f"rt-uri-{k}"] = ok_path(path)
    return cases


def command(argv, env=None, seconds=40):
    return subprocess.run(["timeout", "--kill-after=5s", str(seconds), *map(str, argv)],
                          env=env, capture_output=True, text=True, encoding="utf-8", errors="replace",
                          timeout=seconds + 10)


def guest_env(config):
    assert os.getuid() == 1000 and Path.home() == Path("/home/tester")
    macs = [p.read_text().strip().lower() for p in Path("/sys/class/net").glob("*/address")]
    assert "52:54:00:4c:05:2c" in macs, macs
    socks = glob.glob("/run/user/1000/niri.*.sock")
    assert len(socks) == 1 and Path("/run/user/1000/wayland-1").exists()
    return dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1", NIRI_SOCKET=socks[0],
                ATMOSPHERA_CONFIG_DIR=str(config / "config") + "/", ATMOSPHERA_CACHE_DIR=str(config / "cache") + "/",
                ATMOSPHERA_SETTINGS_FILE=str(config / "config/settings.json"), ATMOSPHERA_DEBUG="0",
                TMPDIR="/home/tester/Projects/qt612-atmocolor/tmp", QT_FORCE_STDERR_LOGGING="1",
                ATMOSPHERA_UPGRADELOG_URL="http://127.0.0.1:9")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse(log):
    cases = []
    for line in log.splitlines():
        if PREFIX in line:
            cases.append(json.loads(line.split(PREFIX, 1)[1]))
    return cases


def matches(actual, want):
    """Every expected field equals the observed field; extras are ignored."""
    if not isinstance(actual, dict):
        return False, {"observed": actual}
    fields = {k: actual.get(k, "<missing>") == v and type(actual.get(k)) is type(v) for k, v in want.items()}
    return all(fields.values()), fields


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    source = Path(args.source).resolve()
    assert source.is_relative_to(ROOT), "--source must be under the guest root"
    output = Path(args.output).resolve() if args.output else None
    if output is not None:
        assert not output.exists(), "Preserve earlier evidence; use a fresh output path"

    stamp = time.strftime("%Y%m%dT%H%M%S")
    run = ROOT / "runtime" / f"portal-paths-unit-{stamp}-{os.getpid()}"
    assert not run.exists(), run
    tree = run / "tree"
    config = run / "profile"
    for part in ("config", "cache"):
        (config / part).mkdir(parents=True)

    hashes_src = {}
    for rel in FILES:
        target = tree / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / rel, target)
        hashes_src[rel] = sha256(target)
    # Quickshell confines relative imports to its config root, so the fixture
    # keeps its repository path and is loaded through a root entry.
    (tree / "shell.qml").write_text('import QtQuick\nItem { Loader { source: "%s" } }\n' % FIXTURE)

    env = guest_env(config)
    result = command(["dbus-run-session", "--", "qs", "-p", tree / "shell.qml"], env, 40)
    log = result.stdout + result.stderr
    (run / "probe.log").write_text(log)

    cases = parse(log)
    expected = expectations()
    seen = {}
    for case in cases:
        seen[case["case"]] = seen.get(case["case"], 0) + 1
    failures = []
    rows = []
    for name, want in expected.items():
        got = [c["output"] for c in cases if c["case"] == name]
        if len(got) != 1:
            ok = False
            observed = f"{len(got)} output lines"
            fields = {}
        else:
            ok, fields = matches(got[0], want)
            observed = got[0]
        rows.append({"case": name, "ok": ok, "expected": want, "actual": observed, "fields": fields})
        if not ok:
            failures.append(name)
        print(f"[{'PASS' if ok else 'FAIL'}] {name} expected={json.dumps(want, ensure_ascii=True)} "
              f"actual={json.dumps(observed, ensure_ascii=True)}", flush=True)
    unexpected = sorted(set(seen) - set(expected))
    if unexpected:
        failures.append(f"unexpected cases: {unexpected}")
    if result.returncode != 0 or DONE not in log:
        failures.append(f"fixture exit {result.returncode}, done marker {DONE in log}")
    if ERRORS.search(log):
        failures.append("error line in fixture log")

    summary = {"source": str(source), "run": str(run), "source_sha256": hashes_src,
               "fixture_exit": result.returncode, "cases": rows, "unexpected": unexpected,
               "failures": failures, "at": time.time()}
    text = json.dumps(summary, indent=2, ensure_ascii=True) + "\n"
    (run / "result.json").write_text(text)
    if output is not None:
        output.mkdir(parents=True)
        (output / "result.json").write_text(text)
    print("PORTAL_PATHS_UNIT: " + ("FAIL" if failures else "PASS") + f" ({len(rows)} cases)", flush=True)
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
