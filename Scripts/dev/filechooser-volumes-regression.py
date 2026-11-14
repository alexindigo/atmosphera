#!/usr/bin/env python3
"""Real guest UDisks proof with a private, resource-capped compositor.

Unlike the UI/portal runners, this dedicated runner needs the guest's system bus
AND mount namespace: UDisks mounts in its own namespace, invisible in a private
mount namespace. All children remain in a dedicated capped guest user service,
with a fresh bus/compositor/profile. Existing suite isolation is unchanged.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import re
import time

from filechooser_profile import current_profile, exact_source, profile_argument
from filechooser_isolation import MIB, reservation, service_guard


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--private", action="store_true", help=argparse.SUPPRESS)
    profile_argument(parser)
    args = parser.parse_args()
    current_profile().verify()
    source = args.source.resolve()
    assert exact_source(source)
    assert re.fullmatch(r"[a-z0-9][a-z0-9-]+", args.label)
    if not args.private:
        env = dict(os.environ, XDG_RUNTIME_DIR=f"/run/user/{os.getuid()}", DBUS_SESSION_BUS_ADDRESS=f"unix:path=/run/user/{os.getuid()}/bus")
        unit = "filechooser-" + args.label
        with reservation(768 * MIB) as admission:
            (current_profile().evidence / (args.label + "-admission.json")).write_text(json.dumps(admission, indent=2))
            try:
                return subprocess.run(["timeout", "100", "systemd-run", "--user", "--pipe", "--wait", "--collect", "--unit=" + unit,
                                       "--setenv=TMPDIR=" + os.environ["TMPDIR"],
                                       "-p", "MemoryMax=768M", "-p", "MemorySwapMax=0", "-p", "TasksMax=128", "-p", "CPUQuota=100%",
                                       "-p", "RuntimeMaxSec=90", "-p", "TimeoutStopSec=10",
                                       "dbus-run-session", "--", sys.executable, "-B", str(Path(__file__).resolve()), *sys.argv[1:], "--private", "--guest-profile", str(current_profile().path)],
                                      env=env, timeout=110).returncode
            finally:
                # Keep admission until the whole owned unit has stopped, also
                # after an interrupted/timed-out systemd-run control connection.
                subprocess.run(["timeout", "15", "systemctl", "--user", "stop", unit], env=env,
                               capture_output=True, timeout=20)
                state = subprocess.run(["timeout", "10", "systemctl", "--user", "show", unit, "-p", "ActiveState"],
                                       env=env, capture_output=True, text=True, check=True, timeout=15)
                assert state.stdout.strip() in ("ActiveState=inactive", "ActiveState=failed"), state.stdout
    with service_guard():
        return run(args, source)


def run(args, source):
    runtime, output = current_profile().runtime / args.label, current_profile().evidence / args.label
    assert not runtime.exists() and not output.exists()
    runtime.mkdir(); output.mkdir()
    shell = runtime / "shell"
    shutil.copytree(source, shell, symlinks=True)
    probe = shell / "volume-probe.qml"
    probe.write_text((source / "Scripts/dev/fixtures/filechooser-volumes.qml").read_text().replace('"../../../Helpers/', '"Helpers/'))
    profile = runtime / "profile"
    for name in ("config", "cache", "data", "state", "tmp", "run"): (profile / name).mkdir(parents=True, mode=0o700)
    run_dir = runtime / "r"
    run_dir.mkdir(mode=0o700)
    env = {k: os.environ[k] for k in ("PATH", "HOME", "USER", "LANG", "DBUS_SESSION_BUS_ADDRESS", "QT_PLUGIN_PATH", "QML_IMPORT_PATH") if k in os.environ}
    env.update(XDG_CONFIG_HOME=str(profile / "config"), XDG_DATA_HOME=str(profile / "data"), XDG_CACHE_HOME=str(profile / "cache"),
               XDG_STATE_HOME=str(profile / "state"), XDG_RUNTIME_DIR=str(run_dir), TMPDIR=str(profile / "tmp"),
               WLR_BACKENDS="headless", WLR_RENDERER="pixman", WLR_LIBINPUT_NO_DEVICES="1", LIBGL_ALWAYS_SOFTWARE="1", QSG_RHI_BACKEND="opengl", QT_QPA_PLATFORM="wayland",
               DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket",
               FILECHOOSER_VOLUME_FOLDER=str(current_profile().workspace / "fixtures"), FILECHOOSER_VOLUME_CAPTURE=str(output / "volumes-mounted.png"),
               FILECHOOSER_VOLUME_ID="/org/freedesktop/UDisks2/block_devices/loop0")
    def prop(name):
        value = subprocess.run(["timeout", "5", "busctl", "--system", "--json=short", "get-property", "org.freedesktop.UDisks2",
                                env["FILECHOOSER_VOLUME_ID"], "org.freedesktop.UDisks2.Loop", name], env=env, capture_output=True, text=True, check=True, timeout=10)
        return json.loads(value.stdout)["data"]
    backing, owner = prop("BackingFile"), prop("SetupByUID")
    assert bytes(backing).rstrip(b"\0").decode() == str(current_profile().workspace / "fixtures/p7-volume.img") and owner == 1000, (backing, owner)
    (output / "loop-ownership.json").write_text(json.dumps({"backing": backing, "uid": owner}))
    config = runtime / "sway.conf"
    config.write_text("output HEADLESS-1 resolution 1280x800\nseat seat0 fallback true\n")
    with (output / "compositor.log").open("w") as log:
        compositor = subprocess.Popen(["timeout", "60", "sway", "-c", str(config)], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while not list(run_dir.glob("wayland-*")):
                assert compositor.poll() is None and time.monotonic() < deadline, "private compositor unavailable"
                time.sleep(.1)
            sockets = [p for p in run_dir.glob("wayland-*") if p.is_socket()]
            assert len(sockets) == 1
            env["WAYLAND_DISPLAY"] = sockets[0].name
            with (output / "probe.log").open("w") as probe_log:
                process = subprocess.run(["timeout", "--kill-after=5", "30", "qs", "-p", str(probe)], env=env, cwd=shell, stdout=probe_log, stderr=subprocess.STDOUT, timeout=40)
        finally:
            compositor.terminate(); compositor.wait(timeout=10)
    log = (output / "probe.log").read_text()
    rows = [json.loads(line.split("FILECHOOSER_VOLUMES|", 1)[1]) for line in log.splitlines() if "FILECHOOSER_VOLUMES|" in line]
    errors = [line for line in log.splitlines() if re.search(r"TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration|Unable to assign", line)]
    result = {"exit": process.returncode, "cases": rows, "errors": errors,
              "pass": process.returncode == 0 and len(rows) == 7 and all(r["pass"] for r in rows) and not errors}
    (output / "result.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 0 if result["pass"] else 1


if __name__ == "__main__": sys.exit(main())
