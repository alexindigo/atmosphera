#!/usr/bin/env python3
"""Real niri session-lock input/focus proof for the NToggle keyboard change.

The actual installed bundled locker acquires ext-session-lock, keeps its own
password focus through Tab/Backtab, rejects a wrong PAM password and releases
only after successful PAM. An independent keyboard canary remains unchanged
behind it. Test-only additions expose read-only state and diagnostics, never
authentication, focus setters or unlock methods. No secure holder is killed.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import subprocess
import time

from guest_profile import activate_profile, profile_argument
from locker_test_support import manage, recover_known_pam_hang, run, wait_for


OBSERVE = '''
  property var _focusProofSurfaces: []
  IpcHandler {
    target: "lockFocusProof"
    function state(): string {
      var surfaces = root._focusProofSurfaces.map(function(surface) {
        var focus = surface.contentItem.Window.activeFocusItem;
        return {screen: surface.screen.name, built: surface.uiBuilt,
          focus: String(focus), passwordFocus: !!focus && focus.echoMode === TextInput.Password};
      });
      return JSON.stringify({secure: lockSession.secure, surfaces: surfaces,
        passwordLength: lockContext.passwordText.length,
        probeText: lockContext.passwordText === "pha-lock-isolation",
        busy: lockContext.unlockInProgress, failed: lockContext.showFailure});
    }
  }
  Connections {
    target: lockContext
    function onDiagnostic(message) {
      if (message === "Authentication successful") console.log("FOCUS_PAM_SUCCESS");
    }
    function onFailed() { console.log("FOCUS_PAM_REJECTED"); }
  }
'''


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def variant(args, profile, name, baseline):
    work, out = args.work_root / name, args.output / name
    work.mkdir()
    out.mkdir()
    configs = work / 'quickshell'
    install = configs / 'atmosphera'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    if baseline is not None:
        shutil.copy2(baseline, install / 'Widgets/NToggle.qml')
    run(['bash', str(install / 'Scripts/bash/install-locker-configs'), str(install), str(configs)], timeout=60)
    locker = configs / 'atmosphera-lockscreen/shell.qml'
    session = locker.with_name('LockSession.qml')
    text = session.read_text()
    source_inputs = {str(path.relative_to(configs)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (configs / 'atmosphera-lockscreen').rglob('*')
        if path.is_file() and path.suffix in ('.qml', '.js')}
    assert text.count('  id: root\n') == text.count('      id: lockSurface\n') == 1
    session.write_text(text.replace('  id: root\n', '  id: root\n' + OBSERVE).replace(
        '      id: lockSurface\n', '      id: lockSurface\n'
        '      Component.onCompleted: root._focusProofSurfaces.push(lockSurface)\n'))
    config = work / 'config'
    config.mkdir()
    write_json(config / 'settings.json', dict(settingsVersion=62,
        general=dict(lockScreenPlugin='default', autoStartAuth=False, compactLockScreen=True),
        location=dict(weatherEnabled=False)))
    write_json(config / 'plugins.json', dict(version=6, states={}, sources=[]))
    # Eager hidden weather bindings use the ordinary cached presentation even
    # with weather disabled. Supply inert cache data, as in the preview proof;
    # this is not a weather/network consumer test.
    (work / 'cache').mkdir()
    write_json(work / 'cache/location.json', dict(latitude='', longitude='', weatherLastFetch=0,
        weather=dict(current_weather=dict(temperature=0, windspeed=0, weathercode=0, is_day=True),
                     current=dict(relativehumidity_2m=0), daily=dict(time=['2026-11-20'] * 4,
                     weathercode=[0] * 4, temperature_2m_max=[0] * 4, temperature_2m_min=[0] * 4))))
    background = install / 'lock-background.qml'
    shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-lock-background.qml', background)
    environment = dict(os.environ, **profile.session_environment(),
        ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(work / 'cache'),
        ATMOSPHERA_STATE_DIR=str(work / 'state'), QML_DISABLE_DISK_CACHE='1')
    # The adapter discovers this session from the actual display peer. No
    # caller-provided login session, synthetic PAM or alternate unlock route.
    environment.update(XDG_CURRENT_DESKTOP='niri', XDG_SESSION_TYPE='wayland')
    os.environ.update(environment)
    sid = manage(install, dict(operation='discover'))['session']
    assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
    previous = manage(install, dict(operation='inspect', session=sid))
    assert not previous['descriptor'] or previous['descriptor']['phase'] == 'settled'
    injector = str(Path(os.environ['PHA_INPUT_INJECTOR']).resolve(strict=True))
    assert Path(injector).is_relative_to(profile.work_base)
    marker = work / 'credential'
    saved_hash = work / 'original-shadow-hash'
    password = secrets.token_hex(16)
    for path, value in ((marker, password), (saved_hash, run(['sudo', '-n', 'getent', 'shadow', 'tester']).stdout.split(':')[1])):
        path.touch(mode=0o600)
        path.write_text(value)
    original_hash = saved_hash.read_text()
    base, record, background_process = None, None, None
    authenticated = False
    trace = []

    def ipc(entry, target):
        result = subprocess.run(['qs', 'ipc', '-p', str(entry), 'call', target, 'state'],
            env=environment, capture_output=True, text=True, timeout=5)
        return json.loads(result.stdout) if result.returncode == 0 else None

    def keys(*argv):
        run([injector, *argv], env=environment)

    def inspect():
        return manage(install, dict(base, operation='inspect'))

    def journal():
        raw = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
            '_SYSTEMD_INVOCATION_ID=' + record['identity']['InvocationID']]).stdout
        # Credentials never appear in retained keyboard protocol lines.
        return '\n'.join(line for line in raw.splitlines() if 'wl_keyboard' not in line)

    def state():
        return ipc(locker, 'lockFocusProof')

    def locked():
        return run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'yes'

    try:
        with (out / 'background.log').open('w') as log:
            background_process = subprocess.Popen(['qs', '-p', str(background)], env=environment,
                stdout=log, stderr=subprocess.STDOUT)
        wait_for(lambda: ipc(background, 'lockBackground'))
        keys('--', 'bg')
        wait_for(lambda: (ipc(background, 'lockBackground') or {}).get('length') == 2)
        background_before = ipc(background, 'lockBackground')
        run(['sudo', '-n', 'chpasswd'], input='tester:' + password + '\n')
        descriptor = manage(install, dict(operation='begin', session=sid, snapshot=dict(adapter='bundled'),
            settingsJson=(config / 'settings.json').read_text()))
        base = dict(session=sid, generation=descriptor['generation'])
        command = shlex.join(['env', *[key + '=' + environment[key] for key in (
            'ATMOSPHERA_CONFIG_DIR', 'ATMOSPHERA_CACHE_DIR', 'ATMOSPHERA_STATE_DIR', 'TMPDIR')],
            'WAYLAND_DEBUG=client', 'qs', '-p', str(locker)])
        record = manage(install, dict(base, operation='launch', role='real', command=command))
        wait_for(lambda: (inspect()['descriptor']['units']['real'].get('client') or {}).get('ready'), 25)
        assert manage(install, dict(base, operation='grant', role='real'))['granted']
        wait_for(lambda: (state() or {}).get('secure') and locked(), 25)
        initial = wait_for(lambda: (value if (value := state()) and value['surfaces']
            and all(surface['built'] and surface['passwordFocus'] for surface in value['surfaces']) else None), 15)
        focus = [surface['focus'] for surface in initial['surfaces']]
        trace.append(dict(stage='secure', state=initial))
        for gesture in (('-k', 'Tab'), ('-k', 'Tab'), ('-M', 'shift', '-k', 'Tab', '-m', 'shift'), ('-k', 'Escape')):
            keys(*gesture)
            time.sleep(.15)
            value = state()
            assert value['secure'] and locked()
            assert all(surface['passwordFocus'] for surface in value['surfaces'])
            assert [surface['focus'] for surface in value['surfaces']] == focus
            trace.append(dict(stage='gesture', gesture=list(gesture), state=value))
        keys('--', 'pha-lock-isolation')
        wait_for(lambda: (state() or {}).get('probeText'))
        isolated = ipc(background, 'lockBackground')
        assert isolated['length'] == background_before['length'] and isolated['toggles'] == background_before['toggles']
        assert 'unlock_and_destroy' not in journal()
        keys('-k', 'Return')  # This known probe is not the random throwaway password.
        try:
            wait_for(lambda: (state() or {}).get('failed') and not state()['busy'], 8)
        except AssertionError:
            if not recover_known_pam_hang(install, sid, 'real', work):
                raise
            wait_for(lambda: (state() or {}).get('failed') and not state()['busy'], 15)
        assert locked() and state()['secure'] and 'unlock_and_destroy' not in journal()
        trace.append(dict(stage='wrong-password-retained', state=state()))
        # PAM disables the password item during authentication. Observe focus
        # restoration before sending the next credential, never force it from
        # the test or replace authentication with a test-only unlock method.
        wait_for(lambda: all(surface['passwordFocus'] for surface in state()['surfaces']), 10)
        keys('-M', 'ctrl', '-k', 'a', '-m', 'ctrl', '-k', 'BackSpace')
        with marker.open() as secret:
            run([injector, '-'], stdin=secret, env=environment)
        assert state()['passwordLength'] == len(password)
        keys('-k', 'Return')
        wait_for(lambda: inspect()['units']['real']['gone'] and not locked(), 25)
        final = inspect()
        native = journal()
        assert re.search(r'ext_session_lock_v1#\d+\.locked\(\)', native)
        assert native.count('unlock_and_destroy') == 1
        assert native.index('FOCUS_PAM_SUCCESS') < native.index('unlock_and_destroy')
        assert final['descriptor']['units']['real']['client']['authenticated']
        assert final['descriptor']['units']['real']['protocolOutcome'] == 'authenticated-unlock'
        assert not final['units']['real']['members']
        after = ipc(background, 'lockBackground')
        assert after['length'] == background_before['length'] and after['toggles'] == background_before['toggles']
        manage(install, dict(base, operation='settle'))
        authenticated = True
        result = dict(status='PASS', variant=name, nativeProtocolLock=True, passwordFocus=True,
            wrongPasswordRetainedLock=True, backgroundUnchanged=True, pamBeforeSingleUnlock=True,
            trace=trace, final=final, sourceInputs=source_inputs,
            diagnostics=sorted(set(re.sub(r'\x1b\[[0-9;]*m', '', line).replace(str(work), '$CASE')
                for line in native.splitlines() if any(marker in line for marker in
                    ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'is not installed', 'is not a type')))),
            ntoggleSha256=hashlib.sha256((install / 'Widgets/NToggle.qml').read_bytes()).hexdigest())
        write_json(out / 'result.json', result)
        return result
    finally:
        if record:
            (out / 'native-journal.log').write_text(journal())
        # Never stop a secure holder or restore an unknown credential while it
        # still needs recovery. Failure retains protected recovery files only
        # inside the guest, not in the collected evidence directory.
        if authenticated or not record:
            run(['sudo', '-n', 'chpasswd', '-e'], input='tester:' + original_hash + '\n')
            assert run(['sudo', '-n', 'getent', 'shadow', 'tester']).stdout.split(':')[1] == original_hash
            marker.unlink()
            saved_hash.unlink()
            write_json(out / 'cleanup.json', dict(originalCredentialRestored=True,
                recoveryFilesRemoved=True, secureHolderKilled=False))
        else:
            write_json(out / 'failure-state.json', dict(trace=trace, view=inspect()))
        if background_process is not None and background_process.poll() is None:
            run(['qs', 'ipc', '-p', str(background), 'call', 'lockBackground', 'finish'], env=environment)
            background_process.wait(timeout=15)
        if authenticated:
            shutil.rmtree(configs)
        profile.verify()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'work-root', 'output', 'baseline-ntoggle'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--plugins', type=Path, help='run-driver compatibility; not loaded')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        rows = [variant(args, profile, 'candidate', None),
                variant(args, profile, 'previous-ntoggle', args.baseline_ntoggle)]
        new_diagnostics = sorted(set(rows[0]['diagnostics']) - set(rows[1]['diagnostics']))
        write_json(args.output / 'result.json', dict(status='FAIL' if new_diagnostics else 'PASS', variants=rows,
            newDiagnostics=new_diagnostics, inheritedDiagnostics=rows[1]['diagnostics']))
        if new_diagnostics:
            raise RuntimeError('new candidate locker runtime diagnostics: ' + repr(new_diagnostics))
        print('CASE real-lock-focus: PASS (native niri session lock, both NToggle variants, real PAM)', flush=True)


if __name__ == '__main__':
    main()
