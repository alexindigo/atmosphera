#!/usr/bin/env python3
"""Built-in catalog regression runner (plan: post-071, B+ row 3).

The Built-in catalog must not advertise the already-retired, payload-less
`noctalia-icons-legacy` icon set.

--case source (per --source tree):
  * builtin/plugins/registry.json parses; format/version preserved.
  * Every advertised built-in id has a payload directory AND manifest.
  * Exactly the three shipped plugins remain: atmosphera-icons,
    atmosphera-wallpapers, demo-custom-lockscreen (baseline FAILS: it
    advertises the retired set with no payload).

--case vm (actual consumer, fresh fixture profile):
  A disposable copy of --source boots with a clean profile; the plugin
  system seeds the Built-in source, fetches the shipped registry, and
  builds the Available model (the model AvailableSubTab renders). The probe
  reports the model ids: fixed = the three shipped plugins; baseline
  includes the retired entry.
"""

import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROBE_SRC = SCRIPT_DIR / "fixtures" / "catalog-regression.qml"
PROBE_NAME = "catalog-regression-probe.qml"

EXPECTED_IDS = ["atmosphera-icons", "atmosphera-wallpapers", "demo-custom-lockscreen"]
RETIRED_ID = "noctalia-icons-legacy"


class Blocked(Exception):
    pass


def case_source(source, failures):
    reg_path = source / "builtin" / "plugins" / "registry.json"
    try:
        reg = json.loads(reg_path.read_text())
    except (OSError, json.JSONDecodeError) as e:
        failures.append(f"registry.json does not parse: {e}")
        return
    if reg.get("version") != 1:
        failures.append(f"registry format version changed: {reg.get('version')}")
    plugins = reg.get("plugins", [])
    ids = [p.get("id") for p in plugins]
    for pid in ids:
        payload = source / "builtin" / "plugins" / pid
        if not payload.is_dir():
            failures.append(f"advertised built-in {pid!r} has no payload directory")
        elif not (payload / "manifest.json").exists():
            failures.append(f"advertised built-in {pid!r} payload lacks manifest.json")
    if RETIRED_ID in ids:
        failures.append(f"retired {RETIRED_ID!r} still advertised in the Built-in catalog")
    extra = [i for i in ids if i not in EXPECTED_IDS]
    missing = [i for i in EXPECTED_IDS if i not in ids]
    if extra:
        failures.append(f"unexpected built-in ids: {extra}")
    if missing:
        failures.append(f"missing shipped built-in ids: {missing}")


def case_vm(source, output, failures):
    for tool in ("qs", "dbus-run-session"):
        if shutil.which(tool) is None:
            raise Blocked(f"missing tool: {tool}")
    socks = sorted(glob.glob("/run/user/1000/niri.*.sock"))
    if len(socks) != 1:
        raise Blocked(f"expected exactly one niri socket, found {socks}")

    case_dir = output / "vm"
    if case_dir.exists():
        shutil.rmtree(case_dir)
    shell_dir = case_dir / "shell"
    shutil.copytree(source, shell_dir, ignore=shutil.ignore_patterns(".git"),
                    ignore_dangling_symlinks=True)
    shutil.copy(PROBE_SRC, shell_dir / PROBE_NAME)
    (case_dir / "config").mkdir(parents=True)
    (case_dir / "cache").mkdir(parents=True)

    env = dict(os.environ)
    env.update({
        "XDG_RUNTIME_DIR": "/run/user/1000",
        "WAYLAND_DISPLAY": "wayland-1",
        "NIRI_SOCKET": socks[0],
        "ATMOSPHERA_CONFIG_DIR": str(case_dir / "config"),
        "ATMOSPHERA_CACHE_DIR": str(case_dir / "cache"),
        "ATMOSPHERA_SETTINGS_FILE": str(case_dir / "config" / "settings.json"),
        "ATMOSPHERA_DEBUG": "0",
    })
    proc = subprocess.run(
        ["dbus-run-session", "--", "qs", "-p", str(shell_dir / PROBE_NAME)],
        env=env, capture_output=True, text=True, timeout=90)
    log = proc.stdout + proc.stderr
    (case_dir / "run.log").write_text(log)

    builtin_ids = None
    all_ids = None
    for line in log.splitlines():
        i = line.find("CATALOG|BUILTIN|")
        if i >= 0:
            try:
                builtin_ids = json.loads(line[i + 16:].strip())
            except json.JSONDecodeError:
                pass
        j = line.find("CATALOG|AVAILABLE|")
        if j >= 0:
            try:
                all_ids = json.loads(line[j + 18:].strip())
            except json.JSONDecodeError:
                pass
    if builtin_ids is None:
        failures.append("Built-in source entries never reported (see vm/run.log)")
        return
    if RETIRED_ID in builtin_ids:
        failures.append(f"Built-in Available entries still list the retired {RETIRED_ID!r}: {builtin_ids}")
    if sorted(builtin_ids) != sorted(EXPECTED_IDS):
        failures.append(f"Built-in Available entries != the three shipped plugins: {builtin_ids}")
    if all_ids is not None and RETIRED_ID in all_ids:
        failures.append(f"retired {RETIRED_ID!r} present in the full Available model: {all_ids}")
    (case_dir / "available.json").write_text(json.dumps(
        {"builtin": builtin_ids, "all": all_ids}, indent=1) + "\n")


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
    failures = []
    blocked = None
    try:
        if args.case in ("source", "all"):
            case_source(source, failures)
        if args.case in ("vm", "all"):
            case_vm(source, output, failures)
    except Blocked as b:
        blocked = str(b)

    for f in failures:
        print(f"FAIL: {f}")
    if blocked:
        print(f"BLOCKED: {blocked}")
    (output / "catalog-result.json").write_text(json.dumps(
        {"case": args.case, "failures": failures, "blocked": blocked}, indent=2) + "\n")
    if failures or blocked:
        print("BUILTIN_CATALOG_REGRESSION: " + ("FAIL" if failures else "BLOCKED"))
        sys.exit(1)
    print("BUILTIN_CATALOG_REGRESSION: PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
