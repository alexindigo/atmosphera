#!/usr/bin/env python3
"""Guest-only regression: InputMethodService against fcitx5's controller (M21).

usage: inputmethod-regression.py --source TREE --work DIR --output DIR --profile {A,B,C,D}

Run in the Qt612 niri VM (arch-niri-atmosphera-qt612-color on ark.home), never on
the host. --work must not exist: the script copies TREE to WORK/shell and writes
the shell profile to WORK/profile. TREE is never modified. --output must not
exist and receives result.json, trace.txt and the journals.

Profiles. C is defined by a later milestone and exits 3 here.
  A  fcitx5 running with one group, Default (keyboard-us, keyboard-de,
     keyboard-ru). Case 7: next three times cycles us -> de -> ru -> us.
     Case 14 (M24b): the guest's shipped atmosphera-i18n.kdl is still in
     place and legacyI18nChecked is unset, so the first shell start converts
     it. Neither mozc nor keyboard-ru-mac is in a group, so no switch is made,
     one notice names both, and the file is retired (backed up, removed).
  B  fcitx5 running with the profile this script writes: group US+RU
     (keyboard-us, keyboard-ru-mac) first, then US+JP (keyboard-us, mozc).
     A small focus window (qml6) holds a focused input context, because
     fcitx5 reports an empty CurrentInputMethod while no context has focus.
     Cases 1-3 and 5, 6, 8 with the shell running; case 9 with the shell
     stopped, drives the secure-mode fixture (Scripts/dev/fixtures/
     input-method-secure-mode.qml) as the only shell-side client.
     Cases 10 and 11 (M24) are niri checks on the guest's own ~/.config/niri.
     Case 10: a fresh profile without atmosphera-i18n.kdl
     gets atmosphera-input.kdl, the session does not include the i18n file, and
     the file shows a combo change within 1 s of the shell applying it. Case 11: with the shipped i18n file
     present, a switch on Alt+Space is skipped and logged, Super+Alt+J is not.
     Case 12: on three shell starts, setIM mozc at the first available state,
     before the startup metadata refresh, must dispatch and reach US+JP/mozc.
     Cases 13-16 (M24b) cover the legacy i18n file. The profile starts with
     legacyI18nChecked true, so cases 10-12 keep the shipped file as it is.
     Case 13: the shipped file is put back with the flag unset, and the next
     start converts it into two switches (backup, removal). Case 16: the start
     after 13 changes nothing. Case 15: a hand-edited file is kept and
     untouched, its Super+Space conflict is skipped, and importLegacyI18n()
     (run by a fixture with the shell stopped) converts it once; an
     unparseable file is refused without changes.
  D  fcitx5 not running. The shell's DBus proxy activates org.fcitx.Fcitx5 on
     its own (the service file in /usr/share/dbus-1/services), so D lets the
     shell attach to the activated fcitx5, stops it, and then runs case 4.

Truth comes from fcitx5 through gdbus, never from the shell. The shell is driven
through `qs -p <work>/shell/shell.qml ipc call inputmethod ...`. The layout toast
is read from the shell's journal ("Layout toast:" lines); the state file from
$XDG_RUNTIME_DIR/fcitx-input-state.json.

Transient user units, all named after the output basename: imreg-<name>-fcitx5,
imreg-<name>-focus, imreg-<name>-shell, imreg-<name>-fixture, and imreg-<name>-legacy-<tag>
(the legacy import fixture, M24b). Each is stopped in
a finally block, as is any qs or fcitx5 left running, including D-Bus-activated
fcitx5 units (dbus-*org.fcitx.Fcitx5*). The fcitx5 profile is
~/.config/fcitx5/profile.

Compositors (M27). The compositor is detected from its running instance (niri socket,
Hyprland instance with a live .socket.sock, mangowc socket); exactly one must run. niri
runs every profile and case. Every niri run backs up ~/.config/niri into WORK/niri-backup
before starting a shell and restores it in finally (session and input files excepted;
niri validate must pass afterwards), regardless of the profile or selected cases.
Hyprland and mangowc run profile B with --cases 10 only:
the generated input-method bind file (hyprlang, the Lua route when hyprland.lua exists,
or mangowc's conf), the compositor's own config check, a combo change in the file with
the reload, and Hyprland's bind table (hyprctl binds -j) after the change. Case 10 is
measured as on niri: from the shell's "settings changed; regenerating" line to the file
(<= 1 s). Both change only after the shell has settled from its startup. Their config
directory is backed up into WORK/compositor-backup before the run and restored in finally
(the input files are rewritten header-only and the compositor reloaded).

Key presses (M29, --keys). The cases K1-K8 press real keys: the host driver
(tools/im-keys.sh, QEMU send-key into the named VM) presses the combo the guest asks for. The
guest writes OUTPUT/keys/ready-<step>.json and waits for OUTPUT/keys/sent-<step>.json; the
driver writes sent after it sent the key, and the guest writes keys/finished when the run
ends. The bind runs `atmosphera ipc`, which reaches only a shell named `atmosphera`: for a
--keys run the test tree is linked as ~/.config/quickshell/atmosphera (refused if that exists)
and removed in finally. The setup proves that `atmosphera ipc inputmethod state` answers
from this shell before the first key. On niri the shipped atmosphera-i18n.kdl is moved
aside for --keys runs (restored with the rest of ~/.config/niri). With --keys the run holds
only the key cases of its profile: A K4; B K1 K2 K3 K5 K8; C K6; D K7a K7b (K7b restarts the
shell with a PATH that has no fcitx5). Profile C is profile B's groups with keyboard-fr in no
group. Any compositor runs --keys; without --keys the cases stay as above.

K5 is an expected failure on mango 0.17.5, which repeats held binds and has no
non-repeating bind flag. It still runs and records the dispatch count; an unexpected
pass is reported but non-fatal. K5 remains strict on niri and Hyprland.

Exit: 0 when every case passes (or is an accepted mango K5 outcome) and cleanup is clean; 1 when a case or the cleanup
fails; 3 on a setup or precondition failure (the run is not evaluated).
"""
import argparse
import ast
from dataclasses import dataclass, field
import glob
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import time

HOME = '/home/tester'
RUNTIME = '/run/user/1000'
BUS = f'unix:path={RUNTIME}/bus'
MIN_FREE_BYTES = 64 * 1024 * 1024
MIN_FREE_INODES = 30000
PROFILES = ('A', 'B', 'C', 'D')
GROUP_RU = 'US+RU'
GROUP_JP = 'US+JP'
GROUP_DEFAULT = 'Default'
# Group order matters: the first group is fcitx5's default.
PROFILE_A = [
    (GROUP_DEFAULT, 'us', ['keyboard-us', 'keyboard-de', 'keyboard-ru']),
]
PROFILE_B = [
    (GROUP_RU, 'us', ['keyboard-us', 'keyboard-ru-mac']),
    (GROUP_JP, 'us', ['keyboard-us', 'mozc']),
]
# C: B's groups; keyboard-fr is in no group (K6 switches to it).
PROFILE_GROUPS = {'A': PROFILE_A, 'B': PROFILE_B, 'C': PROFILE_B}
# The compositor's process name, for the no-restart check of K8.
COMP_PROC = {'niri': 'niri', 'hyprland': 'Hyprland', 'mango': 'mango'}
KEY_DRIVER_WAIT = 180  # seconds the guest waits for the host driver to send one key
MODIFIERS = {'alt', 'ctrl', 'shift', 'super'}
FIXTURE = Path(__file__).resolve().parent / 'fixtures' / 'input-method-secure-mode.qml'
FIXTURE_NAME = FIXTURE.name
LEGACY_FIXTURE = Path(__file__).resolve().parent / 'fixtures' / 'input-method-legacy-import.qml'
LEGACY_FIXTURE_NAME = LEGACY_FIXTURE.name
# sha256 of the only shipped atmosphera-i18n.kdl (commit 95d03c3d5).
SHIPPED_I18N_SHA256 = '1a6c4aeda09bc15264c7a4c2eb031659bbb100e79d686c9510dd50234a7fdb35'
TOAST_MARK = 'Layout toast:'
KEY_DISPATCH_MARK = 'IMREG_KEY_DISPATCH|toggleIM|'
GDBUS = ['gdbus', 'call', '--session', '--dest', 'org.fcitx.Fcitx5', '--object-path', '/controller', '--method']
NIRI_DIR = Path(HOME) / '.config/niri'
NIRI_SESSION = 'atmosphera-session.kdl'
NIRI_INPUT = 'atmosphera-input.kdl'
NIRI_I18N = 'atmosphera-i18n.kdl'
# Every test shell regenerates the session and the input file, so the restore leaves them alone.
NIRI_KEEP = (NIRI_SESSION, NIRI_INPUT)
INPUT_HEADER = '// Generated by Atmosphera from Settings \u2192 Shortcuts. Do not edit.\n'
GENERATED_TEXT = 'Generated by Atmosphera from Settings \u2192 Shortcuts. Do not edit.'
COMPOSITORS = ('niri', 'hyprland', 'mango')
# Wayland socket of each compositor's session (niri and Hyprland: wayland-1, mangowc: wayland-0).
WAYLAND = {'niri': 'wayland-1', 'hyprland': 'wayland-1', 'mango': 'wayland-0'}
WM_DIRS = {'hyprland': Path(HOME) / '.config/hypr', 'mango': Path(HOME) / '.config/mango'}
# The file the generator always writes; Hyprland's Lua route also writes atmosphera-input.lua.
WM_INPUT = 'atmosphera-input.conf'
WM_INPUT_LUA = 'atmosphera-input.lua'
# The compositor running the session (set by main from the running instance).
COMP = 'niri'
COMP_INSTANCE = ''
SWITCH_JA = {'keys': ['Alt+Space'], 'target': 'mozc', 'mode': 'toggle', 'label': 'Japanese'}
BIND_JA = ('Alt+Space repeat=false allow-when-locked=true hotkey-overlay-title="Input method: Japanese" '
           '{ spawn "atmosphera" "ipc" "inputmethod" "toggleIM" "mozc"; }')
BIND_CTRL_ALT_JA = BIND_JA.replace('Alt+Space', 'Ctrl+Alt+Space', 1)
FOCUS_QML = '''import QtQuick
import QtQuick.Controls
ApplicationWindow {
  width: 320; height: 120; visible: true; title: "imreg-focus"
  TextField { anchors.centerIn: parent; width: 260; focus: true }
}
'''


class SetupError(RuntimeError):
    """Setup or precondition failure: the run is not evaluated (exit 3)."""


def sh(argv, timeout=60):
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout)


def fcitx5_profile(groups):
    lines = []
    for i, (name, layout, ims) in enumerate(groups):
        lines += [f'[Groups/{i}]', '# Group Name', f'Name={name}', '# Layout', f'Default Layout={layout}',
                  '# Default Input Method', f'DefaultIM={ims[0]}', '']
        for j, im in enumerate(ims):
            lines += [f'[Groups/{i}/Items/{j}]', '# Name', f'Name={im}', '# Layout', 'Layout=', '']
    lines += ['[GroupOrder]', *[f'{i}={name}' for i, (name, _, _) in enumerate(groups)], '']
    return '\n'.join(lines)


@dataclass
class Ctx:
    source: Path
    work: Path
    output: Path
    profile: str
    name: str
    keys: bool = False
    shell_unit: str = ''
    fcitx_unit: str = ''
    focus_unit: str = ''
    fixture_unit: str = ''
    niri_backup: object = None
    wm_backup: object = None
    path_override: str = ''  # PATH for the shell (K7b: a directory without fcitx5)
    cli_link: object = None  # ~/.config/quickshell/atmosphera, while a --keys run holds it
    cli_dir_made: bool = False
    units: list = field(default_factory=list)
    notes: list = field(default_factory=list)

    def __post_init__(self):
        self.shell_unit = f'imreg-{self.name}-shell'
        self.fcitx_unit = f'imreg-{self.name}-fcitx5'
        self.focus_unit = f'imreg-{self.name}-focus'
        self.fixture_unit = f'imreg-{self.name}-fixture'

    @property
    def shell_qml(self):
        # --keys: qs -c (the bind's route) matches instances by the path string, so the shell and every ipc
        # call of the run use the user-level link path, not the work path (which qs does not match to it).
        if self.cli_link is not None:
            return Path(self.cli_link) / 'shell.qml'
        return self.work / 'shell' / 'shell.qml'

    @property
    def profile_dir(self):
        return self.work / 'profile'

    def trace(self, text):
        with open(self.output / 'trace.txt', 'a') as f:
            f.write(f'{time.strftime("%H:%M:%S")} {text}\n')


def preflight(source, work, output, profile, cases, keys):
    if profile not in PROFILES:
        raise SetupError(f'profile {profile} not defined')
    if COMP != 'niri' and not keys and (profile != 'B' or cases != ['10']):
        raise SetupError(f'{COMP}: only profile B with --cases 10 is defined without --keys (the other cases check niri files)')
    if not (source / 'shell.qml').is_file() or not (source / 'Configs/defaults.json').is_file():
        raise SetupError(f'{source} is not a shell tree (shell.qml / Configs/defaults.json missing)')
    if work.exists():
        raise SetupError(f'work dir already exists: {work}')
    if output.exists():
        raise SetupError(f'output dir already exists: {output}')
    if os.path.expanduser('~') != HOME:
        raise SetupError(f'HOME is {os.path.expanduser("~")}, expected {HOME}')
    free = os.statvfs(RUNTIME)
    if free.f_bavail * free.f_frsize < MIN_FREE_BYTES:
        raise SetupError(f'{RUNTIME} has less than 64 MiB free; clear stale quickshell runtime first')
    inodes = os.statvfs(output.parent)
    if inodes.f_favail < MIN_FREE_INODES:
        raise SetupError(f'{output.parent} has fewer than {MIN_FREE_INODES} free inodes')
    if sh(['pgrep', '-x', 'qs']).returncode == 0:
        raise SetupError('a qs process is already running in the guest; stop it first')
    if sh(['pgrep', '-x', 'fcitx5']).returncode == 0:
        raise SetupError('a fcitx5 process is already running in the guest; stop it first')


def setup_work(ctx):
    ctx.work.mkdir(parents=True)
    shutil.copytree(ctx.source, ctx.work / 'shell', symlinks=True)
    if ctx.keys:
        # Observe incoming switch calls in the disposable test copy, before any
        # service queuing. Generated binds and product source stay untouched.
        handler = ctx.work / 'shell/Services/Control/IPCService.qml'
        text = handler.read_text()
        # QML permits an omitted return annotation (the pre-I6b/M20 handler).
        # Observe the same callable contract across source versions rather than
        # making the negative-control baseline implement today's return type.
        declaration = (r'(?m)^(?P<indent>[ \t]*)function[ \t]+toggleIM[ \t]*\('
                       r'[ \t]*name[ \t]*:[ \t]*string[ \t]*,[ \t]*group[ \t]*:[ \t]*string[ \t]*\)'
                       r'[ \t]*(?::[ \t]*\w+[ \t]*)?\{[ \t]*\n')
        matches = list(re.finditer(declaration, text))
        if len(matches) != 1:
            raise SetupError('expected one toggleIM handler for key dispatch observation')
        match = matches[0]
        marker = f'{match.group("indent")}  console.log("{KEY_DISPATCH_MARK}" + name);\n'
        handler.write_text(text[:match.end()] + marker + text[match.end():])
    for name in ('config', 'cache', 'state'):
        (ctx.profile_dir / name).mkdir(parents=True)
    settings = json.loads((ctx.source / 'Configs/defaults.json').read_text())
    settings['general']['showChangelogOnStartup'] = False
    # B and C start with the legacy check already done (cases 10-12 keep the shipped file); A starts unchecked
    # (case 14). Key runs never convert the legacy file (the key cases move it aside on niri).
    settings.setdefault('inputMethod', {})['legacyI18nChecked'] = ctx.profile in ('B', 'C') or ctx.keys
    (ctx.profile_dir / 'config' / 'settings.json').write_text(json.dumps(settings))
    (ctx.work / 'focus').mkdir()
    (ctx.work / 'focus' / 'probe.qml').write_text(FOCUS_QML)
    shutil.copyfile(FIXTURE, ctx.work / 'shell' / FIXTURE_NAME)
    shutil.copyfile(LEGACY_FIXTURE, ctx.work / 'shell' / LEGACY_FIXTURE_NAME)


def write_fcitx5_profile(groups=PROFILE_B):
    path = Path(HOME) / '.config/fcitx5/profile'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(fcitx5_profile(groups))


def systemd_run(ctx, unit, argv, env):
    ctx.units.append(unit)
    cmd = ['systemd-run', '--user', f'--unit={unit}', '--collect']
    cmd += [f'--setenv={k}={v}' for k, v in env.items()]
    r = sh([*cmd, *argv])
    if r.returncode:
        raise SetupError(f'could not start {unit}: {(r.stderr or r.stdout).strip()}')


def base_env():
    return {'XDG_RUNTIME_DIR': RUNTIME, 'WAYLAND_DISPLAY': WAYLAND[COMP],
            'DBUS_SESSION_BUS_ADDRESS': BUS}


def compositor_env():
    """Environment that makes a shell (and the reload commands) see the running compositor."""
    if COMP == 'niri':
        return {'NIRI_SOCKET': COMP_INSTANCE}
    if COMP == 'hyprland':
        return {'HYPRLAND_INSTANCE_SIGNATURE': COMP_INSTANCE}
    return {'MANGO_INSTANCE_SIGNATURE': COMP_INSTANCE, 'XDG_CURRENT_DESKTOP': 'mango'}


def gdbus(ctx, method, *args):
    r = sh([*GDBUS, f'org.fcitx.Fcitx.Controller1.{method}', *args], timeout=20)
    text = (r.stdout + r.stderr).strip()
    ctx.trace(f'gdbus {method} {" ".join(args)} -> rc {r.returncode} {text}')
    return r.returncode, text


def gvalue(ctx, method):
    rc, text = gdbus(ctx, method)
    if rc:
        return None
    try:
        return ast.literal_eval(text)[0]
    except (ValueError, SyntaxError, IndexError):
        return None


def truth(ctx):
    return {'group': gvalue(ctx, 'CurrentInputMethodGroup'), 'im': gvalue(ctx, 'CurrentInputMethod'),
            'state': gvalue(ctx, 'State')}


def truth_is(ctx, group, im):
    t = truth(ctx)
    return t['group'] == group and t['im'] == im


def ipc(ctx, fn, *args, timeout=30):
    r = sh(['qs', '-p', str(ctx.shell_qml), 'ipc', 'call', 'inputmethod', fn, *args], timeout=timeout)
    out = r.stdout.strip()
    ctx.trace(f'ipc {fn} {" ".join(args)} -> rc {r.returncode} out {out!r} err {r.stderr.strip()!r}')
    return r.returncode, out


def shell_state(ctx):
    rc, out = ipc(ctx, 'state')
    if rc:
        return None
    try:
        return json.loads(out)
    except ValueError:
        return None


def shell_matches(ctx, group, im):
    s = shell_state(ctx)
    return bool(s) and s.get('group') == group and s.get('im') == im


def wait_for(pred, seconds, step=0.1):
    """(matched, seconds taken): polls pred() until it is true or `seconds` pass."""
    start = time.monotonic()
    while True:
        if pred():
            return True, round(time.monotonic() - start, 2)
        if time.monotonic() - start >= seconds:
            return False, round(time.monotonic() - start, 2)
        time.sleep(step)


def journal_of(ctx, unit):
    return sh(['journalctl', '--user', '-u', unit, '--no-pager', '-o', 'cat'], timeout=120).stdout


def journal(ctx):
    return journal_of(ctx, ctx.shell_unit)


def activated_fcitx5_units():
    out = sh(['systemctl', '--user', 'list-units', '--all', '--no-legend', '--plain', '--',
              'dbus-*org.fcitx.Fcitx5*']).stdout
    return [line.split()[0] for line in out.splitlines() if line.strip()]


def fcitx5_running():
    return sh(['pgrep', '-x', 'fcitx5']).returncode == 0


def start_fcitx5(ctx, groups):
    first = groups[0][0]
    write_fcitx5_profile(groups)
    systemd_run(ctx, ctx.fcitx_unit, ['/usr/bin/fcitx5'], base_env())
    ok, took = wait_for(lambda: gvalue(ctx, 'CurrentInputMethodGroup') == first, 30)
    if not ok:
        raise SetupError(f'fcitx5 did not answer on org.fcitx.Fcitx5 with group {first}')


def start_focus(ctx):
    # fcitx5 only reports the current IM for a focused input context.
    systemd_run(ctx, ctx.focus_unit, ['/usr/bin/qml6', str(ctx.work / 'focus' / 'probe.qml')], base_env())
    ok, took = wait_for(lambda: 'focus:1' in gdbus(ctx, 'DebugInfo')[1], 30)
    if not ok:
        raise SetupError('the focus window did not give fcitx5 a focused input context')


def qs_env(ctx):
    p = ctx.profile_dir
    env = dict(base_env(), ATMOSPHERA_CONFIG_DIR=f'{p}/config/', ATMOSPHERA_CACHE_DIR=f'{p}/cache/',
               ATMOSPHERA_STATE_DIR=f'{p}/state/', ATMOSPHERA_SETTINGS_FILE=f'{p}/config/settings.json',
               ATMOSPHERA_DEBUG='0', ATMOSPHERA_UPGRADELOG_URL='http://127.0.0.1:9',
               QT_FORCE_STDERR_LOGGING='1', **compositor_env())
    if ctx.path_override:
        env['PATH'] = ctx.path_override
    return env


def start_shell(ctx):
    systemd_run(ctx, ctx.shell_unit, ['/usr/bin/qs', '-p', str(ctx.shell_qml)], qs_env(ctx))
    ok, took = wait_for(lambda: 'inputmethod' in sh(['qs', '-p', str(ctx.shell_qml), 'ipc', 'show']).stdout, 90, 0.5)
    if not ok:
        raise SetupError(f'the shell did not expose the inputmethod IPC target within 90 s (see {ctx.shell_unit})')
    ctx.trace(f'shell ready after {took} s')


def stop_shell(ctx):
    sh(['systemctl', '--user', 'stop', ctx.shell_unit], timeout=60)
    ok, took = wait_for(lambda: sh(['pgrep', '-x', 'qs']).returncode != 0, 20)
    ctx.trace(f'shell stopped: {ok} after {took} s')
    if not ok:
        raise SetupError('the shell did not stop for the secure-mode case')


def fixture_rows(ctx):
    rows = []
    for line in journal_of(ctx, ctx.fixture_unit).splitlines():
        i = line.find('INPUT_METHOD_SECURE|')
        if i >= 0:
            rows.append(json.loads(line[i + len('INPUT_METHOD_SECURE|'):]))
    return rows


def has_fixture_row(ctx, phase):
    return any(row.get('phase') == phase for row in fixture_rows(ctx))


def state_file():
    try:
        return json.loads(Path(RUNTIME, 'fcitx-input-state.json').read_text())
    except (OSError, ValueError):
        return None


def toast_count(ctx):
    return sum(1 for line in journal(ctx).splitlines() if TOAST_MARK in line)


def detach_fcitx5(ctx):
    """Profile D: the shell attached to the activated fcitx5; stop it, then wait for the shell to notice."""
    ok, took = wait_for(lambda: (shell_state(ctx) or {}).get('available') is True, 30)
    ctx.trace(f'shell attached to fcitx5: {ok} after {took} s')
    if not ok:
        raise SetupError('the shell never saw an activated fcitx5 (D needs one to stop)')
    for unit in activated_fcitx5_units():
        sh(['systemctl', '--user', 'stop', unit], timeout=60)
    ok, took = wait_for(lambda: not fcitx5_running(), 20)
    ctx.trace(f'fcitx5 stopped: {ok} after {took} s')
    if not ok:
        raise SetupError('the activated fcitx5 did not stop')
    ok, took = wait_for(lambda: (shell_state(ctx) or {}).get('available') is False, 10)
    ctx.trace(f'shell saw fcitx5 gone: {ok} after {took} s')


def new_record(cid, title, profile):
    return {'case': cid, 'profile': profile, 'title': title, 'checks': {}, 'observed': {}, 'notes': []}


def reset_baseline(ctx, rec, group=GROUP_RU, im='keyboard-us'):
    """group / im, set through gdbus, and the shell caught up with it (default: US+RU / keyboard-us)."""
    gdbus(ctx, 'SwitchInputMethodGroup', group)
    gdbus(ctx, 'SetCurrentIM', im)
    ok, took = wait_for(lambda: truth_is(ctx, group, im), 5)
    rec['checks']['baseline_fcitx5'] = ok
    ok, took = wait_for(lambda: shell_matches(ctx, group, im), 3)
    rec['checks']['baseline_shell'] = ok
    rec['observed']['baseline_shell_s'] = took


def check_state_fields(rec, state, lang, active=True):
    rec['checks']['state_lang'] = bool(state) and state.get('lang') == lang
    rec['checks']['state_active'] = bool(state) and state.get('active') is active
    rec['observed']['state_final'] = state


def case1(ctx):
    rec = new_record('1', 'setIM mozc from US+RU/keyboard-us', 'B')
    reset_baseline(ctx, rec)
    rc, out = ipc(ctx, 'setIM', 'mozc')
    rec['observed']['setIM'] = out
    rec['checks']['setIM_ok'] = rc == 0 and out == 'ok'
    ok, took = wait_for(lambda: truth_is(ctx, GROUP_JP, 'mozc'), 3)
    rec['checks']['fcitx5_US+JP_mozc'] = ok
    rec['observed']['fcitx5_s'] = took
    ok, took = wait_for(lambda: shell_matches(ctx, GROUP_JP, 'mozc'), 1.0)
    rec['checks']['state_follows_1s'] = ok
    rec['observed']['state_s'] = took
    check_state_fields(rec, shell_state(ctx), 'ja')
    rec['observed']['truth'] = truth(ctx)
    return rec


def case2(ctx):
    rec = new_record('2', 'SetCurrentIM keyboard-ru-mac outside the shell is followed by state', 'B')
    reset_baseline(ctx, rec)
    gdbus(ctx, 'SetCurrentIM', 'keyboard-ru-mac')
    ok, took = wait_for(lambda: shell_matches(ctx, GROUP_RU, 'keyboard-ru-mac'), 1.0)
    rec['checks']['state_follows_1s'] = ok
    rec['observed']['state_s'] = took
    check_state_fields(rec, shell_state(ctx), 'ru')
    rec['observed']['truth'] = truth(ctx)
    return rec


def case3(ctx):
    rec = new_record('3', 'setIM keyboard-fr is refused, fcitx5 unchanged, refusal logged', 'B')
    reset_baseline(ctx, rec)
    before = truth(ctx)
    rc, out = ipc(ctx, 'setIM', 'keyboard-fr')
    rec['observed']['setIM'] = out
    rec['checks']['refused'] = rc == 0 and out in ('error: unknown input method keyboard-fr',
                                                   'error: keyboard-fr is in no group')
    time.sleep(1.0)
    rec['checks']['fcitx5_unchanged'] = truth(ctx) == before and truth_is(ctx, GROUP_RU, 'keyboard-us')
    rec['checks']['state_unchanged'] = shell_matches(ctx, GROUP_RU, 'keyboard-us')
    # Logger shortens the module name to 14 characters ("InputMethodSer").
    logged, took = wait_for(lambda: any('InputMethodSer' in line and 'switchTo keyboard-fr' in line
                                        for line in journal(ctx).splitlines()), 5, 0.5)
    rec['checks']['logger_line'] = logged
    rec['observed']['logger_s'] = took
    return rec


def case4(ctx):
    rec = new_record('4', 'without fcitx5: setIM is unavailable, state still answers', 'D')
    rec['checks']['fcitx5_not_running'] = not fcitx5_running()
    rc, out = ipc(ctx, 'setIM', 'mozc')
    rec['observed']['setIM'] = out
    rec['checks']['setIM_unavailable'] = rc == 0 and out == 'error: unavailable'
    rc, out = ipc(ctx, 'state')
    rec['observed']['state'] = out
    state = None
    try:
        state = json.loads(out) if rc == 0 else None
    except ValueError:
        pass
    rec['checks']['state_reports_unavailable'] = bool(state) and state.get('available') is False
    rec['checks']['shell_alive'] = sh(['systemctl', '--user', 'is-active', '--quiet', ctx.shell_unit]).returncode == 0
    return rec


def toggle_twice(ctx, rec, name, group, away_group, away_im, prefix):
    """toggleIM name twice from away_group/away_im: in, then back to where it was."""
    rc, out = ipc(ctx, 'toggleIM', name, group)
    rec['observed'][f'{prefix}_toggle_in'] = out
    ok, took = wait_for(lambda: truth_is(ctx, group, name), 3)
    rec['checks'][f'{prefix}_in_fcitx5'] = ok and rc == 0 and out == 'ok'
    rec['observed'][f'{prefix}_in_fcitx5_s'] = took
    ok, took = wait_for(lambda: shell_matches(ctx, group, name), 1.0)
    rec['checks'][f'{prefix}_in_state_follows_1s'] = ok
    rc, out = ipc(ctx, 'toggleIM', name, group)
    rec['observed'][f'{prefix}_toggle_back'] = out
    ok, took = wait_for(lambda: truth_is(ctx, away_group, away_im), 3)
    rec['checks'][f'{prefix}_back_fcitx5'] = ok and rc == 0 and out == 'ok'
    rec['observed'][f'{prefix}_back_fcitx5_s'] = took
    ok, took = wait_for(lambda: shell_matches(ctx, away_group, away_im), 1.0)
    rec['checks'][f'{prefix}_back_state_follows_1s'] = ok


def case5(ctx):
    rec = new_record('5', 'toggleIM mozc twice from US+RU/keyboard-us returns to US+RU/keyboard-us', 'B')
    reset_baseline(ctx, rec)
    toggle_twice(ctx, rec, 'mozc', GROUP_JP, GROUP_RU, 'keyboard-us', 'mozc')
    rec['observed']['truth'] = truth(ctx)
    return rec


def case6(ctx):
    rec = new_record('6', 'toggleIM keyboard-ru-mac twice from US+RU/keyboard-us returns to US+RU/keyboard-us', 'B')
    reset_baseline(ctx, rec)
    toggle_twice(ctx, rec, 'keyboard-ru-mac', GROUP_RU, GROUP_RU, 'keyboard-us', 'ru-mac')
    rec['observed']['truth'] = truth(ctx)
    return rec


def case7(ctx):
    rec = new_record('7', 'next three times from keyboard-us cycles us -> de -> ru -> us', 'A')
    reset_baseline(ctx, rec, GROUP_DEFAULT, 'keyboard-us')
    for i, expect in enumerate(['keyboard-de', 'keyboard-ru', 'keyboard-us'], start=1):
        rc, out = ipc(ctx, 'next')
        rec['observed'][f'next_{i}'] = out
        ok, took = wait_for(lambda: truth_is(ctx, GROUP_DEFAULT, expect), 3)
        rec['checks'][f'next_{i}_is_{expect}'] = ok and rc == 0 and out == 'ok'
        rec['observed'][f'next_{i}_fcitx5_s'] = took
        ok, took = wait_for(lambda: shell_matches(ctx, GROUP_DEFAULT, expect), 1.0)
        rec['checks'][f'next_{i}_state_follows_1s'] = ok
    rec['observed']['truth'] = truth(ctx)
    return rec


def case8(ctx):
    rec = new_record('8', 'outside switch via gdbus: state file within 1 s, one layout toast line', 'B')
    reset_baseline(ctx, rec)
    time.sleep(2.5)  # let any toast from the baseline switch finish
    before = toast_count(ctx)
    gdbus(ctx, 'SetCurrentIM', 'keyboard-ru-mac')
    ok, took = wait_for(lambda: (state_file() or {}).get('im') == 'keyboard-ru-mac'
                        and (state_file() or {}).get('group') == GROUP_RU, 1.0)
    rec['checks']['state_file_1s'] = ok
    rec['observed']['state_file_s'] = took
    rec['observed']['state_file'] = state_file()
    time.sleep(2.0)  # the toast window
    toasts = toast_count(ctx) - before
    rec['observed']['toast_lines'] = toasts
    rec['checks']['toast_once'] = toasts == 1
    rec['observed']['truth'] = truth(ctx)
    return rec


def case9(ctx):
    rec = new_record('9', 'enterSecureMode, group and IM changed while locked, exitSecureMode restores both', 'B')
    stop_shell(ctx)  # the fixture must be the only shell-side service instance
    gdbus(ctx, 'SwitchInputMethodGroup', GROUP_JP)
    gdbus(ctx, 'SetCurrentIM', 'mozc')
    ok, took = wait_for(lambda: truth_is(ctx, GROUP_JP, 'mozc'), 5)
    rec['checks']['pre_state_set'] = ok
    before = truth(ctx)
    rec['observed']['before'] = before
    systemd_run(ctx, ctx.fixture_unit, ['/usr/bin/qs', '-p', str(ctx.work / 'shell' / FIXTURE_NAME)], qs_env(ctx))
    ok, took = wait_for(lambda: has_fixture_row(ctx, 'entered'), 45, 0.5)
    rec['checks']['fixture_entered'] = ok
    entered = next((r for r in fixture_rows(ctx) if r.get('phase') == 'entered'), {})
    rec['checks']['entered_locked_inactive'] = entered.get('secureModeActive') is True and entered.get('active') is False
    rec['observed']['entered'] = entered
    # While locked: the exit has not run yet (it comes ~6 s after 'entered').
    rec['checks']['change_before_exit'] = not has_fixture_row(ctx, 'exited')
    gdbus(ctx, 'SwitchInputMethodGroup', GROUP_RU)
    gdbus(ctx, 'SetCurrentIM', 'keyboard-us')
    ok, took = wait_for(lambda: truth_is(ctx, GROUP_RU, 'keyboard-us'), 3)
    rec['checks']['lock_change_applied'] = ok
    rec['observed']['during_lock'] = truth(ctx)
    ok, took = wait_for(lambda: has_fixture_row(ctx, 'exited'), 45, 0.5)
    rec['checks']['fixture_exited'] = ok
    ok, took = wait_for(lambda: truth_is(ctx, GROUP_JP, 'mozc'), 5)
    rec['checks']['restored_group_and_im'] = ok
    after = truth(ctx)
    rec['observed']['after'] = after
    rec['checks']['restored_state'] = after['state'] == before['state']
    errors = [line for line in journal_of(ctx, ctx.fixture_unit).splitlines()
              if 'TypeError' in line or 'ReferenceError' in line or 'non-existent' in line]
    rec['checks']['fixture_no_errors'] = not errors
    rec['observed']['fixture_rows'] = fixture_rows(ctx)
    sh(['systemctl', '--user', 'stop', ctx.fixture_unit], timeout=60)
    return rec


def niri_input_lines():
    try:
        return (NIRI_DIR / NIRI_INPUT).read_text(encoding='utf-8').splitlines()
    except OSError:
        return []


def stripped(lines):
    return [line.strip() for line in lines]


def bind_lines(lines, combo):
    return [line for line in stripped(lines) if line.startswith(combo + ' ')]


def write_im_section(ctx, switches, next_keys=(), legacy=True):
    """The inputMethod section file of the test profile; the shell reloads it on change."""
    path = ctx.profile_dir / 'config' / 'settings' / 'inputMethod.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(json.dumps({'switches': switches, 'nextKeys': list(next_keys), 'launchFcitx5': True,
                               'legacyI18nChecked': legacy}))
    os.replace(tmp, path)


def niri_validate(path):
    r = sh(['niri', 'validate', '-c', str(path)], timeout=60)
    return r.returncode, (r.stdout + r.stderr).strip()


def journal_line_after(ctx, needle, after_us, seconds=3.0):
    """Realtime journal timestamp (µs) of the first line of this shell containing needle after after_us, or None."""
    deadline = time.monotonic() + seconds
    while True:
        out = sh(['journalctl', '--user', '-u', ctx.shell_unit, '--no-pager', '-o', 'json'], timeout=120).stdout
        for line in out.splitlines():
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            message = entry.get('MESSAGE')
            # journalctl -o json writes MESSAGE as a byte list when the line holds control characters (ANSI colours).
            if isinstance(message, list):
                message = bytes(message).decode('utf-8', 'replace')
            if isinstance(message, str) and needle in message:
                ts = int(entry.get('__REALTIME_TIMESTAMP', 0))
                if ts > after_us:
                    return ts
        if time.monotonic() >= deadline:
            return None
        time.sleep(0.1)


def settings_applied_us(ctx, after_us, seconds=3.0):
    """Realtime journal timestamp (µs) of the first 'settings changed; regenerating' line after after_us, or None."""
    return journal_line_after(ctx, 'settings changed; regenerating', after_us, seconds)


def restart_shell(ctx, tag):
    """A new shell unit for the next case; the stopped unit's journal is kept beside the output."""
    stop_shell(ctx)
    (ctx.output / f'{ctx.shell_unit}-journal.txt').write_text(journal(ctx))
    ctx.shell_unit = f'imreg-{ctx.name}-shell-{tag}'
    start_shell(ctx)


class NiriEvents:
    """`niri msg --json event-stream`, read in the background with a receive time per event."""

    def __init__(self):
        sock = glob.glob(f'{RUNTIME}/niri.*.sock')[0]
        self.proc = subprocess.Popen(['niri', 'msg', '--json', 'event-stream'], stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True,
                                     env=dict(os.environ, NIRI_SOCKET=sock))
        self.events = []
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        for line in self.proc.stdout:
            try:
                event = json.loads(line)
            except ValueError:
                continue
            self.events.append((time.monotonic(), event))

    def config_loaded(self, lo, hi):
        """ConfigLoaded events received within [lo, hi] as (time, failed) pairs."""
        out = []
        for t, event in list(self.events):
            if lo <= t <= hi and 'ConfigLoaded' in event:
                out.append((t, bool(event['ConfigLoaded'].get('failed'))))
        return out

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()


def case10(ctx):
    return case10_niri(ctx) if COMP == 'niri' else case10_wm(ctx)


def wm_route(ctx):
    """'lua' when Hyprland runs its Lua config (hyprland.lua present), else the compositor's own syntax."""
    if COMP == 'hyprland' and (WM_DIRS[COMP] / 'hyprland.lua').exists():
        return 'lua'
    return 'hyprlang' if COMP == 'hyprland' else 'conf'


def wm_input_path(route):
    return WM_DIRS[COMP] / (WM_INPUT_LUA if route == 'lua' else WM_INPUT)


def wm_bind(route, combo, title, mode):
    """The bind line the generator writes for one combo, as the syntax of the running compositor spells it."""
    parts = combo.split('+')
    key, mods = parts[-1], [m.upper() for m in parts[:-1]]
    spawn = 'atmosphera ipc inputmethod ' + ('setIM' if mode == 'set' else 'toggleIM') + ' mozc'
    if COMP == 'hyprland' and route == 'lua':
        return ('hl.bind("' + ' + '.join(mods + [key]) + '", hl.dsp.exec_cmd("' + spawn + '"), '
                '{ locked = true, repeating = false, description = "' + title + '" })')
    if COMP == 'hyprland':
        return 'bindld = ' + ' '.join(mods) + ', ' + key + ', ' + title + ', exec, ' + spawn
    return 'bindl=' + '+'.join(mods) + ',' + key + ',spawn,' + spawn


# The two combos case 10 switches between, per compositor. mangowc's default config binds Alt+space
# to rofi (the user's own bind, not an Atmosphera-owned file), so mangowc uses other keys.
WM_COMBOS = {'hyprland': ('Alt+Space', 'Ctrl+Alt+Space'), 'mango': ('Super+Alt+J', 'Ctrl+Alt+J')}
HYPR_MODMASK = {'SHIFT': 1, 'CTRL': 4, 'ALT': 8, 'SUPER': 64}
SWITCH_TITLE = 'Input method: Japanese'
SWITCH_SPAWN = 'atmosphera ipc inputmethod toggleIM mozc'


def hypr_binds():
    """`hyprctl binds -j` as a list, or None when it does not parse."""
    r = sh(['hyprctl', 'binds', '-j'], timeout=30)
    try:
        return json.loads(r.stdout)
    except ValueError:
        return None


def hypr_bind_loaded(binds, combo, lua):
    """True when Hyprland has the switch bind for combo: locked, not repeating, titled, and running the IPC call.
    On the Lua route the command is a Lua callback (dispatcher __lua) whose text binds does not show: the
    generated file's exact line is checked instead."""
    parts = combo.split('+')
    key, mask = parts[-1], sum(HYPR_MODMASK[m.upper()] for m in parts[:-1])
    return any(b.get('key') == key and b.get('modmask') == mask and b.get('locked') is True
               and b.get('repeat') is False and b.get('description') == SWITCH_TITLE
               and (b.get('dispatcher') == '__lua' if lua else b.get('arg') == SWITCH_SPAWN)
               for b in (binds or []))


def wait_shell_settled(ctx, quiet=1.5, cap=20.0):
    """Waits until this shell has logged nothing for `quiet` seconds (its startup work is done), at most `cap`.
    A change made during startup would be timed against the startup work on the shell's main thread.
    Returns the seconds waited, or None when the cap passed first."""
    start = time.monotonic()
    while time.monotonic() - start < cap:
        out = sh(['journalctl', '--user', '-u', ctx.shell_unit, '--no-pager', '-o', 'json'], timeout=120).stdout
        last = 0
        for line in out.splitlines():
            try:
                last = max(last, int(json.loads(line).get('__REALTIME_TIMESTAMP', 0)))
            except ValueError:
                continue
        if last and time.time_ns() // 1000 - last >= quiet * 1_000_000:
            return round(time.monotonic() - start, 2)
        time.sleep(0.25)
    return None


def wm_lines(path):
    try:
        return path.read_text(encoding='utf-8').splitlines()
    except OSError:
        return []


def wm_config_check(ctx):
    """(ok, text): the compositor's own config check. Hyprland: configerrors (text empty = none).
    mangowc: mango -p. Its exit status is 1 for an error in the file given, but 0 for one in a sourced
    file (the error is printed as "[ERROR]"), so the output decides too."""
    if COMP == 'hyprland':
        r = sh(['hyprctl', 'configerrors'], timeout=30)
        return r.returncode == 0 and not r.stdout.strip(), r.stdout.strip()
    r = sh(['mango', '-c', str(WM_DIRS[COMP] / 'config.conf'), '-p'], timeout=60)
    text = re.sub(r'\x1b\[[0-9;]*m', '', r.stdout + r.stderr).strip()
    return r.returncode == 0 and 'ERROR' not in text, text


def wm_reload_ok(route, before, after):
    """Hyprland: no error after the reload that was not there before (and none naming the generated file);
    the Lua route is strict. mangowc: the config still validates (checked by the caller)."""
    if COMP != 'hyprland':
        return True
    if route == 'lua':
        return after.strip() == ''
    known = set(before.splitlines())
    fresh = [line for line in after.splitlines() if line.strip() and line not in known]
    return not fresh and WM_INPUT not in after


def case10_wm(ctx):
    route = wm_route(ctx)
    label = COMP if COMP != 'hyprland' else f'hyprland-{route}'
    rec = new_record('10', f'{label}: fresh profile: input file generated with the bind; combo change rewritten within 1 s of being applied and reloaded, no new config error', 'B')
    cfg = WM_DIRS[COMP]
    inp = wm_input_path(route)
    # The state setup leaves: the file exists and is empty (the layer sources it, so it must not be missing).
    inp.write_text('', encoding='utf-8')
    rec['checks']['input_emptied'] = inp.stat().st_size == 0
    if COMP == 'hyprland' and route == 'lua':
        wiring = wm_lines(cfg / 'atmosphera.lua')
        rec['checks']['wired'] = any(line.strip() == 'require("atmosphera-input")' for line in wiring)
    elif COMP == 'hyprland':
        wiring = wm_lines(cfg / 'atmosphera.conf')
        rec['checks']['wired'] = any(line.strip() == 'source = ~/.config/hypr/atmosphera-input.conf' for line in wiring)
    else:
        wiring = wm_lines(cfg / 'atmosphera.conf')
        rec['checks']['wired'] = 'source=./atmosphera-input.conf' in [line.strip() for line in wiring]
    rec['observed']['wiring'] = [line for line in wiring if 'atmosphera-input' in line]
    _, before_text = wm_config_check(ctx)
    rec['observed']['config_check_before'] = before_text
    combo_a, combo_b = WM_COMBOS[COMP]
    write_im_section(ctx, [dict(SWITCH_JA, keys=[combo_a])])
    restart_shell(ctx, '10')
    expected = wm_bind(route, combo_a, SWITCH_TITLE, 'toggle')
    ok, took = wait_for(lambda: expected in [line.strip() for line in wm_lines(inp)], 30, 0.2)
    rec['checks']['input_file_written'] = ok
    rec['observed']['input_file_written_s'] = took
    rec['observed']['settled_before_change_s'] = wait_shell_settled(ctx)
    lines = wm_lines(inp)
    rec['observed']['input_file_10'] = lines
    rec['checks']['input_bind_exact'] = expected in [line.strip() for line in lines]
    rec['checks']['input_fcitx5'] = any('fcitx5' in line for line in lines)
    rec['checks']['input_header'] = bool(lines) and 'Generated by Atmosphera' in lines[0]
    rec['checks']['i18n_not_recreated'] = not (cfg / 'atmosphera-i18n.kdl').exists()
    _, after_start_text = wm_config_check(ctx)
    rec['observed']['config_check_after_first_start'] = after_start_text
    write_us = time.time_ns() // 1000
    write_im_section(ctx, [dict(SWITCH_JA, keys=[combo_b])])
    new_expected = wm_bind(route, combo_b, SWITCH_TITLE, 'toggle')
    ok, took = wait_for(lambda: new_expected in [line.strip() for line in wm_lines(inp)], 5.0, 0.02)
    file_us = time.time_ns() // 1000
    applied_us = settings_applied_us(ctx, write_us)
    rec['checks']['settings_applied_logged'] = applied_us is not None
    rec['observed']['write_to_file_s'] = round((file_us - write_us) / 1e6, 3) if ok else None
    if applied_us is not None:
        rec['observed']['write_to_applied_s'] = round((applied_us - write_us) / 1e6, 3)
        rec['observed']['applied_to_file_s'] = round((file_us - applied_us) / 1e6, 3)
    rec['checks']['combo_file_within_1s'] = ok and applied_us is not None and (file_us - applied_us) <= 1_000_000
    lines = wm_lines(inp)
    rec['observed']['input_file_10_changed'] = lines
    rec['checks']['old_combo_gone'] = expected not in [line.strip() for line in lines]
    rec['checks']['new_bind_exact'] = new_expected in [line.strip() for line in lines]
    # The reload follows this change's write, which follows the applied line: the applied line is the lower bound.
    reloaded = journal_line_after(ctx, f'reloaded {"mangowc" if COMP == "mango" else "Hyprland"} config',
                                  applied_us if applied_us is not None else write_us, 3.0)
    rec['checks']['reload_logged_after_change'] = reloaded is not None
    rec['observed']['reload_logged_after_applied_s'] = round((reloaded - applied_us) / 1e6, 3) if reloaded and applied_us else None
    after_ok, after_text = wm_config_check(ctx)
    rec['observed']['config_check_after_change'] = after_text
    if COMP == 'hyprland':
        rec['checks']['no_new_config_error_after_reload'] = wm_reload_ok(route, before_text, after_text)
        # Hyprland's own bind table: the reload loaded the new combo and dropped the old one.
        lua = route == 'lua'
        loaded, took = wait_for(lambda: hypr_bind_loaded(hypr_binds(), combo_b, lua), 3.0, 0.1)
        rec['checks']['reload_loaded_new_bind'] = loaded
        rec['observed']['reload_loaded_new_bind_s'] = took
        rec['checks']['reload_dropped_old_bind'] = not hypr_bind_loaded(hypr_binds(), combo_a, lua)
        rec['observed']['hypr_binds_after_change'] = hypr_binds()
    else:
        rec['checks']['mango_config_valid_after_reload'] = after_ok
    (ctx.output / 'config-check.txt').write_text(json.dumps({'before': before_text, 'after': after_text}, indent=2) + '\n')
    stop_shell(ctx)
    (ctx.output / 'shell-10-journal.txt').write_text(journal(ctx))
    return rec


def case10_niri(ctx):
    rec = new_record('10', 'fresh profile: input file generated, no i18n recreated, combo change shows in the file within 1 s of being applied', 'B')
    i18n = NIRI_DIR / NIRI_I18N
    aside = ctx.work / 'niri-aside'
    aside.mkdir(exist_ok=True)
    if i18n.exists():
        shutil.move(str(i18n), str(aside / NIRI_I18N))
    rec['checks']['i18n_set_aside'] = not i18n.exists()
    write_im_section(ctx, [dict(SWITCH_JA)])
    restart_shell(ctx, '10')
    ok, took = wait_for(lambda: bind_lines(niri_input_lines(), 'Alt+Space'), 30, 0.2)
    rec['checks']['input_file_written'] = ok
    rec['observed']['input_file_written_s'] = took
    # The session is regenerated by the startup chain (BindingsService, keyd, xremap, then NiriSessionInit),
    # after the input file: wait for it, and for the shell to settle, before the checks and the change.
    _, took = wait_for(lambda: 'atmosphera-i18n.kdl' not in session_text() and 'include "atmosphera-input.kdl"' in session_text(), 30, 0.2)
    rec['observed']['session_regenerated_s'] = took
    rec['observed']['settled_before_change_s'] = wait_shell_settled(ctx)
    lines = niri_input_lines()
    rec['observed']['input_file_10'] = lines
    rec['checks']['i18n_not_recreated'] = not i18n.exists()
    session = session_text()
    rec['checks']['session_includes_input'] = 'include "atmosphera-input.kdl"' in session
    rec['checks']['session_no_i18n'] = 'atmosphera-i18n.kdl' not in session
    rec['checks']['input_header'] = bool(lines) and lines[0].startswith('// Generated by Atmosphera')
    rec['checks']['input_fcitx5_spawn'] = 'spawn-at-startup "fcitx5"' in stripped(lines)
    rec['checks']['input_bind_exact'] = BIND_JA in stripped(lines)
    rc, out = niri_validate(NIRI_DIR / NIRI_SESSION)
    rec['checks']['niri_validate_before_change'] = rc == 0
    rec['observed']['niri_validate_before_change'] = out
    events = NiriEvents()
    try:
        write_us = time.time_ns() // 1000
        t_write = time.monotonic()
        write_im_section(ctx, [dict(SWITCH_JA, keys=['Ctrl+Alt+Space'])])
        ok, took = wait_for(lambda: bind_lines(niri_input_lines(), 'Ctrl+Alt+Space'), 5.0, 0.02)
        t_seen = time.monotonic()
        file_us = time.time_ns() // 1000
        # The limit runs from the shell applying the settings change (its journal line), not from the write.
        applied_us = settings_applied_us(ctx, write_us)
        rec['checks']['settings_applied_logged'] = applied_us is not None
        rec['observed']['write_to_file_s'] = round((file_us - write_us) / 1e6, 3) if ok else None
        if applied_us is not None:
            rec['observed']['write_to_applied_s'] = round((applied_us - write_us) / 1e6, 3)
            rec['observed']['applied_to_file_s'] = round((file_us - applied_us) / 1e6, 3)
        rec['checks']['combo_file_within_1s'] = (ok and applied_us is not None
                                                 and (file_us - applied_us) <= 1_000_000)
        lines = niri_input_lines()
        rec['checks']['old_combo_gone'] = not bind_lines(lines, 'Alt+Space')
        rec['checks']['new_bind_exact'] = BIND_CTRL_ALT_JA in stripped(lines)
        ok, took = wait_for(lambda: any(not failed for _, failed in events.config_loaded(t_write, t_seen + 2.0)),
                            2.0, 0.05)
        loaded = events.config_loaded(t_write, t_seen + 2.0)
        rec['checks']['niri_reloaded_ok_within_2s'] = ok
        rec['observed']['niri_config_loaded_after_change'] = [
            {'after_write_s': round(t - t_write, 3), 'failed': failed} for t, failed in loaded]
    finally:
        events.close()
    rc, out = niri_validate(NIRI_DIR / NIRI_SESSION)
    rec['checks']['niri_validate_after_change'] = rc == 0
    rec['observed']['niri_validate_after_change'] = out
    stop_shell(ctx)
    (ctx.output / 'shell-10-journal.txt').write_text(journal(ctx))
    return rec


def case11(ctx):
    rec = new_record('11', 'shipped i18n present: Alt+Space switch skipped and logged, Super+Alt+J generated', 'B')
    i18n = NIRI_DIR / NIRI_I18N
    aside = ctx.work / 'niri-aside' / NIRI_I18N
    if aside.exists() and not i18n.exists():
        shutil.move(str(aside), str(i18n))
    rec['checks']['i18n_restored'] = i18n.exists() and i18n.read_bytes() == (ctx.work / 'niri-backup' / NIRI_I18N).read_bytes()
    write_im_section(ctx, [dict(SWITCH_JA),
                           {'keys': ['Super+Alt+J'], 'target': 'mozc', 'mode': 'set', 'label': ''}])
    restart_shell(ctx, '11')
    ok, took = wait_for(lambda: bind_lines(niri_input_lines(), 'Super+Alt+J'), 30, 0.2)
    lines = niri_input_lines()
    rec['observed']['input_file_11'] = lines
    rec['checks']['super_alt_j_generated_setIM'] = ok and any('"setIM" "mozc"' in line
                                                             for line in bind_lines(lines, 'Super+Alt+J'))
    rec['checks']['alt_space_not_generated'] = not bind_lines(lines, 'Alt+Space')
    # No label: the title falls back to the IM's name from fcitx5 (Mozc), which the shell learns after the first generation.
    named, took = wait_for(lambda: any('"Input method: Mozc"' in line for line in bind_lines(niri_input_lines(), 'Super+Alt+J')), 5, 0.2)
    rec['checks']['fallback_title_is_im_name'] = named
    rec['observed']['fallback_title_s'] = took
    session = (NIRI_DIR / NIRI_SESSION).read_text(encoding='utf-8') if (NIRI_DIR / NIRI_SESSION).exists() else ''
    rec['checks']['session_includes_i18n'] = 'include "atmosphera-i18n.kdl"' in session
    logged, took = wait_for(lambda: any('Alt+Space' in line and NIRI_I18N in line
                                        for line in journal(ctx).splitlines()), 10, 0.5)
    rec['checks']['skip_logged_naming_both'] = logged
    rec['observed']['skip_logged_s'] = took
    rc, out = niri_validate(NIRI_DIR / NIRI_SESSION)
    rec['checks']['niri_validate'] = rc == 0
    rec['observed']['niri_validate'] = out
    stop_shell(ctx)
    (ctx.output / 'shell-11-journal.txt').write_text(journal(ctx))
    return rec


def case12(ctx):
    rec = new_record('12', 'setIM mozc as soon as fcitx5 is available on three shell starts', 'B')
    attempts = []
    for attempt in range(1, 4):
        stop_shell(ctx)
        (ctx.output / f'{ctx.shell_unit}-journal.txt').write_text(journal(ctx))
        gdbus(ctx, 'SwitchInputMethodGroup', GROUP_RU)
        gdbus(ctx, 'SetCurrentIM', 'keyboard-us')
        baseline, _ = wait_for(lambda: truth_is(ctx, GROUP_RU, 'keyboard-us'), 3)
        ctx.shell_unit = f'imreg-{ctx.name}-shell-12-{attempt}'
        systemd_run(ctx, ctx.shell_unit, ['/usr/bin/qs', '-p', str(ctx.shell_qml)], qs_env(ctx))
        # Do not use start_shell's slower IPC-discovery poll or query truth here:
        # issue the request immediately on the first available state response.
        available, startup_s = wait_for(lambda: (shell_state(ctx) or {}).get('available') is True, 90, 0.02)
        t_available = time.monotonic()
        t_call = time.monotonic()
        rc, out = ipc(ctx, 'setIM', 'mozc')
        delay_s = t_call - t_available
        ctx.trace(f'case 12 attempt {attempt}: setIM sent {delay_s:.6f} s after available')
        reached, truth_s = wait_for(lambda: truth_is(ctx, GROUP_JP, 'mozc'), 3)
        followed, state_s = wait_for(lambda: shell_matches(ctx, GROUP_JP, 'mozc'), 1.0)
        checks = {'baseline_fcitx5': baseline, 'available': available, 'setIM_ok': rc == 0 and out == 'ok',
                  'fcitx5_US+JP_mozc_3s': reached, 'state_follows_1s': followed}
        for name, passed in checks.items():
            rec['checks'][f'attempt_{attempt}_{name}'] = passed
        attempts.append({'attempt': attempt, 'available_after_start_s': startup_s,
                         'call_after_available_s': delay_s, 'setIM': out, 'setIM_rc': rc,
                         'fcitx5_s': truth_s, 'state_s': state_s, 'checks': checks,
                         'truth': truth(ctx), 'state_final': shell_state(ctx)})
        ctx.trace(f'case 12 attempt {attempt}: {"PASS" if all(checks.values()) else "FAIL"} {checks}')
    rec['observed']['attempts'] = attempts
    return rec


SHIPPED_SWITCHES = [
    {'keys': ['Alt+Space'], 'target': 'mozc', 'mode': 'toggle', 'label': 'Japanese (mozc)'},
    {'keys': ['Ctrl+Space'], 'target': 'keyboard-ru-mac', 'mode': 'toggle', 'label': 'Russian'},
]
BIND_SHIPPED_JA = ('Alt+Space repeat=false allow-when-locked=true hotkey-overlay-title="Input method: Japanese (mozc)" '
                   '{ spawn "atmosphera" "ipc" "inputmethod" "toggleIM" "mozc"; }')
BIND_SHIPPED_RU = ('Ctrl+Space repeat=false allow-when-locked=true hotkey-overlay-title="Input method: Russian" '
                   '{ spawn "atmosphera" "ipc" "inputmethod" "toggleIM" "keyboard-ru-mac"; }')
BIND_EDITED_RU = ('Super+Space repeat=false allow-when-locked=true hotkey-overlay-title="Input method: Russian" '
                  '{ spawn "atmosphera" "ipc" "inputmethod" "toggleIM" "keyboard-ru-mac"; }')
# One convertible bind on Super+Space: the file differs from the shipped one.
EDITED_I18N = ('// Hand-edited legacy file\n'
               'spawn-at-startup "fcitx5"\n\n'
               'binds {\n'
               '    Super+Space  allow-when-locked=true hotkey-overlay-title="Input method: Russian" {\n'
               '        spawn "atmosphera" "ipc" "inputmethod" "toggleIM" "keyboard-ru-mac" "US+RU";\n'
               '    }\n'
               '}\n').encode('utf-8')
UNPARSEABLE_I18N = ('// Hand-edited legacy file without an input-method bind\n'
                    'binds {\n'
                    '    Super+Space { spawn "foo" "bar"; }\n'
                    '}\n').encode('utf-8')
CONFLICT_SWITCH = {'keys': ['Super+Space'], 'target': 'mozc', 'mode': 'toggle', 'label': ''}
RUSSIAN_SWITCH = {'keys': ['Super+Space'], 'target': 'keyboard-ru-mac', 'mode': 'toggle', 'label': 'Russian'}


def sha256_of(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def section_json(ctx):
    try:
        return json.loads((ctx.profile_dir / 'config' / 'settings' / 'inputMethod.json').read_text())
    except (OSError, ValueError):
        return None


def backup_dir(ctx):
    return ctx.profile_dir / 'config' / 'backups'


def backup_names(ctx):
    return sorted(p.name for p in backup_dir(ctx).iterdir()) if backup_dir(ctx).is_dir() else []


def i18n_bytes():
    p = NIRI_DIR / NIRI_I18N
    return p.read_bytes() if p.exists() else None


def session_text():
    p = NIRI_DIR / NIRI_SESSION
    return p.read_text(encoding='utf-8') if p.exists() else ''


def restore_shipped_i18n(ctx):
    shutil.copyfile(ctx.niri_backup / NIRI_I18N, NIRI_DIR / NIRI_I18N)


def write_legacy_file(content):
    tmp = NIRI_DIR / (NIRI_I18N + '.tmp')
    tmp.write_bytes(content)
    os.replace(tmp, NIRI_DIR / NIRI_I18N)


def legacy_import(ctx, tag):
    """Runs the import fixture with the shell stopped; (count, error) from its LEGACY_IMPORT row."""
    unit = f'imreg-{ctx.name}-legacy-{tag}'
    systemd_run(ctx, unit, ['/usr/bin/qs', '-p', str(ctx.work / 'shell' / LEGACY_FIXTURE_NAME)], qs_env(ctx))
    wait_for(lambda: 'LEGACY_IMPORT|' in journal_of(ctx, unit), 90, 0.5)
    wait_for(lambda: sh(['systemctl', '--user', 'is-active', '--quiet', unit]).returncode != 0, 30, 0.5)
    rows = []
    for line in journal_of(ctx, unit).splitlines():
        i = line.find('LEGACY_IMPORT|')
        if i >= 0:
            rows.append(json.loads(line[i + len('LEGACY_IMPORT|'):]))
    ctx.trace(f'legacy import {tag}: {rows}')
    return rows[0] if rows else {}


def case13(ctx):
    rec = new_record('13', 'shipped i18n file converted: two switches, backup, file removed, session without the include, no failed niri reload', 'B')
    restore_shipped_i18n(ctx)
    write_im_section(ctx, [], legacy=False)
    rec['checks']['setup_shipped_bytes'] = i18n_bytes() == (ctx.niri_backup / NIRI_I18N).read_bytes()
    before = set(backup_names(ctx))
    events = NiriEvents()
    try:
        t0 = time.monotonic()
        restart_shell(ctx, '13')
        gone, took = wait_for(lambda: not (NIRI_DIR / NIRI_I18N).exists(), 30, 0.2)
        rec['checks']['file_removed'] = gone
        rec['observed']['file_removed_s'] = took
        wait_for(lambda: bool((section_json(ctx) or {}).get('legacyI18nChecked')), 10, 0.2)
        wait_for(lambda: bind_lines(niri_input_lines(), 'Alt+Space') and bind_lines(niri_input_lines(), 'Ctrl+Space'), 10, 0.2)
        t1 = time.monotonic()
    finally:
        events.close()
    section = section_json(ctx) or {}
    rec['checks']['switches_on_disk'] = section.get('switches') == SHIPPED_SWITCHES
    rec['checks']['legacy_flag_on_disk'] = section.get('legacyI18nChecked') is True
    new = [n for n in backup_names(ctx) if n not in before]
    rec['observed']['new_backups'] = new
    rec['checks']['one_backup_identical'] = (len(new) == 1
                                             and (backup_dir(ctx) / new[0]).read_bytes() == (ctx.niri_backup / NIRI_I18N).read_bytes())
    session = session_text()
    rec['checks']['session_no_i18n'] = 'atmosphera-i18n.kdl' not in session
    rec['checks']['session_includes_input'] = 'include "atmosphera-input.kdl"' in session
    lines = niri_input_lines()
    rec['observed']['input_file_13'] = lines
    rec['checks']['input_binds_both'] = BIND_SHIPPED_JA in stripped(lines) and BIND_SHIPPED_RU in stripped(lines)
    rc, out = niri_validate(NIRI_DIR / NIRI_SESSION)
    rec['checks']['niri_validate'] = rc == 0
    rec['observed']['niri_validate'] = out
    rec['observed']['niri_config_loaded'] = [{'after_start_s': round(t - t0, 3), 'failed': failed}
                                             for t, failed in events.config_loaded(t0, t1 + 2.0)]
    rec['checks']['no_failed_niri_reload'] = not any(failed for _, failed in events.config_loaded(t0, t1 + 2.0))
    logged = [line for line in journal(ctx).splitlines() if 'legacy i18n' in line]
    rec['observed']['legacy_log'] = logged
    rec['checks']['no_notice_when_all_converted'] = not any('notice shown' in line for line in logged)
    return rec


def case16(ctx):
    rec = new_record('16', 'second start after the conversion: settings, files, backups and binds unchanged', 'B')

    def snapshot():
        data = i18n_bytes()
        return {'section': section_json(ctx), 'backups': backup_names(ctx),
                'i18n': None if data is None else hashlib.sha256(data).hexdigest(),
                'input': niri_input_lines(), 'session': session_text()}
    before = snapshot()
    rec['observed']['before'] = {k: v for k, v in before.items() if k != 'input'}
    restart_shell(ctx, '16')
    wait_for(lambda: (shell_state(ctx) or {}).get('available') is True, 90, 0.2)
    time.sleep(3.0)  # the startup checks and any regeneration
    after = snapshot()
    rec['checks']['section_unchanged'] = after['section'] == before['section']
    rec['checks']['legacy_flag_still_true'] = bool((after['section'] or {}).get('legacyI18nChecked')) is True
    rec['checks']['no_new_backup'] = after['backups'] == before['backups']
    rec['checks']['i18n_still_absent'] = after['i18n'] is None
    rec['checks']['input_unchanged'] = after['input'] == before['input']
    rec['checks']['session_unchanged'] = after['session'] == before['session']
    stop_shell(ctx)
    (ctx.output / 'shell-16-journal.txt').write_text(journal(ctx))
    return rec


def case15(ctx):
    rec = new_record('15', 'hand-edited i18n file kept untouched, conflict skipped, importLegacyI18n converts it once, bad file refused', 'B')
    write_legacy_file(EDITED_I18N)
    edited_sha = sha256_of(NIRI_DIR / NIRI_I18N)
    write_im_section(ctx, [CONFLICT_SWITCH])
    restart_shell(ctx, '15a')
    conflict, took = wait_for(lambda: any('Super+Space' in line and NIRI_I18N in line
                                          for line in journal(ctx).splitlines()), 30, 0.5)
    rec['checks']['conflict_skipped_naming_file'] = conflict
    rec['observed']['conflict_s'] = took
    rec['checks']['file_untouched'] = sha256_of(NIRI_DIR / NIRI_I18N) == edited_sha
    rec['checks']['file_still_included'] = 'include "atmosphera-i18n.kdl"' in session_text()
    rec['checks']['super_space_not_generated'] = not bind_lines(niri_input_lines(), 'Super+Space')
    rec['checks']['custom_file_kept_logged'] = any('legacy i18n file kept, not converted:' in line
                                                   for line in journal(ctx).splitlines())
    rec['checks']['flag_unchanged_true'] = bool((section_json(ctx) or {}).get('legacyI18nChecked')) is True
    stop_shell(ctx)
    (ctx.output / 'shell-15a-journal.txt').write_text(journal(ctx))
    section_before = section_json(ctx)
    backups_before = backup_names(ctx)
    # Unparseable file: refused, nothing changes.
    write_legacy_file(UNPARSEABLE_I18N)
    bad_sha = sha256_of(NIRI_DIR / NIRI_I18N)
    bad = legacy_import(ctx, 'bad')
    rec['observed']['import_unparseable'] = bad
    rec['checks']['unparseable_refused'] = bad.get('count') == 0 and bool(bad.get('error'))
    rec['checks']['unparseable_file_untouched'] = sha256_of(NIRI_DIR / NIRI_I18N) == bad_sha
    rec['checks']['unparseable_settings_untouched'] = section_json(ctx) == section_before
    rec['checks']['unparseable_no_backup'] = backup_names(ctx) == backups_before
    # Parseable: the conflict switch is removed first, so the import adds exactly one switch.
    write_im_section(ctx, [])
    write_legacy_file(EDITED_I18N)
    good = legacy_import(ctx, 'good')
    rec['observed']['import_edited'] = good
    rec['checks']['import_returns_one'] = good.get('count') == 1 and good.get('error') == ''
    section = section_json(ctx) or {}
    rec['observed']['switches_after_import'] = section.get('switches')
    rec['checks']['one_super_space_switch'] = section.get('switches') == [RUSSIAN_SWITCH]
    rec['checks']['flag_true_after_import'] = section.get('legacyI18nChecked') is True
    rec['checks']['file_removed_after_import'] = not (NIRI_DIR / NIRI_I18N).exists()
    new = [n for n in backup_names(ctx) if n not in backups_before]
    rec['checks']['one_backup_after_import'] = (len(new) == 1
                                                and (backup_dir(ctx) / new[0]).read_bytes() == EDITED_I18N)
    # The next start: the file and its include are gone, the switch is generated.
    restart_shell(ctx, '15b')
    gone, took = wait_for(lambda: bind_lines(niri_input_lines(), 'Super+Space'), 30, 0.2)
    rec['checks']['switch_generated_after_restart'] = gone and BIND_EDITED_RU in stripped(niri_input_lines())
    rec['checks']['session_no_i18n_after_restart'] = 'atmosphera-i18n.kdl' not in session_text()
    rc, out = niri_validate(NIRI_DIR / NIRI_SESSION)
    rec['checks']['niri_validate'] = rc == 0
    rec['observed']['niri_validate'] = out
    stop_shell(ctx)
    (ctx.output / 'shell-15b-journal.txt').write_text(journal(ctx))
    return rec


def tree_digest(root, skip=()):
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.iterdir())
            if p.is_file() and p.name not in skip}


def backup_niri(ctx):
    """Copy the guest's ~/.config/niri into WORK/niri-backup (files only: the directory has none else).

    Profiles A and B need the shipped atmosphera-i18n.kdl in place: they test it, and it comes back afterwards.
    """
    if not NIRI_DIR.is_dir():
        raise SetupError(f'{NIRI_DIR} does not exist in the guest')
    if ctx.profile in ('A', 'B') and (not (NIRI_DIR / NIRI_I18N).is_file()
                                     or sha256_of(NIRI_DIR / NIRI_I18N) != SHIPPED_I18N_SHA256):
        raise SetupError(f'{NIRI_DIR / NIRI_I18N} is not the shipped file; restore it before the run')
    dst = ctx.work / 'niri-backup'
    dst.mkdir()
    for p in NIRI_DIR.iterdir():
        if p.is_file():
            shutil.copy2(p, dst / p.name)
    ctx.niri_backup = dst


def restore_niri(ctx):
    """Put ~/.config/niri back as backed up; the session and input files are not restored."""
    backup = ctx.niri_backup
    before = tree_digest(backup)
    for name in before:
        if name not in NIRI_KEEP:
            shutil.copy2(backup / name, NIRI_DIR / name)
    for p in NIRI_DIR.iterdir():
        if p.is_file() and p.name not in before and p.name not in NIRI_KEEP:
            p.unlink()
    # The session includes the input file, so it must exist: header only, as the generator writes it when fcitx5 is absent.
    (NIRI_DIR / NIRI_INPUT).write_text(INPUT_HEADER, encoding='utf-8')
    expected = {k: v for k, v in before.items() if k not in NIRI_KEEP}
    actual = tree_digest(NIRI_DIR, skip=NIRI_KEEP)
    rc, out = niri_validate(NIRI_DIR / NIRI_SESSION)
    return {'identical_except_kept': actual == expected, 'files': sorted(expected),
            'final_validate_rc': rc, 'final_validate': out,
            'passed': actual == expected and rc == 0}


def backup_wm(ctx):
    """Copy the compositor's config directory into WORK/compositor-backup (files only)."""
    src = WM_DIRS[COMP]
    if not src.is_dir():
        raise SetupError(f'{src} does not exist in the guest')
    dst = ctx.work / 'compositor-backup'
    dst.mkdir()
    for p in src.iterdir():
        if p.is_file():
            shutil.copy2(p, dst / p.name)
    ctx.wm_backup = dst


def restore_wm(ctx):
    """Put the compositor's config directory back as backed up; the input files are rewritten header-only
    and the compositor reloaded, so no test bind stays loaded."""
    src = WM_DIRS[COMP]
    keep = (WM_INPUT, WM_INPUT_LUA)
    before = tree_digest(ctx.wm_backup)
    for name in before:
        if name not in keep:
            shutil.copy2(ctx.wm_backup / name, src / name)
    for p in src.iterdir():
        if p.is_file() and p.name not in before and p.name not in keep:
            p.unlink()
    marker = '-- ' if COMP == 'hyprland' and (src / 'hyprland.lua').exists() else '# '
    (src / WM_INPUT).write_text(marker + GENERATED_TEXT + '\n', encoding='utf-8')
    expected = {k: v for k, v in before.items() if k not in keep}
    actual = tree_digest(src, skip=keep)
    if COMP == 'hyprland':
        sh(['hyprctl', 'reload'], timeout=60)
    else:
        sh(['mmsg', 'dispatch', 'reload_config'], timeout=60)
    ok, text = wm_config_check(ctx)
    return {'identical_except_kept': actual == expected, 'files': sorted(expected), 'config_check_rc_ok': ok,
            'config_check': text, 'passed': actual == expected}


def case14(ctx):
    rec = new_record('14', 'shipped i18n file, no group holds mozc or keyboard-ru-mac: no switch, one notice, file retired, niri valid', 'A')
    removed, took = wait_for(lambda: not (NIRI_DIR / NIRI_I18N).exists(), 30, 0.2)
    rec['checks']['file_removed'] = removed
    rec['observed']['file_removed_s'] = took
    wait_for(lambda: bool((section_json(ctx) or {}).get('legacyI18nChecked')), 10, 0.2)
    section = section_json(ctx) or {}
    # The section file is sparse: an empty list at its default is not written.
    rec['checks']['no_switches'] = section.get('switches', []) == []
    rec['checks']['legacy_flag_on_disk'] = section.get('legacyI18nChecked') is True
    backups = backup_names(ctx)
    rec['observed']['backups'] = backups
    rec['checks']['backup_is_shipped_bytes'] = (len(backups) == 1 and (backup_dir(ctx) / backups[0]).read_bytes()
                                                == (ctx.niri_backup / NIRI_I18N).read_bytes())
    logged = [line for line in journal(ctx).splitlines() if 'legacy i18n' in line]
    rec['observed']['legacy_log'] = logged
    notices = [line for line in logged if 'notice shown' in line]
    rec['checks']['one_notice_naming_both'] = (len(notices) == 1 and 'mozc' in notices[0]
                                               and 'keyboard-ru-mac' in notices[0])
    rec['checks']['both_refusals_logged'] = sum(1 for line in logged if 'bind not converted:' in line) == 2
    rec['checks']['session_no_i18n'] = 'atmosphera-i18n.kdl' not in session_text()
    rc, out = niri_validate(NIRI_DIR / NIRI_SESSION)
    rec['checks']['niri_validate'] = rc == 0
    rec['observed']['niri_validate'] = out
    rec['checks']['shell_alive'] = sh(['systemctl', '--user', 'is-active', '--quiet', ctx.shell_unit]).returncode == 0
    return rec


# ——— Key-press cases (M29, --keys) ———
# A real key press goes keyboard -> compositor bind -> `atmosphera ipc` -> this shell -> fcitx5. The guest
# only asks for a key (keys/ready-<step>.json) and waits for the host driver's ack (keys/sent-<step>.json);
# everything it checks is read back from fcitx5, the shell, the generated file or the journal.

def keys_case(cid):
    def wrap(fn):
        fn.cid = cid
        return fn
    return wrap


def case_id(case):
    return getattr(case, 'cid', None) or case.__name__.removeprefix('case')


def key_step(ctx, step, combo, hold_ms=100):
    """Asks the host driver to press combo, then waits for its ack. (sent, info): sent is True when the driver
    reports it sent exactly this combo (the key was injected)."""
    d = ctx.output / 'keys'
    d.mkdir(exist_ok=True)
    ready = d / f'ready-{step}.json'
    tmp = ready.with_name(ready.name + '.tmp')
    tmp.write_text(json.dumps({'step': step, 'combo': combo, 'hold_ms': hold_ms}))
    os.replace(tmp, ready)
    sent_file = d / f'sent-{step}.json'
    ok, took = wait_for(sent_file.exists, KEY_DRIVER_WAIT, 0.1)
    driver = {}
    if ok:
        try:
            driver = json.loads(sent_file.read_text())
        except (OSError, ValueError):
            driver = {}
    ctx.trace(f'key {step} {combo} hold {hold_ms} ms: driver {driver} after {took} s')
    return bool(ok and driver.get('ok') is True and driver.get('combo') == combo), {'waited_s': took, 'driver': driver}


def press(ctx, rec, name, combo, hold_ms=100):
    sent, info = key_step(ctx, f'{rec["case"]}-{name}', combo, hold_ms)
    rec['checks'][f'{name}_sent'] = sent
    rec['observed'][f'{name}_sent'] = info
    return sent


def is_active(ctx):
    return sh(['systemctl', '--user', 'is-active', '--quiet', ctx.shell_unit]).returncode == 0


def generated_lines(ctx):
    return niri_input_lines() if COMP == 'niri' else wm_lines(wm_input_path(wm_route(ctx)))


def bound(ctx, combo, action):
    """True when the generated file binds combo to action (action: the words of the spawned IPC call).
    niri: the line starts with the combo. Hyprland and mangowc: the modifier set and key must match exactly."""
    parts = combo.split('+')
    key, mods = parts[-1].lower(), {p.lower() for p in parts[:-1]}
    for line in stripped(generated_lines(ctx)):
        if not line or line.startswith(('//', '#', '--')):
            continue
        if COMP == 'niri' and line.split()[:1] != [combo]:
            continue
        words = set(re.split(r'[^a-z0-9_-]+', line.lower()))
        if COMP != 'niri' and ((words & MODIFIERS) != mods or key not in words):
            continue
        if all(w in words for w in action):
            return True
    return False


def binds_in_file(ctx):
    return [line for line in stripped(generated_lines(ctx)) if line and not line.startswith(('//', '#', '--'))]


def set_switches(ctx, rec, switches, expect, next_keys=(), tag=''):
    """Writes the inputMethod section unless it already holds these switches, then waits for the generated file
    to bind every (combo, action) in expect. The shell regenerates on the change; the compositor reloads."""
    section = section_json(ctx) or {}
    if section.get('switches', []) != switches or section.get('nextKeys', []) != list(next_keys):
        write_im_section(ctx, switches, next_keys)
    ok, took = wait_for(lambda: all(bound(ctx, c, a) for c, a in expect), 30, 0.2)
    rec['checks'][f'binds_generated{tag}'] = ok
    rec['observed'][f'binds_generated{tag}_s'] = took
    if ok:
        rec['observed'][f'settled{tag}_s'] = wait_shell_settled(ctx)
        time.sleep(1.0)  # the compositor's config reload after the file change
    return ok


KEY_B_EXPECT = [('Alt+Space', ('toggleim', 'mozc')), ('Ctrl+Space', ('toggleim', 'keyboard-ru-mac'))]


def truth_then_shell(ctx, rec, label, group, im, fcitx_wait=3.0, shell_wait=1.0):
    ok, took = wait_for(lambda: truth_is(ctx, group, im), fcitx_wait)
    rec['checks'][f'{label}_fcitx5'] = ok
    rec['observed'][f'{label}_fcitx5_s'] = took
    ok, took = wait_for(lambda: shell_matches(ctx, group, im), shell_wait)
    rec['checks'][f'{label}_state_follows_1s'] = ok
    rec['observed'][f'{label}_state_s'] = took
    return ok


@keys_case('K1')
def key_k1(ctx):
    rec = new_record('K1', 'Alt+Space (real key) switches US+RU/keyboard-us to US+JP/mozc', 'B')
    set_switches(ctx, rec, SHIPPED_SWITCHES, KEY_B_EXPECT)
    reset_baseline(ctx, rec)
    press(ctx, rec, 'press', 'Alt+Space')
    truth_then_shell(ctx, rec, 'press', GROUP_JP, 'mozc')
    check_state_fields(rec, shell_state(ctx), 'ja')
    rec['observed']['truth'] = truth(ctx)
    return rec


@keys_case('K2')
def key_k2(ctx):
    rec = new_record('K2', 'Alt+Space again returns US+JP/mozc to US+RU/keyboard-us', 'B')
    set_switches(ctx, rec, SHIPPED_SWITCHES, KEY_B_EXPECT)
    reset_baseline(ctx, rec)
    # The first press arms the shell's return target (toggleTo), so the second press is the real test.
    press(ctx, rec, 'first', 'Alt+Space')
    truth_then_shell(ctx, rec, 'first', GROUP_JP, 'mozc')
    press(ctx, rec, 'again', 'Alt+Space')
    truth_then_shell(ctx, rec, 'again', GROUP_RU, 'keyboard-us')
    rec['observed']['truth'] = truth(ctx)
    return rec


@keys_case('K3')
def key_k3(ctx):
    rec = new_record('K3', 'Ctrl+Space (real key) switches to keyboard-ru-mac and back', 'B')
    set_switches(ctx, rec, SHIPPED_SWITCHES, KEY_B_EXPECT)
    reset_baseline(ctx, rec)
    press(ctx, rec, 'first', 'Ctrl+Space')
    truth_then_shell(ctx, rec, 'first', GROUP_RU, 'keyboard-ru-mac')
    press(ctx, rec, 'again', 'Ctrl+Space')
    truth_then_shell(ctx, rec, 'again', GROUP_RU, 'keyboard-us')
    rec['observed']['truth'] = truth(ctx)
    return rec


@keys_case('K5')
def key_k5(ctx):
    rec = new_record('K5', 'Alt+Space held 1.5 s switches exactly once', 'B')
    set_switches(ctx, rec, SHIPPED_SWITCHES, KEY_B_EXPECT)
    reset_baseline(ctx, rec)
    before = toast_count(ctx)
    dispatch_before = journal(ctx).count(KEY_DISPATCH_MARK + 'mozc')
    press(ctx, rec, 'held', 'Alt+Space', hold_ms=1500)
    ok, took = wait_for(lambda: truth_is(ctx, GROUP_JP, 'mozc'), 3)
    rec['checks']['held_fcitx5_US+JP_mozc'] = ok
    time.sleep(2.5)
    # A second toggle would return to US+RU; the final state and the toast count show exactly one switch.
    rec['checks']['still_mozc_after_2_5s'] = truth_is(ctx, GROUP_JP, 'mozc')
    toasts = toast_count(ctx) - before
    rec['observed']['toast_lines'] = toasts
    rec['checks']['one_layout_toast'] = toasts == 1
    dispatches = journal(ctx).count(KEY_DISPATCH_MARK + 'mozc') - dispatch_before
    rec['observed']['dispatch_count'] = dispatches
    rec['checks']['one_dispatch'] = dispatches == 1
    rec['observed']['truth'] = truth(ctx)
    if COMP == 'mango':
        # Only the held-key outcome is expected to fail. Setup, baseline and
        # actual key delivery remain required checks, including a real dispatch.
        held_checks = {name: rec['checks'].pop(name) for name in (
            'held_fcitx5_US+JP_mozc', 'still_mozc_after_2_5s', 'one_layout_toast', 'one_dispatch')}
        rec['checks']['held_dispatched'] = dispatches > 0
        rec['expected_failure'] = {
            'reason': 'mango 0.17.5 repeats held binds; no non-repeating bind flag',
            'checks': held_checks,
            'status': 'XPASS' if all(held_checks.values()) else 'XFAIL',
        }
    return rec


@keys_case('K4')
def key_k4(ctx):
    rec = new_record('K4', 'Super+Space (next key) three times cycles us -> de -> ru -> us', 'A')
    set_switches(ctx, rec, [], [('Super+Space', ('next',))], next_keys=['Super+Space'])
    reset_baseline(ctx, rec, GROUP_DEFAULT, 'keyboard-us')
    for i, expect in enumerate(['keyboard-de', 'keyboard-ru', 'keyboard-us'], start=1):
        press(ctx, rec, f'next_{i}', 'Super+Space')
        truth_then_shell(ctx, rec, f'next_{i}_is_{expect}', GROUP_DEFAULT, expect)
    rec['observed']['truth'] = truth(ctx)
    return rec


@keys_case('K6')
def key_k6(ctx):
    rec = new_record('K6', 'Ctrl+Alt+F for keyboard-fr (in no group): nothing changes, refusal logged', 'C')
    fr = [{'keys': ['Ctrl+Alt+F'], 'target': 'keyboard-fr', 'mode': 'toggle', 'label': ''}]
    set_switches(ctx, rec, fr, [('Ctrl+Alt+F', ('toggleim', 'keyboard-fr'))])
    reset_baseline(ctx, rec)
    before = truth(ctx)
    rec['observed']['before'] = before
    press(ctx, rec, 'press', 'Ctrl+Alt+F')
    time.sleep(1.5)
    rec['checks']['fcitx5_unchanged'] = truth(ctx) == before and truth_is(ctx, GROUP_RU, 'keyboard-us')
    rec['checks']['state_unchanged'] = shell_matches(ctx, GROUP_RU, 'keyboard-us')
    logged, took = wait_for(lambda: any('keyboard-fr' in line and ('in no group' in line or 'unknown input method' in line)
                                        for line in journal(ctx).splitlines()), 5, 0.5)
    rec['checks']['refusal_logged'] = logged
    rec['observed']['refusal_s'] = took
    rec['checks']['shell_alive'] = is_active(ctx)
    return rec


def instance_ids(ctx):
    inv = sh(['systemctl', '--user', 'show', '-p', 'InvocationID', '--value', ctx.shell_unit]).stdout.strip()
    return {'shell_invocation': inv, 'compositor_pids': sh(['pgrep', '-x', COMP_PROC[COMP]]).stdout.split()}


@keys_case('K8')
def key_k8(ctx):
    rec = new_record('K8', 'combo changed to Ctrl+Alt+Space: new combo works, old does nothing, no restart', 'B')
    reset_baseline(ctx, rec)
    before_text = wm_config_check(ctx)[1] if COMP != 'niri' else ''
    new_switches = [dict(SHIPPED_SWITCHES[0], keys=['Ctrl+Alt+Space']), SHIPPED_SWITCHES[1]]
    set_switches(ctx, rec, new_switches,
                 [('Ctrl+Alt+Space', ('toggleim', 'mozc')), ('Ctrl+Space', ('toggleim', 'keyboard-ru-mac'))],
                 tag='_changed')
    rec['checks']['old_combo_not_bound'] = not bound(ctx, 'Alt+Space', ('toggleim', 'mozc'))
    ids_before = instance_ids(ctx)
    rec['observed']['ids_before'] = ids_before
    press(ctx, rec, 'new', 'Ctrl+Alt+Space')
    truth_then_shell(ctx, rec, 'new', GROUP_JP, 'mozc')
    before_old = truth(ctx)
    press(ctx, rec, 'old', 'Alt+Space')
    time.sleep(2.0)
    rec['checks']['old_does_nothing'] = truth(ctx) == before_old and truth_is(ctx, GROUP_JP, 'mozc')
    rec['observed']['ids_after'] = instance_ids(ctx)
    rec['checks']['no_shell_or_compositor_restart'] = rec['observed']['ids_after'] == ids_before
    if COMP != 'niri':
        after_ok, after_text = wm_config_check(ctx)
        rec['observed']['config_check_before_change'] = before_text
        rec['observed']['config_check_after_change'] = after_text
        rec['checks']['no_new_config_error_after_reload'] = (
            wm_reload_ok(wm_route(ctx), before_text, after_text) if COMP == 'hyprland' else after_ok)
    rec['observed']['truth'] = truth(ctx)
    return rec


@keys_case('K7a')
def key_k7a(ctx):
    rec = new_record('K7a', 'profile D (fcitx5 installed, not running): Alt+Space bound, shell alive, refusal logged', 'D')
    set_switches(ctx, rec, SHIPPED_SWITCHES[:1], [('Alt+Space', ('toggleim', 'mozc'))])
    rec['checks']['fcitx5_not_running'] = not fcitx5_running()
    rec['observed']['state_before'] = shell_state(ctx)
    press(ctx, rec, 'press', 'Alt+Space')
    time.sleep(1.5)
    rec['checks']['fcitx5_still_not_running'] = not fcitx5_running()
    rec['checks']['state_unavailable'] = (shell_state(ctx) or {}).get('available') is False
    rec['observed']['state_after'] = shell_state(ctx)
    logged, took = wait_for(lambda: any('mozc' in line and 'unavailable' in line for line in journal(ctx).splitlines()),
                            5, 0.5)
    rec['checks']['refusal_logged'] = logged
    rec['observed']['refusal_s'] = took
    rec['checks']['shell_alive'] = is_active(ctx)
    rec['checks']['no_crash'] = not any('TypeError' in line or 'ReferenceError' in line
                                        for line in journal(ctx).splitlines())
    return rec


def make_shadow_path(ctx):
    """A PATH directory with a symlink to every /usr/bin and /usr/local/bin entry except fcitx5 (no package change)."""
    shadow = ctx.work / 'shadow-bin'
    shadow.mkdir()
    for d in ('/usr/bin', '/usr/local/bin'):
        for entry in os.scandir(d):
            if entry.name == 'fcitx5' or os.path.lexists(shadow / entry.name):
                continue
            os.symlink(entry.path, shadow / entry.name)
    if shutil.which('fcitx5', path=str(shadow)):
        raise SetupError('the shadow PATH still finds fcitx5')
    return str(shadow)


@keys_case('K7b')
def key_k7b(ctx):
    rec = new_record('K7b', 'fcitx5 not installed (PATH without fcitx5): no binds, Alt+Space changes nothing, shell alive', 'D')
    set_switches(ctx, rec, SHIPPED_SWITCHES[:1], [('Alt+Space', ('toggleim', 'mozc'))], tag='_installed')
    ctx.path_override = make_shadow_path(ctx)
    rec['observed']['fcitx5_running_before_restart'] = fcitx5_running()
    restart_shell(ctx, 'k7b')
    rec['observed']['settled_after_start_s'] = wait_shell_settled(ctx)
    lines = generated_lines(ctx)
    rec['observed']['input_file_k7b'] = lines
    rec['checks']['header_only'] = bool(lines) and 'Generated by Atmosphera' in lines[0]
    rec['checks']['no_binds_generated'] = binds_in_file(ctx) == []
    state_before = shell_state(ctx)
    fcitx_before = fcitx5_running()
    rec['observed']['fcitx5_running_before_press'] = fcitx_before
    press(ctx, rec, 'press', 'Alt+Space')
    time.sleep(1.5)
    rec['checks']['state_unchanged'] = shell_state(ctx) == state_before
    rec['checks']['fcitx5_unchanged'] = fcitx5_running() == fcitx_before
    rec['checks']['shell_alive'] = is_active(ctx)
    rec['checks']['no_crash'] = not any('TypeError' in line or 'ReferenceError' in line
                                        for line in journal(ctx).splitlines())
    return rec


CASES = {'A': [case7, case14],
         'B': [case1, case2, case3, case5, case6, case8, case9, case10, case11, case12, case13, case16, case15],
         'D': [case4]}
# --keys: the key cases of each profile (C has no non-key cases).
KEY_CASES = {'A': [key_k4], 'B': [key_k1, key_k2, key_k3, key_k5, key_k8], 'C': [key_k6],
             'D': [key_k7a, key_k7b]}


def stop_everything(ctx):
    activated = activated_fcitx5_units()
    for unit in [*reversed(ctx.units), *activated]:
        sh(['systemctl', '--user', 'stop', unit], timeout=60)
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline and (sh(['pgrep', '-x', 'qs']).returncode == 0 or fcitx5_running()):
        time.sleep(1)
    return {'units_stopped': [*reversed(ctx.units), *activated],
            'qs_running_after_stop': sh(['pgrep', '-x', 'qs']).returncode == 0,
            'fcitx5_running_after_stop': fcitx5_running()}


def detect_compositor():
    """(name, instance) of the one compositor running in the guest session."""
    found = {
        'niri': glob.glob(f'{RUNTIME}/niri.*.sock'),
        # A live instance has its .socket.sock; a dead one leaves its directory and log behind.
        'hyprland': [p for p in glob.glob(f'{RUNTIME}/hypr/*') if os.path.exists(os.path.join(p, '.socket.sock'))],
        'mango': glob.glob(f'{RUNTIME}/mango-*.sock'),
    }
    running = [name for name in COMPOSITORS if found[name]]
    if len(running) != 1:
        raise SetupError(f'expected exactly one running compositor, found {running or "none"}')
    if len(found[running[0]]) != 1:
        raise SetupError(f'{running[0]}: expected one instance, found {len(found[running[0]])}')
    instance = found[running[0]][0]
    return running[0], (os.path.basename(instance) if running[0] == 'hyprland' else instance)


def selected_cases(profile, wanted, keys):
    pool = KEY_CASES if keys else CASES
    if not pool.get(profile):
        raise SetupError(f'profile {profile} has no {"key" if keys else "non-key"} cases')
    chosen = [c for c in pool[profile] if not wanted or case_id(c) in wanted]
    if wanted and len(chosen) != len(set(wanted)):
        raise SetupError(f'unknown case id in {",".join(wanted)} for profile {profile}')
    return chosen


def keys_setup(ctx):
    """--keys: the test tree becomes the user-level `atmosphera` config, so the bind's `atmosphera ipc` (qs -c
    atmosphera) reaches this shell. Refuses to replace an existing link or config; the link is removed in finally."""
    link = Path(HOME) / '.config/quickshell/atmosphera'
    if os.path.lexists(link):
        raise SetupError(f'{link} exists; the key cases need it free')
    ctx.cli_dir_made = not link.parent.exists()
    link.parent.mkdir(parents=True, exist_ok=True)
    os.symlink(ctx.work / 'shell', link)
    ctx.cli_link = link


def keys_teardown(ctx):
    """Removes only the link this run made (and its directory when this run created it)."""
    if ctx.cli_link is None:
        return {'link_removed': True, 'dir_removed': None}
    removed = False
    if os.path.islink(ctx.cli_link):
        os.unlink(ctx.cli_link)
        removed = True
    dir_removed = None
    if ctx.cli_dir_made:
        try:
            ctx.cli_link.parent.rmdir()
            dir_removed = True
        except OSError:
            dir_removed = False
    return {'link_removed': removed and not os.path.lexists(ctx.cli_link), 'dir_removed': dir_removed}


def aside_niri_i18n(ctx):
    """--keys on niri: the shipped atmosphera-i18n.kdl would bind the same combos. It is moved aside (the niri
    backup restores it afterwards) and the session regenerates without it."""
    i18n = NIRI_DIR / NIRI_I18N
    if i18n.exists():
        (ctx.work / 'niri-aside').mkdir()
        shutil.move(str(i18n), str(ctx.work / 'niri-aside' / NIRI_I18N))


def cli_route(ctx):
    """`atmosphera ipc inputmethod state` (the bind's route) must answer with this shell's group and IM, polled
    until fcitx5's state has loaded in this shell. Only this shell runs, so an answer at all proves the link is
    what qs -c resolved; the matching group and IM show it is this shell's state, not an empty early answer."""
    seen = {}

    def matches():
        via_cli = sh(['atmosphera', 'ipc', 'inputmethod', 'state'], timeout=60)
        direct = ipc(ctx, 'state')[1]
        seen.update(rc=via_cli.returncode, cli=via_cli.stdout.strip(), direct=direct, err=via_cli.stderr.strip())
        if via_cli.returncode != 0 or not seen['cli']:
            return False
        try:
            a, b = json.loads(seen['cli']), json.loads(direct)
        except ValueError:
            # A shell without the state function (M20) answers with the same error text to both routes.
            return seen['cli'] == direct
        return a.get('group') == b.get('group') and a.get('im') == b.get('im') and a.get('available') == b.get('available')
    ok, took = wait_for(matches, 30, 0.5)
    seen['polled_s'] = took
    return ok, seen


def keys_session_ready(ctx):
    """niri: the session includes the generated input file and not the moved-aside i18n file."""
    if COMP != 'niri':
        return None
    ok, took = wait_for(lambda: 'include "atmosphera-input.kdl"' in session_text()
                        and 'atmosphera-i18n.kdl' not in session_text(), 30, 0.2)
    return {'ready': ok, 'after_s': took}


def run(args):
    source = args.source.resolve()
    work = args.work.resolve()
    output = args.output.resolve()
    ctx = Ctx(source, work, output, args.profile, output.name, keys=args.keys)
    cases = []
    result = {'label': output.name, 'profile': args.profile, 'source': str(source), 'work': str(work),
              'compositor': COMP, 'keys': args.keys, 'cases_requested': args.cases,
              'units': {'shell': ctx.shell_unit, 'fcitx5': ctx.fcitx_unit, 'focus': ctx.focus_unit},
              'setup_error': None, 'cases': [], 'cleanup': {}, 'niri': None, 'compositor_restore': None,
              'cli_route': None, 'keys_link': None, 'keys_session': None, 'passed': False}
    started = False
    try:
        preflight(source, work, output, args.profile, args.cases, args.keys)
        cases = selected_cases(args.profile, args.cases, args.keys)
        output.mkdir(parents=True)
        started = True
        setup_work(ctx)
        # Every admitted run starts a shell, which can rewrite the compositor's config.
        # Own the snapshot here, independently of the profile and selected cases.
        if COMP == 'niri':
            backup_niri(ctx)
        else:
            backup_wm(ctx)
        if args.keys:
            if COMP == 'niri':
                aside_niri_i18n(ctx)
            keys_setup(ctx)
            (output / 'keys').mkdir()
        if args.profile in PROFILE_GROUPS:
            start_fcitx5(ctx, PROFILE_GROUPS[args.profile])
            start_focus(ctx)
        else:
            write_fcitx5_profile()
        start_shell(ctx)
        if args.keys:
            ok, route = cli_route(ctx)
            result['cli_route'] = {'passed': ok, **route}
            if not ok:
                raise SetupError(f'atmosphera ipc does not reach this shell: {route}')
            result['keys_session'] = keys_session_ready(ctx)
        if args.profile == 'D':
            detach_fcitx5(ctx)
        for case in cases:
            cid = case_id(case)
            try:
                rec = case(ctx)
            except Exception as e:  # a crashed case is a failed case; the run goes on
                rec = new_record(cid, 'crashed', args.profile)
                rec['checks']['no_crash'] = False
                rec['notes'].append(f'case crashed: {type(e).__name__}: {e}')
            rec['passed'] = bool(rec['checks']) and all(rec['checks'].values())
            result['cases'].append(rec)
            status = rec.get('expected_failure', {}).get('status', 'PASS') if rec['passed'] else 'FAIL'
            print(f"{rec['case']} {status}", flush=True)
    except SetupError as e:
        result['setup_error'] = str(e)
        print(f'setup failed: {e}', file=sys.stderr)
    except (OSError, subprocess.SubprocessError, IndexError) as e:
        result['setup_error'] = f'{type(e).__name__}: {e}'
        print(f'setup failed: {result["setup_error"]}', file=sys.stderr)
    finally:
        if started:
            if args.keys:
                # The driver stops polling when the guest is finished.
                (output / 'keys').mkdir(exist_ok=True)
                (output / 'keys' / 'finished').write_text('done\n')
            for unit, name in ((ctx.shell_unit, 'shell-journal.txt'), (ctx.fcitx_unit, 'fcitx5-journal.txt')):
                text = sh(['journalctl', '--user', '-u', unit, '--no-pager', '-o', 'cat'], timeout=120).stdout
                (output / name).write_text(text)
            result['cleanup'] = stop_everything(ctx)
            if ctx.niri_backup is not None:
                try:
                    result['niri'] = restore_niri(ctx)
                except (OSError, subprocess.SubprocessError) as e:
                    result['niri'] = {'passed': False, 'error': f'{type(e).__name__}: {e}'}
            result['notes'] = ctx.notes
            if ctx.wm_backup is not None:
                try:
                    result['compositor_restore'] = restore_wm(ctx)
                except (OSError, subprocess.SubprocessError) as e:
                    result['compositor_restore'] = {'passed': False, 'error': f'{type(e).__name__}: {e}'}
            if args.keys:
                result['keys_link'] = keys_teardown(ctx)
            niri_ok = result['niri'] is None or result['niri'].get('passed') is True
            wm_ok = result['compositor_restore'] is None or result['compositor_restore'].get('passed') is True
            niri_ok = niri_ok and wm_ok
            link_ok = result['keys_link'] is None or result['keys_link']['link_removed']
            result['passed'] = (result['setup_error'] is None and bool(result['cases'])
                                and all(c['passed'] for c in result['cases'])
                                and not result['cleanup']['qs_running_after_stop']
                                and not result['cleanup']['fcitx5_running_after_stop'] and niri_ok and link_ok)
            (output / 'result.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    if result['setup_error']:
        return 3
    return 0 if result['passed'] else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--source', type=Path, required=True)
    ap.add_argument('--work', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--profile', choices=PROFILES, required=True)
    ap.add_argument('--cases', default='', help='comma-separated case ids (default: every case of the profile)')
    ap.add_argument('--keys', action='store_true',
                    help='run the key-press cases (K1-K8) of the profile instead of the switch cases (M29)')
    args = ap.parse_args(argv)
    args.cases = [c.strip() for c in args.cases.split(',') if c.strip()]
    global COMP, COMP_INSTANCE
    COMP, COMP_INSTANCE = detect_compositor()
    os.environ.update(XDG_RUNTIME_DIR=RUNTIME, WAYLAND_DISPLAY=WAYLAND[COMP], DBUS_SESSION_BUS_ADDRESS=BUS,
                      **compositor_env())
    return run(args)


if __name__ == '__main__':
    sys.exit(main())
