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
  B  fcitx5 running with the profile this script writes: group US+RU
     (keyboard-us, keyboard-ru-mac) first, then US+JP (keyboard-us, mozc).
     A small focus window (qml6) holds a focused input context, because
     fcitx5 reports an empty CurrentInputMethod while no context has focus.
     Cases 1-3 and 5, 6, 8 with the shell running; case 9 last, with the shell
     stopped, drives the secure-mode fixture (Scripts/dev/fixtures/
     input-method-secure-mode.qml) as the only shell-side client.
  D  fcitx5 not running. The shell's DBus proxy activates org.fcitx.Fcitx5 on
     its own (the service file in /usr/share/dbus-1/services), so D lets the
     shell attach to the activated fcitx5, stops it, and then runs case 4.

Truth comes from fcitx5 through gdbus, never from the shell. The shell is driven
through `qs -p <work>/shell/shell.qml ipc call inputmethod ...`. The layout toast
is read from the shell's journal ("Layout toast:" lines); the state file from
$XDG_RUNTIME_DIR/fcitx-input-state.json.

Transient user units, all named after the output basename: imreg-<name>-fcitx5,
imreg-<name>-focus, imreg-<name>-shell, imreg-<name>-fixture. Each is stopped in
a finally block, as is any qs or fcitx5 left running, including D-Bus-activated
fcitx5 units (dbus-*org.fcitx.Fcitx5*). The fcitx5 profile is
~/.config/fcitx5/profile.

Exit: 0 when every case passes and cleanup is clean; 1 when a case or the cleanup
fails; 3 on a setup or precondition failure (the run is not evaluated).
"""
import argparse
import ast
from dataclasses import dataclass, field
import glob
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
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
PROFILE_GROUPS = {'A': PROFILE_A, 'B': PROFILE_B}
FIXTURE = Path(__file__).resolve().parent / 'fixtures' / 'input-method-secure-mode.qml'
FIXTURE_NAME = FIXTURE.name
TOAST_MARK = 'Layout toast:'
GDBUS = ['gdbus', 'call', '--session', '--dest', 'org.fcitx.Fcitx5', '--object-path', '/controller', '--method']
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
    shell_unit: str = ''
    fcitx_unit: str = ''
    focus_unit: str = ''
    fixture_unit: str = ''
    units: list = field(default_factory=list)
    notes: list = field(default_factory=list)

    def __post_init__(self):
        self.shell_unit = f'imreg-{self.name}-shell'
        self.fcitx_unit = f'imreg-{self.name}-fcitx5'
        self.focus_unit = f'imreg-{self.name}-focus'
        self.fixture_unit = f'imreg-{self.name}-fixture'

    @property
    def shell_qml(self):
        return self.work / 'shell' / 'shell.qml'

    @property
    def profile_dir(self):
        return self.work / 'profile'

    def trace(self, text):
        with open(self.output / 'trace.txt', 'a') as f:
            f.write(f'{time.strftime("%H:%M:%S")} {text}\n')


def preflight(source, work, output, profile):
    if profile not in ('A', 'B', 'D'):
        raise SetupError(f'profile {profile} not defined yet (M22 defines A, B and D)')
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
    for name in ('config', 'cache', 'state'):
        (ctx.profile_dir / name).mkdir(parents=True)
    settings = json.loads((ctx.source / 'Configs/defaults.json').read_text())
    settings['general']['showChangelogOnStartup'] = False
    (ctx.profile_dir / 'config' / 'settings.json').write_text(json.dumps(settings))
    (ctx.work / 'focus').mkdir()
    (ctx.work / 'focus' / 'probe.qml').write_text(FOCUS_QML)
    shutil.copyfile(FIXTURE, ctx.work / 'shell' / FIXTURE_NAME)


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
    return {'XDG_RUNTIME_DIR': RUNTIME, 'WAYLAND_DISPLAY': 'wayland-1',
            'DBUS_SESSION_BUS_ADDRESS': BUS}


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
    return dict(base_env(), ATMOSPHERA_CONFIG_DIR=f'{p}/config/', ATMOSPHERA_CACHE_DIR=f'{p}/cache/',
                ATMOSPHERA_STATE_DIR=f'{p}/state/', ATMOSPHERA_SETTINGS_FILE=f'{p}/config/settings.json',
                ATMOSPHERA_DEBUG='0', ATMOSPHERA_UPGRADELOG_URL='http://127.0.0.1:9',
                QT_FORCE_STDERR_LOGGING='1', NIRI_SOCKET=glob.glob(f'{RUNTIME}/niri.*.sock')[0])


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


CASES = {'A': [case7], 'B': [case1, case2, case3, case5, case6, case8, case9], 'D': [case4]}


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


def run(args):
    source = args.source.resolve()
    work = args.work.resolve()
    output = args.output.resolve()
    ctx = Ctx(source, work, output, args.profile, output.name)
    result = {'label': output.name, 'profile': args.profile, 'source': str(source), 'work': str(work),
              'units': {'shell': ctx.shell_unit, 'fcitx5': ctx.fcitx_unit, 'focus': ctx.focus_unit},
              'setup_error': None, 'cases': [], 'cleanup': {}, 'passed': False}
    started = False
    try:
        preflight(source, work, output, args.profile)
        output.mkdir(parents=True)
        started = True
        setup_work(ctx)
        if args.profile in PROFILE_GROUPS:
            start_fcitx5(ctx, PROFILE_GROUPS[args.profile])
            start_focus(ctx)
        else:
            write_fcitx5_profile()
        start_shell(ctx)
        if args.profile == 'D':
            detach_fcitx5(ctx)
        for case in CASES[args.profile]:
            cid = case.__name__.removeprefix('case')
            try:
                rec = case(ctx)
            except Exception as e:  # a crashed case is a failed case; the run goes on
                rec = new_record(cid, 'crashed', args.profile)
                rec['checks']['no_crash'] = False
                rec['notes'].append(f'case crashed: {type(e).__name__}: {e}')
            rec['passed'] = bool(rec['checks']) and all(rec['checks'].values())
            result['cases'].append(rec)
            print(f"{rec['case']} {'PASS' if rec['passed'] else 'FAIL'}", flush=True)
    except SetupError as e:
        result['setup_error'] = str(e)
        print(f'setup failed: {e}', file=sys.stderr)
    except (OSError, subprocess.SubprocessError, IndexError) as e:
        result['setup_error'] = f'{type(e).__name__}: {e}'
        print(f'setup failed: {result["setup_error"]}', file=sys.stderr)
    finally:
        if started:
            for unit, name in ((ctx.shell_unit, 'shell-journal.txt'), (ctx.fcitx_unit, 'fcitx5-journal.txt')):
                text = sh(['journalctl', '--user', '-u', unit, '--no-pager', '-o', 'cat'], timeout=120).stdout
                (output / name).write_text(text)
            result['cleanup'] = stop_everything(ctx)
            result['notes'] = ctx.notes
            result['passed'] = (result['setup_error'] is None and bool(result['cases'])
                                and all(c['passed'] for c in result['cases'])
                                and not result['cleanup']['qs_running_after_stop']
                                and not result['cleanup']['fcitx5_running_after_stop'])
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
    args = ap.parse_args(argv)
    os.environ.update(XDG_RUNTIME_DIR=RUNTIME, WAYLAND_DISPLAY='wayland-1', DBUS_SESSION_BUS_ADDRESS=BUS)
    return run(args)


if __name__ == '__main__':
    sys.exit(main())
