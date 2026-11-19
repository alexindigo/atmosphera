"""Guest-only ydotool/uinput proof of the actual per-monitor menu and drag UI."""
import json
import subprocess
import time


def exercise(R, W, source, installed, out, label, env, client, run):
    probe = installed / "monitor-pointer.qml"
    assert not probe.exists()
    probe.write_bytes((source / "Scripts/dev/fixtures/monitor-pointer.qml").read_bytes())
    # One fixture-owned namespace avoids the retained catalog's short runtime
    # prefixes while keeping Quickshell's UNIX socket paths within their limit.
    work = W / "ptr"
    work.mkdir()
    runtime = work / "r"
    runtime.mkdir(mode=0o700)
    config = work / "c"
    socket = work / "u.sock"
    unit = "atcq-monitor-pointer-" + label
    setting = {**env, **client, "QT_QPA_PLATFORM": "wayland", "XDG_RUNTIME_DIR": str(runtime),
               "ATMOSPHERA_CONFIG_DIR": str(config), "ATMOSPHERA_SETTINGS_FILE": str(config / "settings.json"),
               "ATMOSPHERA_CACHE_DIR": str(W / ("mk" + label)), "ATMOSPHERA_STATE_DIR": str(W / ("mv" + label)),
               "YDOTOOL_SOCKET": str(socket), "I4_VERIFY": "0"}
    commands = []
    observations = {}
    process = None
    daemon = False

    def call(argv, check=True):
        result = subprocess.run(["timeout", "10", *map(str, argv)], env=setting, capture_output=True, text=True, timeout=15)
        commands.append(dict(argv=list(map(str, argv)), exit=result.returncode))
        if check:
            assert result.returncode == 0, (argv, result.stdout, result.stderr)
        return result

    def ipc(method):
        return call(["qs", "-p", probe, "ipc", "call", "monitorPointer", method]).stdout

    def snapshot():
        return json.loads(ipc("snapshot"))

    def wait(predicate):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            assert process is None or process.poll() is None, "pointer fixture exited early"
            time.sleep(0.05)
        raise AssertionError("native monitor pointer deadline")

    def position(point):
        # Relative device only; the provisioned guest uses flat pointer input.
        # First clamp at the output origin, then move to observed global geometry.
        call(["ydotool", "mousemove", "--", "-10000", "-10000"])
        time.sleep(0.05)
        call(["ydotool", "mousemove", "--", str(round(point["x"])), str(round(point["y"]))])
        time.sleep(0.1)

    try:
        call(["sudo", "-n", "systemd-run", "--unit=" + unit, "--property=RuntimeMaxSec=180", "--property=TimeoutStopSec=5",
              "--setenv=TMPDIR=" + str(R / "tmp"), "/usr/bin/ydotoold", "--socket-path=" + str(socket), "--socket-own=1000:1000"])
        daemon = True
        wait(socket.exists)
        with (out / "monitor-pointer-save.log").open("x") as log:
            process = subprocess.Popen(["timeout", "100", "dbus-run-session", "--", "qs", "-p", str(probe), "--no-color"], env=setting, stdout=log, stderr=subprocess.STDOUT)
            wait(lambda: call(["qs", "-p", probe, "ipc", "show"], False).returncode == 0)
            wait(lambda: snapshot()["ready"] and snapshot()["leftRow"] is not None)
            observations["initial"] = snapshot()
            position(snapshot()["leftRow"])
            call(["ydotool", "click", "0xC1"])
            observations["afterRightClick"] = snapshot()
            wait(lambda: snapshot()["menu"] and snapshot()["menuCenter"] is not None)
            observations["nativeMenu"] = snapshot()
            position(snapshot()["menuCenter"])
            call(["ydotool", "click", "0xC0"])
            wait(lambda: len(snapshot()["completions"]) == 1)
            observations["menuMove"] = snapshot()
            assert observations["menuMove"]["values"]["center"][1]["tag"] == "first"
            assert observations["menuMove"]["completions"][0]["status"] == "admitted"
            start = snapshot()["leftRow"]
            target = snapshot()["rightDrop"]
            position(start)
            call(["ydotool", "click", "0x40"])
            time.sleep(0.1)
            previous = {key: round(value) for key, value in start.items()}
            for step in range(1, 17):
                next_point = {key: round(start[key] + (target[key] - start[key]) * step / 16) for key in ("x", "y")}
                call(["ydotool", "mousemove", "--", str(next_point["x"] - previous["x"]), str(next_point["y"] - previous["y"])])
                previous = next_point
                time.sleep(0.03)
            call(["ydotool", "click", "0x80"])
            wait(lambda: len(snapshot()["completions"]) == 2)
            observations["dragMove"] = snapshot()
            assert observations["dragMove"]["values"]["right"][0]["tag"] == "second"
            assert observations["dragMove"]["completions"][1]["status"] == "admitted"
            ipc("save")
            wait(lambda: snapshot()["saved"] in ("saved", "nothing_to_save"))
            observations["saved"] = snapshot()
            ipc("quit")
            assert process.wait(timeout=15) == 0
        text = (out / "monitor-pointer-save.log").read_text()
        assert "I4_MONITOR_POINTER: SAVED_PASS" in text and not any(token in text for token in ("TypeError", "ReferenceError", "I4_MONITOR_POINTER_ASSERT", "Failed to load configuration")), text
        run("monitor-pointer-restart", ["dbus-run-session", "--", "qs", "-p", probe, "--no-color"], 30, True, dict(setting, I4_VERIFY="1"))
        assert "I4_MONITOR_POINTER: RESTART_PASS" in (out / "monitor-pointer-restart.log").read_text()
        records = json.loads((config / "settings/bar.json").read_text())
        assert records["screenOverrides"][0]["widgets"]["right"][0]["tag"] == "second"
        assert len(records["widgets"]["left"]) == 2
        return dict(status="PASS", input="guest ydotool/uinput relative pointer", menu=1, crossSectionDrag=1, restart=True)
    finally:
        if process is not None and process.poll() is None:
            observations["last"] = snapshot()
        (out / "monitor-pointer-result.log").write_text(json.dumps(dict(observations=observations, commands=commands), indent=2))
        if process is not None and process.poll() is None:
            call(["ydotool", "click", "0x80"], False)
            ipc("quit")
            process.wait(timeout=15)
        if daemon:
            call(["sudo", "-n", "systemctl", "stop", unit])
        probe.unlink()
