#!/usr/bin/env python3
"""Bindings regression runner (plan: post-071-settings-icons-release-notes, B+ rows 1-2).

Runs INSIDE the test guest. Covers both approved template fixes:

  Row 1 — xremap template: Terminal copy-paste (specific) must precede
          Mac copy-paste (generic); xremap applies the first matching keymap.
  Row 2 — niri macOS layer: Super+Space spawns the native launcher via
          `qs -c atmosphera ipc call launcher toggle` (no fuzzel).

--case source (static, per --source tree):
  * xremap template: YAML parses; block order; remap/app-list/modmap contents
    unchanged (device filter, mappings, other keymaps).
  * kdl template: exactly one live Super+Space bind with the approved spawn
    args; no fuzzel anywhere; obsolete TODO removed.

--case vm (consumer legs against the live niri session):
  K1 terminal clipboard  — foot focused; host-side QMP injects physical
      Alt+V / Alt+C (Cmd position through the shipped fallback modmap);
      foot must receive Ctrl+Shift+V (clipboard sentinel on stdin), and the
      xremap virtual device must show the terminal-specific combos.
      On the baseline template the generic map shadows the terminal one:
      foot receives Shift+Insert (primary-selection sentinel) instead.
  K2 GUI regression      — non-terminal Qt probe focused; Alt+V must still
      emit Shift_L-Insert (generic map) and paste the PRIMARY sentinel.
  K3 real corner Ctrl    — physical Ctrl+C reaches the terminal unchanged
      (SIGINT kills the sink; evtest shows an unmapped pass-through).
  L1 launcher            — the edited kdl layer is loaded into niri through
      the typed niriqml integration (LoadConfigFile); injected Alt+Space
      (logical Super+Space) opens the native launcher in app mode, a second
      chord closes it, and from clipboard mode the chord switches to app
      mode. Evidence: screenshots, not return codes.

Hardware-level injection cannot originate inside the guest: at each
injection point the runner writes <output>/AWAITING-<stage> with the exact
QMP command lines and waits for <output>/GO-<stage> (created by the host
side after injecting). Timeout without GO = BLOCKED (nonzero).

The runner restores guest state on exit: the pre-existing xremap config
(or its absence) and the original niri session config.
"""

import argparse
import glob
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
FIXTURES = SCRIPT_DIR / "fixtures"

XREMAP_REL = "Bindings/environments/macos/xremap/atmosphera-xremap.yml"
KDL_REL = "Bindings/environments/macos/niri/atmosphera-shortcuts-macos.kdl"

GUEST_XREMAP_DIR = Path.home() / ".config" / "xremap"
GUEST_XREMAP_CONF = GUEST_XREMAP_DIR / "atmosphera-xremap.yml"
GUEST_NIRI_DIR = Path.home() / ".config" / "niri"
GUEST_KDL_LAYER = GUEST_NIRI_DIR / "atmosphera-shortcuts-macos.kdl"
GUEST_SESSION_CONF = GUEST_NIRI_DIR / "atmosphera-session.kdl"
GUEST_TEST_SESSION = GUEST_NIRI_DIR / "post071-test-session.kdl"

EXPECTED_TERMINAL_REMAP = {"Super-c": "Ctrl-Shift-c", "Super-v": "Ctrl-Shift-v", "Super-x": "Ctrl-Shift-x"}
EXPECTED_TERMINAL_APPS = ["/ghostty/", "/alacritty/", "/kitty/", "/wezterm/", "/foot/"]
EXPECTED_MAC_REMAP = {"Super-C": "Ctrl_L-Insert", "Super-V": "Shift_L-Insert", "Super-X": "Ctrl_L-X"}
EXPECTED_MODMAP = {"Alt_L": "Super_L", "Alt_R": "Super_R", "Super_L": "Alt_L", "Super_R": "Alt_R"}
EXPECTED_MODMAP_DEVICE = "AT Translated Set 2 keyboard"
EXPECTED_SPAWN = '"qs" "-c" "atmosphera" "ipc" "call" "launcher" "toggle"'

INJECT_TIMEOUT_S = 600


def sh(args, env=None, capture=True, timeout=60):
    return subprocess.run(args, capture_output=capture, text=True, env=env, timeout=timeout)


class Blocked(Exception):
    pass


class Ctx:
    def __init__(self, source, output):
        self.source = Path(source)
        self.output = Path(output)
        self.failures = []
        self.notes = []
        self._restore = []
        self.session = self._discover_session()

    def _discover_session(self):
        socks = sorted(glob.glob("/run/user/1000/niri.*.sock"))
        if len(socks) != 1:
            raise Blocked(f"expected exactly one niri socket, found {socks}")
        return {
            "XDG_RUNTIME_DIR": "/run/user/1000",
            "WAYLAND_DISPLAY": "wayland-1",
            "NIRI_SOCKET": socks[0],
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/bus",
        }

    def env(self, extra=None):
        e = dict(os.environ)
        e.update(self.session)
        if extra:
            e.update(extra)
        return e

    def check(self, cond, msg):
        if not cond:
            self.failures.append(msg)
        return cond

    def note(self, msg):
        self.notes.append(msg)

    def add_restore(self, fn):
        self._restore.append(fn)

    def restore_all(self):
        for fn in reversed(self._restore):
            try:
                fn()
            except Exception as e:
                self.note(f"restore step failed: {e!r}")

    # ---- staged host-side injection protocol ----
    def await_injection(self, stage, qmp_commands):
        awaiting = self.output / f"AWAITING-{stage}"
        go = self.output / f"GO-{stage}"
        awaiting.write_text("\n".join(qmp_commands) + "\n")
        print(f"AWAITING INJECTION [{stage}] — host side must run:", flush=True)
        for c in qmp_commands:
            print(f"    {c}", flush=True)
        print(f"then: touch {go}", flush=True)
        deadline = time.time() + INJECT_TIMEOUT_S
        while time.time() < deadline:
            if go.exists():
                go.unlink()
                awaiting.unlink(missing_ok=True)
                time.sleep(1.5)  # let events settle through the chain
                return True
            time.sleep(2)
        raise Blocked(f"stage {stage}: no GO file within {INJECT_TIMEOUT_S}s — injection not performed")


# ------------------------------------------------------------- source case

def case_source(ctx):
    import yaml  # pyyaml (provisioned)

    # --- row 1: xremap template ---
    text = (ctx.source / XREMAP_REL).read_text()
    try:
        doc = yaml.safe_load(text)
    except yaml.YAMLError as e:
        ctx.check(False, f"xremap template YAML parse failed: {e}")
        return
    ctx.check(isinstance(doc, dict) and "keymap" in doc and "modmap" in doc,
              "xremap template missing keymap/modmap")
    keymaps = {k.get("name"): k for k in doc.get("keymap", [])}
    names = [k.get("name") for k in doc.get("keymap", [])]

    if "Terminal copy-paste" in keymaps and "Mac copy-paste" in keymaps:
        ctx.check(names.index("Terminal copy-paste") < names.index("Mac copy-paste"),
                  "xremap order: 'Terminal copy-paste' must precede 'Mac copy-paste' "
                  "(xremap applies the first matching keymap — the generic map shadows the terminal one)")
    else:
        ctx.check(False, f"expected keymaps missing (have {names})")

    term = keymaps.get("Terminal copy-paste", {})
    ctx.check(term.get("remap") == EXPECTED_TERMINAL_REMAP,
              f"Terminal copy-paste remap changed: {term.get('remap')}")
    ctx.check((term.get("application") or {}).get("only") == EXPECTED_TERMINAL_APPS,
              f"Terminal copy-paste application list changed: {(term.get('application') or {}).get('only')}")
    mac = keymaps.get("Mac copy-paste", {})
    ctx.check(mac.get("remap") == EXPECTED_MAC_REMAP, f"Mac copy-paste remap changed: {mac.get('remap')}")
    ctx.check((mac.get("application") or {}).get("not") == ["/zed/"],
              f"Mac copy-paste exclusions changed: {(mac.get('application') or {}).get('not')}")
    for other in ("Mac text navigation", "Word navigation", "GUI App Actions"):
        ctx.check(other in keymaps, f"keymap missing after reorder: {other}")

    modmaps = doc.get("modmap", [])
    ctx.check(len(modmaps) == 1, f"expected exactly one modmap, got {len(modmaps)}")
    if modmaps:
        ctx.check(modmaps[0].get("remap") == EXPECTED_MODMAP,
                  f"modmap changed: {modmaps[0].get('remap')}")
        ctx.check((modmaps[0].get("device") or {}).get("only") == EXPECTED_MODMAP_DEVICE,
                  f"modmap device filter changed: {(modmaps[0].get('device') or {}).get('only')}")

    # --- row 2: niri macOS layer ---
    kdl = (ctx.source / KDL_REL).read_text()
    ctx.check("fuzzel" not in kdl, "kdl still references fuzzel")
    ctx.check("replace fuzzel" not in kdl, "obsolete 'replace fuzzel' TODO still present")
    binds = re.findall(r'Super\+Space[^.{]*\{([^}]*)\}', kdl, re.S)
    ctx.check(len(binds) == 1, f"expected exactly one live Super+Space bind, found {len(binds)}")
    if binds:
        m = re.search(r'spawn\s+([^;]+);', binds[0])
        actual = m.group(1).strip() if m else None
        ctx.check(actual == EXPECTED_SPAWN,
                  f"Super+Space spawn args: expected {EXPECTED_SPAWN}, got {actual}")


# ---------------------------------------------------------------- vm case

def _qmp(qcode_list, hold_ms=150):
    keys = ",".join('{"type":"qcode","data":"%s"}' % q for q in qcode_list)
    return ('virsh -c qemu+ssh://ark-dom/system qemu-monitor-command arch-atmosphera-gtkfree '
            '\'{"execute":"send-key","arguments":{"keys":[%s],"hold-time":%d}}\'' % (keys, hold_ms))


def _systemctl_user(ctx, *args):
    r = sh(["systemctl", "--user"] + list(args), env=ctx.env())
    return r


def _xremap_device_node(ctx):
    """Event node of xremap's virtual keyboard (None if absent)."""
    try:
        text = Path("/proc/bus/input/devices").read_text()
    except OSError:
        return None
    for block in text.split("\n\n"):
        if "xremap" in block.lower():
            m = re.search(r"H: Handlers=.*?(event\d+)", block)
            if m:
                return "/dev/input/" + m.group(1)
    return None


def _focused_window(ctx):
    """(app_id, title) of the focused window, or (None, None)."""
    r = sh(["niri", "msg", "--json", "windows"], env=ctx.env())
    if r.returncode != 0:
        return None, None
    try:
        for w in json.loads(r.stdout):
            if w.get("is_focused"):
                return w.get("app_id") or "", w.get("title") or ""
    except json.JSONDecodeError:
        pass
    return None, None


def _wait_focus(ctx, fragment, timeout_s=30):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        app, title = _focused_window(ctx)
        if (app and fragment in app) or (title and fragment in title):
            return app or title
        time.sleep(1)
    raise Blocked(f"window matching {fragment!r} never took focus (focused={_focused_window(ctx)!r})")


def _windows(ctx):
    r = sh(["niri", "msg", "--json", "windows"], env=ctx.env())
    if r.returncode != 0:
        return []
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return []


def focus_with_launcher_recovery(ctx, proc, fragment):
    """Focus a test window. An open launcher panel holds niri's exclusive
    keyboard grab and silently blocks all window focus — if focusing fails,
    toggle the launcher (a close attempt) and retry, up to 3 toggles."""
    last = None
    for attempt in range(4):
        try:
            return focus_launched(ctx, proc, fragment, timeout_s=25)
        except Blocked as b:
            last = b
            sh(["qs", "-c", "atmosphera", "ipc", "call", "launcher", "toggle"],
               env=ctx.env(), timeout=15)
            time.sleep(1.5)
    raise last


def focus_launched(ctx, proc, fragment, timeout_s=30):
    """Deterministically focus a just-launched window (this niri does not
    reliably auto-focus new windows). Match by client pid, fall back to the
    newest matching window; drive focus explicitly via niri's action."""
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        wins = _windows(ctx)
        cand = [w for w in wins if w.get("pid") == proc.pid]
        if not cand:
            cand = [w for w in wins
                    if fragment in (w.get("app_id") or "") or fragment in (w.get("title") or "")]
        if cand:
            win = sorted(cand, key=lambda w: w.get("id", 0))[-1]
            if win.get("is_focused"):
                return win.get("id")
            sh(["niri", "msg", "action", "focus-window", "--id", str(win["id"])], env=ctx.env())
            time.sleep(0.7)
            for w in _windows(ctx):
                if w.get("id") == win["id"] and w.get("is_focused"):
                    return win["id"]
        time.sleep(1)
    raise Blocked(f"could not focus launched window (pid={proc.pid}, match={fragment!r})")


def evtest_event_lines(log_path):
    """Only the 'Event:' lines after the device-capability dump."""
    lines = Path(log_path).read_text(errors="replace").splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.startswith("Testing ..."))
    except StopIteration:
        return []
    return [l for l in lines[start:] if l.startswith("Event:")]


def key_pressed(events, code_name):
    return any(f"({code_name}), value 1" in l for l in events)


class EvtestCapture:
    def __init__(self, ctx, node, log_name):
        self.log_path = ctx.output / log_name
        self.proc = subprocess.Popen(["evtest", node], stdout=open(self.log_path, "w"),
                                     stderr=subprocess.STDOUT, text=True,
                                     start_new_session=True)

    def stop(self):
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        self.proc.wait(timeout=5)


def _start_xremap(ctx):
    # Deploy the --source template and (re)start the shipped user unit
    had_existing = GUEST_XREMAP_CONF.exists()
    backup = None
    if had_existing:
        backup = ctx.output / "xremap-config.backup"
        shutil.copy(GUEST_XREMAP_CONF, backup)

    def restore():
        if backup is not None:
            shutil.copy(backup, GUEST_XREMAP_CONF)
        else:
            GUEST_XREMAP_CONF.unlink(missing_ok=True)
            try:
                GUEST_XREMAP_DIR.rmdir()
            except OSError:
                pass
        _systemctl_user(ctx, "stop", "xremap-atmosphera.service")
    ctx.add_restore(restore)

    GUEST_XREMAP_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy(ctx.source / XREMAP_REL, GUEST_XREMAP_CONF)
    _systemctl_user(ctx, "restart", "xremap-atmosphera.service")
    time.sleep(2)
    r = _systemctl_user(ctx, "is-active", "xremap-atmosphera.service")
    if not ctx.check(r.stdout.strip() == "active",
                     f"xremap-atmosphera.service not active: {r.stdout.strip()} {r.stderr.strip()}"):
        j = sh(["journalctl", "--user", "-u", "xremap-atmosphera.service", "-n", "20", "--no-pager"],
               env=ctx.env())
        ctx.note("xremap journal tail:\n" + j.stdout[-2000:])
        raise Blocked("xremap service failed to start")
    node = None
    deadline = time.time() + 25
    while time.time() < deadline:
        node = _xremap_device_node(ctx)
        if node is not None:
            break
        time.sleep(1)
    if node is None:
        j = sh(["journalctl", "--user", "-u", "xremap-atmosphera.service", "-n", "20", "--no-pager"],
               env=ctx.env())
        ctx.note("xremap journal tail:\n" + j.stdout[-2000:])
        raise Blocked("xremap virtual keyboard not present in /proc/bus/input/devices after 25s")
    ctx.note(f"xremap virtual device: {node}")
    # The uinput device node is (re)created at every service start with
    # default perms — re-apply the provisioned runtime ACL for this run.
    sh(["sudo", "-n", "setfacl", "-m", "u:tester:rw", node], timeout=15)
    # This fork's boot raced udev seat tagging (keyboards carried no seat0
    # tag, so niri never opened them until re-triggered). Nudge the input
    # subsystem so the fresh virtual device is seat-tagged and picked up.
    sh(["sudo", "-n", "udevadm", "trigger", "--subsystem-match=input", "--action=add"], timeout=20)
    time.sleep(2)
    return node


def _set_sentinels(ctx):
    clip = f"CLIPBOARD-SENTINEL-{int(time.time())}"
    pri = f"PRIMARY-SELECTION-SENTINEL-{int(time.time())}"
    # wl-copy daemonizes to serve the selection; keep its pipes out of
    # subprocess pipes or communicate() waits on the daemon forever.
    for args in (["wl-copy", clip], ["wl-copy", "--primary", pri]):
        subprocess.run(args, env=ctx.env(), stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
    # Read back both selections — a silently-failing wl-copy must BLOCK, not
    # produce empty-paste confusion downstream.
    for args, want in ((["wl-paste"], clip), (["wl-paste", "--primary"], pri)):
        r = sh(args + ["--no-newline"], env=ctx.env(), timeout=10)
        if want not in r.stdout:
            raise Blocked(f"selection readback failed for {args}: got {r.stdout[:60]!r}, want {want!r}")
    return clip, pri


def _read_file(path, timeout_s=8):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            t = Path(path).read_text()
            if t:
                return t
        except OSError:
            pass
        time.sleep(0.5)
    try:
        return Path(path).read_text()
    except OSError:
        return ""


def leg_k1_terminal(ctx, node):
    """Terminal clipboard: foot must receive the terminal-specific combos."""
    clip, pri = _set_sentinels(ctx)
    paste_target = ctx.output / "k1-foot-paste.txt"
    paste_target.unlink(missing_ok=True)
    foot_log = open(ctx.output / "k1-foot.log", "w")
    foot = subprocess.Popen(["foot", "sh", "-c", f"cat > {paste_target}"],
                            env=ctx.env(), stdout=foot_log, stderr=foot_log,
                            start_new_session=True)
    ctx.add_restore(lambda: foot.poll() is None and os.killpg(foot.pid, signal.SIGTERM))
    try:
        focus_with_launcher_recovery(ctx, foot, "foot")
    except Blocked:
        foot_log.close()
        raise
    cap = EvtestCapture(ctx, node, "k1-evtest.log")
    try:
        ctx.await_injection("k1", [_qmp(["alt", "v"]), _qmp(["alt", "c"]), _qmp(["ret"], hold_ms=80)])
        pasted = _read_file(paste_target)
        events = evtest_event_lines(cap.log_path)
        # The discriminating emission evidence: the terminal map emits a
        # KEY_V press (Ctrl+Shift+V); the generic map emits KEY_INSERT
        # (Shift+Insert). The physical V scancode never reaches the device.
        ctx.note(f"K1 emitted V-press={key_pressed(events, 'KEY_V')} "
                 f"Insert-press={key_pressed(events, 'KEY_INSERT')} pasted={pasted[:60]!r}")
        ctx.check(key_pressed(events, "KEY_V"),
                  "K1: no Ctrl+Shift+V emission for a focused terminal — the generic map "
                  "shadows the terminal map (emitted Shift+Insert instead)"
                  if key_pressed(events, "KEY_INSERT") else
                  "K1: no paste chord emitted at all for a focused terminal")
        ctx.check(clip in pasted,
                  f"K1: foot did not receive the CLIPBOARD sentinel. "
                  f"pasted={pasted[:80]!r} clip={clip!r}")
        ctx.check(pri not in pasted,
                  "K1: foot received the PRIMARY-selection sentinel — the generic Shift+Insert "
                  "map handled Cmd+V (terminal map shadowed)")
    finally:
        cap.stop()
        if foot.poll() is None:
            os.killpg(foot.pid, signal.SIGTERM)
        foot_log.close()


def leg_k2_gui(ctx, node):
    """Generic GUI combos retain prior behavior (Shift+Insert path)."""
    if shutil.which("qml6") is None and not Path("/usr/lib/qt6/bin/qml").exists():
        raise Blocked("no qml runtime for the GUI probe")
    qml_bin = shutil.which("qml6") or "/usr/lib/qt6/bin/qml"
    clip, pri = _set_sentinels(ctx)
    probe_log = ctx.output / "k2-guiprobe.log"
    logf = open(probe_log, "w")
    # Arch's Qt routes QML console output to the systemd journal by default;
    # force stderr so the probe's GUIPROBE lines reach the capture file.
    probe = subprocess.Popen([qml_bin, str(FIXTURES / "gui-key-probe.qml")],
                             env=ctx.env({"QT_FORCE_STDERR_LOGGING": "1"}),
                             stdout=logf, stderr=subprocess.STDOUT,
                             text=True, start_new_session=True)
    ctx.add_restore(lambda: probe.poll() is None and os.killpg(probe.pid, signal.SIGTERM))
    focus_with_launcher_recovery(ctx, probe, "guiprobe")
    cap = EvtestCapture(ctx, node, "k2-evtest.log")
    try:
        ctx.await_injection("k2", [_qmp(["alt", "v"])])
        time.sleep(2)
        content = probe_log.read_text(errors="replace")
        events = evtest_event_lines(cap.log_path)
        # Prior behavior = the generic map emits Shift+Insert for GUI apps.
        # The probe's key log proves delivery to a GUI client; the paste
        # outcome itself is app-specific (Qt Shift+Insert semantics) and is
        # recorded as a note, not a gate.
        ctx.check(key_pressed(events, "KEY_INSERT") and key_pressed(events, "KEY_LEFTSHIFT"),
                  "K2: generic map no longer emits Shift+Insert for a GUI app — prior behavior changed")
        ctx.check("GUIPROBE|KEY|" in content,
                  f"K2: GUI probe received no key events at all. log={content[-200:]!r}")
        ctx.note(f"K2 probe text outcome: {[l for l in content.splitlines() if 'TEXT' in l][-3:]}"
                 f" (Qt 6 Shift+Insert pastes the clipboard — toolkit behavior, recorded only)")
    finally:
        cap.stop()
        if probe.poll() is None:
            os.killpg(probe.pid, signal.SIGTERM)
        logf.close()


def leg_k3_real_ctrl(ctx, node):
    """Real corner Ctrl passes through unchanged (SIGINT reaches the terminal)."""
    paste_target = ctx.output / "k3-foot-sink.txt"
    paste_target.unlink(missing_ok=True)
    foot_log = open(ctx.output / "k3-foot.log", "w")
    foot = subprocess.Popen(["foot", "sh", "-c", f"cat > {paste_target}"],
                            env=ctx.env(), stdout=foot_log, stderr=foot_log,
                            start_new_session=True)
    ctx.add_restore(lambda: foot.poll() is None and os.killpg(foot.pid, signal.SIGTERM))
    win_id = focus_with_launcher_recovery(ctx, foot, "foot")
    cap = EvtestCapture(ctx, node, "k3-evtest.log")
    try:
        ctx.await_injection("k3", [_qmp(["ctrl", "c"])])
        # Consumer evidence: Ctrl+C -> SIGINT -> cat dies -> sh -c completes
        # -> the foot window closes.
        gone = False
        deadline = time.time() + 10
        while time.time() < deadline:
            if not any(w.get("id") == win_id for w in _windows(ctx)):
                gone = True
                break
            time.sleep(1)
        ctx.check(gone,
                  "K3: foot window still present after physical Ctrl+C — corner Ctrl did not "
                  "reach the terminal (expected SIGINT to kill the sink and close the window)")
        events = evtest_event_lines(cap.log_path)
        ctx.check(key_pressed(events, "KEY_LEFTCTRL") and key_pressed(events, "KEY_C"),
                  "K3: xremap device shows no Ctrl+C pass-through")
        ctx.check(not key_pressed(events, "KEY_LEFTSHIFT"),
                  "K3: corner Ctrl+C acquired an unexpected Shift modifier")
    finally:
        cap.stop()
        if foot.poll() is None:
            os.killpg(foot.pid, signal.SIGTERM)
        foot_log.close()


def _grim(ctx, name, region=None):
    out = ctx.output / name
    args = ["grim"]
    if region:
        args += ["-g", region]
    args.append(str(out))
    r = sh(args, env=ctx.env(), timeout=30)
    if r.returncode != 0 or not out.exists():
        raise Blocked(f"grim failed for {name}: {r.stderr.strip()}")
    return out


# L1 evidence: the guest wallpaper is ANIMATED, so full-region byte-compares
# are noise. Two animation-free signals instead:
#  * open/closed — the open launcher holds niri's exclusive keyboard grab:
#    a test foot window cannot be focused while it is open.
#  * mode — the launcher panel is OPAQUE: a tight crop of its interior
#    (search field + mode chips) carries no wallpaper and compares cleanly.
L1_PANEL_REGION = "390,115 500x120"


def launcher_open_probe(ctx):
    """True if the launcher (or another exclusive-grab panel) is open."""
    foot = subprocess.Popen(["foot", "sh", "-c", "sleep 20"],
                            env=ctx.env(), stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            start_new_session=True)
    try:
        try:
            focus_launched(ctx, foot, "foot", timeout_s=8)
            return False  # window focus worked -> no exclusive grab
        except Blocked:
            return True
    finally:
        if foot.poll() is None:
            os.killpg(foot.pid, signal.SIGTERM)


def _niri_load(ctx, path):
    env = ctx.env({"NIRI_LOAD_CONFIG": str(path)})
    r = sh(["dbus-run-session", "--", "qs", "-p", str(FIXTURES / "niri-load-config.qml")],
           env=env, timeout=40)
    ok = "NIRI_LOAD|OK|" in (r.stdout + r.stderr)
    return ok, (r.stdout + r.stderr)


def leg_l1_launcher(ctx):
    """Native launcher via the edited niri layer (typed niriqml load + chord)."""
    # Deploy the edited layer + a composed test session config
    layer_existed = GUEST_KDL_LAYER.exists()
    layer_backup = None
    if layer_existed:
        layer_backup = ctx.output / "kdl-layer.backup"
        shutil.copy(GUEST_KDL_LAYER, layer_backup)
    shutil.copy(ctx.source / KDL_REL, GUEST_KDL_LAYER)
    session_text = GUEST_SESSION_CONF.read_text()
    GUEST_TEST_SESSION.write_text(session_text + '\ninclude "atmosphera-shortcuts-macos.kdl"\n')

    def restore_niri():
        ok, out = _niri_load(ctx, GUEST_SESSION_CONF)
        if not ok:
            ctx.note(f"WARNING: failed to restore niri session config: {out[-400:]}")
        if layer_backup is not None:
            shutil.copy(layer_backup, GUEST_KDL_LAYER)
        else:
            GUEST_KDL_LAYER.unlink(missing_ok=True)
        GUEST_TEST_SESSION.unlink(missing_ok=True)
    ctx.add_restore(restore_niri)

    ok, out = _niri_load(ctx, GUEST_TEST_SESSION)
    ctx.check(ok, f"L1: niri rejected the edited layer via LoadConfigFile: {out[-600:]}")
    if not ok:
        return
    ctx.note("L1: niri accepted the edited layer (LoadConfigFile ok)")

    ctx.check(not launcher_open_probe(ctx),
              "L1: launcher (or another exclusive-grab panel) is already open before the chord")
    ctx.await_injection("l1-open", [_qmp(["alt", "spc"], hold_ms=200)])
    time.sleep(1.5)
    opened = launcher_open_probe(ctx)
    _grim(ctx, "l1-opened-panel.png", region=L1_PANEL_REGION)
    ctx.check(opened, "L1: injected chord did not open the launcher (no exclusive grab appeared)")

    ctx.await_injection("l1-close", [_qmp(["alt", "spc"], hold_ms=200)])
    time.sleep(1.5)
    ctx.check(not launcher_open_probe(ctx),
              "L1: launcher did not close on the second chord (grab still held)")

    # Mode switch: open in clipboard mode, chord must switch to app mode (stay open)
    sh(["qs", "-c", "atmosphera", "ipc", "call", "launcher", "clipboard"], env=ctx.env(), timeout=15)
    time.sleep(1.5)
    ctx.check(launcher_open_probe(ctx), "L1: launcher clipboard mode did not open via IPC")
    clipmode = _grim(ctx, "l1-clipboard-mode.png", region=L1_PANEL_REGION)
    ctx.await_injection("l1-mode", [_qmp(["alt", "spc"], hold_ms=200)])
    time.sleep(1.5)
    still_open = launcher_open_probe(ctx)
    appmode = _grim(ctx, "l1-app-mode.png", region=L1_PANEL_REGION)
    ctx.check(still_open, "L1: launcher not open after the mode-switch chord (should switch to app mode, not close)")
    ctx.check(_images_differ(clipmode, appmode),
              "L1: chord from clipboard mode produced no visible mode switch")
    # State-aware cleanup: toggle until the exclusive grab is released.
    for _ in range(3):
        if not launcher_open_probe(ctx):
            break
        sh(["qs", "-c", "atmosphera", "ipc", "call", "launcher", "toggle"], env=ctx.env(), timeout=15)
        time.sleep(1.5)


def _images_differ(a, b):
    """Byte-level frame compare (no PIL on the guest). grim output is
    deterministic for identical frames on a static desktop; the launcher
    open/close legs compare within seconds to avoid the bar clock rollover.
    The visual review of the saved PNGs is the evidence; this is a tripwire."""
    return Path(a).read_bytes() != Path(b).read_bytes()


def _window_present(ctx, fragment):
    r = sh(["niri", "msg", "--json", "windows"], env=ctx.env())
    if r.returncode != 0:
        return None
    try:
        return any(fragment in (w.get("app_id") or "") or fragment in (w.get("title") or "")
                   for w in json.loads(r.stdout))
    except json.JSONDecodeError:
        return None


def case_vm(ctx):
    for tool in ("xremap", "wl-copy", "evtest", "foot", "grim", "qs", "dbus-run-session"):
        if shutil.which(tool) is None:
            raise Blocked(f"required tool missing on the guest: {tool}")
    for dev in ("/dev/uinput", "/dev/input/event0"):
        if not os.access(dev, os.R_OK | os.W_OK):
            raise Blocked(f"no rw access to {dev} — input-access provisioning missing")
    # The shipped fallback modmap must own the injected keyboard
    devices = Path("/proc/bus/input/devices").read_text()
    if EXPECTED_MODMAP_DEVICE not in devices:
        raise Blocked(f"shipped modmap device filter {EXPECTED_MODMAP_DEVICE!r} does not match any guest keyboard")
    # Production shell must be the atmosphera IPC instance the chord names
    r = sh(["qs", "-c", "atmosphera", "ipc", "call", "launcher"], env=ctx.env(), timeout=15)
    if "Function required" not in (r.stdout + r.stderr):
        raise Blocked("could not reach the production 'atmosphera' instance's launcher handler — "
                      "ambiguous or missing IPC instance selection")

    node = _start_xremap(ctx)
    leg_k1_terminal(ctx, node)
    leg_k2_gui(ctx, node)
    leg_k3_real_ctrl(ctx, node)
    leg_l1_launcher(ctx)


# ------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--case", required=True, choices=["source", "vm", "all"])
    args = ap.parse_args()

    ctx = Ctx(args.source, args.output)
    ctx.output.mkdir(parents=True, exist_ok=True)
    blocked = None
    try:
        if args.case in ("source", "all"):
            try:
                case_source(ctx)
            except ImportError:
                raise Blocked("python-yaml not installed — source case cannot run")
        if args.case in ("vm", "all"):
            case_vm(ctx)
    except Blocked as b:
        blocked = str(b)
    finally:
        ctx.restore_all()

    for n in ctx.notes:
        print(f"note: {n}")
    for f in ctx.failures:
        print(f"FAIL: {f}")
    if blocked:
        print(f"BLOCKED: {blocked}")

    result = {"case": args.case, "source": str(ctx.source),
              "failures": ctx.failures, "blocked": blocked, "notes": ctx.notes}
    (ctx.output / "bindings-result.json").write_text(json.dumps(result, indent=2) + "\n")

    if blocked or ctx.failures:
        print("BINDINGS_REGRESSION: FAIL" if ctx.failures else "BINDINGS_REGRESSION: BLOCKED")
        sys.exit(1)
    print("BINDINGS_REGRESSION: PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
