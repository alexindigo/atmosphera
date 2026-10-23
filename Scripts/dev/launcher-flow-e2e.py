#!/usr/bin/env python3
"""Real-key launcher flow on the explicitly owned launcher VM's console niri.

Run --prepare once after tools/install, then --label LABEL once per version.
After installing a new candidate use --observe to attach the passive probe.
The passive IPC observer is installed in the guest only; no activation or
selection is simulated via IPC. All input goes through uinput and niri.
Full screenshots remain under the guest workspace, alongside JSON evidence.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


ROOT = Path('/home/tester/Projects/atmosphera-launcher')
CONFIG = Path('/etc/xdg/quickshell/atmosphera')
SOCKET = ROOT / 'runtime/input.sock'
APP = 'launcher-flow-alpha'
APPS = ('alpha', 'beta', 'gamma')
SHORTCUT = ['125:1', '57:1', '57:0', '125:0']
PROBE = r'''
  // BEGIN launcher-flow passive observer (guest test copy only)
  IpcHandler {
    target: "launcherFlow"
    function snapshot(): string {
      var screen = PanelService.findFallbackScreen();
      var open = PanelService.isLauncherOpen(screen);
      var panel = PanelService.getPanel("launcherPanel", screen);
      var core = open ? (Settings.data.appLauncher.overviewLayer ? PanelService.overlayLauncherCore : (panel ? panel.launcherCoreRef : null)) : null;
      function focused(item) {
        if (!item) return null;
        if (item.activeFocus && item.text !== undefined)
          return {text: String(item.text), activeFocus: true};
        var children = item.children || [];
        for (var i = 0; i < children.length; ++i) {
          var result = focused(children[i]);
          if (result) return result;
        }
        return null;
      }
      var entries = DesktopEntries.applications.values || [];
      return JSON.stringify({
        open: open, query: core ? core.searchText : null,
        index: core ? core.selectedIndex : null,
        results: core ? core.results.map(function(r) { return {id: r.appId || r.usageKey || r.name, name: r.name}; }) : [],
        focused: focused(core),
        desktop: entries.filter(function(e) { return e.id.indexOf("launcher-flow-") === 0; }).map(function(e) { return {id: e.id, name: e.name}; })
      });
    }
  }
  // END launcher-flow passive observer
'''


def command(argv, seconds=10, check=True):
    return subprocess.run(['timeout', '--kill-after=3', str(seconds), *map(str, argv)],
                          env=os.environ, capture_output=True, text=True,
                          check=check, timeout=seconds + 5)


def boundary():
    assert os.getuid() == 1000 and Path.home() == Path('/home/tester')
    assert '52:54:00:82:44:3c' in [p.read_text().strip() for p in Path('/sys/class/net').glob('*/address')]
    assert Path(os.environ['TMPDIR']).resolve().is_relative_to(ROOT)
    assert command(['findmnt', '-n', '-o', 'UUID', '-T', ROOT]).stdout.strip() == '5c5bde9a-2912-4e4f-800c-690aa35d0168'
    sockets = list(Path('/run/user/1000').glob('niri.*.sock'))
    assert len(sockets) == 1, sockets
    os.environ.update(XDG_RUNTIME_DIR='/run/user/1000', WAYLAND_DISPLAY='wayland-1',
                      DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus',
                      NIRI_SOCKET=str(sockets[0]), YDOTOOL_SOCKET=str(SOCKET))


def snapshot():
    return json.loads(command(['qs', '-c', 'atmosphera', 'ipc', 'call', 'launcherFlow', 'snapshot']).stdout)


def windows():
    return json.loads(command(['niri', 'msg', '--json', 'windows']).stdout)


def keys(*codes):
    command(['ydotool', 'key', '--key-delay', '0', *codes])


def press(code):
    keys(f'{code}:1', f'{code}:0')


def wait(predicate, seconds=5):
    end = time.monotonic() + seconds
    last = None
    while time.monotonic() < end:
        last = predicate()
        if last:
            return last
        time.sleep(.03)
    raise AssertionError(f'condition not observed within {seconds}s (last={last!r})')


def desktop(name, title=None):
    path = Path.home() / '.local/share/applications' / f'launcher-flow-{name}.desktop'
    path.parent.mkdir(parents=True, exist_ok=True)
    pending = path.with_suffix('.pending')
    pending.write_text('[Desktop Entry]\nType=Application\n'
                    f'Name={title or "Launcher Flow " + name.title()}\n'
                    f'Exec=foot --app-id=launcher-flow-{name} --title=launcher-flow-{name} /usr/bin/sleep 300\n'
                    'Terminal=false\nCategories=Utility;\n')
    pending.replace(path)
    return path


def install_probe():
    qml = CONFIG / 'shell.qml'
    original = qml.read_text()
    assert 'launcher-flow passive observer' not in original, 'probe already installed'
    assert original.count('ShellRoot {') == 1
    backup = ROOT / 'runtime' / ('shell-before-observer-' + hashlib.sha256(original.encode()).hexdigest() + '.qml')
    if not backup.exists():
        backup.write_text(original)
    observed = original.replace('import Quickshell\n', 'import Quickshell\nimport Quickshell.Io\n', 1)
    observed = observed.replace('ShellRoot {', 'ShellRoot {' + PROBE, 1)
    staged = ROOT / 'runtime/shell-with-observer.qml'
    staged.write_text(observed)
    command(['sudo', '-n', 'cp', staged, qml])


def prepare():
    assert not command(['pgrep', '-x', 'qs'], check=False).stdout.strip(), 'prepare requires no console shell'
    for name in APPS:
        desktop(name)
    settings_path = Path.home() / '.config/atmosphera/settings.json'
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    settings = json.loads((CONFIG / 'Configs/defaults.json').read_text())
    settings['general']['showChangelogOnStartup'] = False
    settings['appLauncher'].update(pinnedApps=['launcher-flow-' + name for name in APPS],
                                   viewMode='list', overviewLayer=False)
    if settings_path.exists():
        assert json.loads(settings_path.read_text()) == settings, 'preserve existing settings'
    else:
        settings_path.write_text(json.dumps(settings, indent=2))
    install_probe()
    config = Path.home() / '.config/niri/config.kdl'
    backup = ROOT / 'runtime/niri-before-shortcut.kdl'
    niri = backup.read_text() if backup.exists() else config.read_text()
    assert niri.count('\nbinds {') == 1
    if not backup.exists():
        backup.write_text(niri)
    binding = '    Mod+Space { spawn "qs" "-c" "atmosphera" "ipc" "call" "launcher" "toggle"; }\n'
    configured = niri.replace('\nbinds {', '\nbinds {\n    // launcher keyboard test shortcut\n' + binding, 1)
    assert config.read_text() in (niri, configured), 'unexpected compositor config changes'
    config.write_text(configured)
    print(command(['niri', 'validate']).stderr, flush=True)
    command(['sudo', '-n', 'systemd-run', '--unit=launcher-flow-input', '--collect',
             '-p', 'RuntimeMaxSec=7200', '-p', 'TimeoutStopSec=5',
             '--setenv=TMPDIR=' + str(ROOT / 'tmp'), '/usr/bin/ydotoold',
             '--socket-path=' + str(SOCKET), '--socket-own=1000:1000'])
    wait(SOCKET.exists)
    session = ['systemd-run', '--user', '--unit=launcher-flow-session', '--collect',
               '--service-type=exec', '-p', 'RuntimeMaxSec=7200', '-p', 'TimeoutStopSec=5',
               '-p', 'StandardOutput=append:' + str(ROOT / 'evidence/console-shell.log'),
               '-p', 'StandardError=inherit', '--working-directory=' + str(ROOT)]
    for key in ('TMPDIR', 'XDG_RUNTIME_DIR', 'WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'NIRI_SOCKET'):
        session.append('--setenv=' + key + '=' + os.environ[key])
    command([*session, 'qs', '-c', 'atmosphera', '--no-color', '--log-times'])
    pid = int(command(['systemctl', '--user', 'show', 'launcher-flow-session', '-p', 'MainPID', '--value']).stdout)
    (ROOT / 'evidence/console-shell.pid').write_text(str(pid))
    wait(lambda: 'launcherFlow' in command(['qs', '-c', 'atmosphera', 'ipc', 'show'], check=False).stdout, 20)
    # Niri's first-run overlay must be dismissed before any capture or test.
    press(1)
    print(json.dumps({'prepared': True, 'shell_pid': pid, 'state': snapshot()}, indent=2))


def run(label):
    output = ROOT / 'evidence' / label
    assert not output.exists(), 'labels are single-use'
    output.mkdir()
    record = {'label': label, 'harness_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'input': 'ydotool/uinput -> console niri -> Mod+Space binding -> qs launcher.toggle',
              'cases': []}

    def evidence(name):
        data = {'state': snapshot(), 'windows': windows(),
                'processes': command(['ps', '-u', 'tester', '-o', 'pid,lstart,args']).stdout,
                'monotonic': time.monotonic()}
        (output / (name + '.json')).write_text(json.dumps(data, indent=2))
        command(['grim', output / (name + '.png')])
        return data

    def closed():
        if snapshot()['open']:
            # Test cases are independent even when Escape is a product failure.
            # Reset with the real compositor toggle, never a simulated action.
            keys(*SHORTCUT)
            wait(lambda: not snapshot()['open'])
            time.sleep(.2)

    def opened():
        closed()
        keys(*SHORTCUT)
        wait(lambda: snapshot()['open'])
        wait(lambda: len(snapshot()['results']) > 0)
        return snapshot()

    def selected(state):
        return state['results'][state['index']]['id']

    def case(name, body):
        try:
            details = body()
            status = 'PASS'
        except (AssertionError, subprocess.SubprocessError) as error:
            details = {'error': str(error)}
            status = 'FAIL'
        details['final'] = evidence(name)
        record['cases'].append({'name': name, 'status': status, **details})
        (output / 'result.json').write_text(json.dumps(record, indent=2))
        print(name, status, json.dumps({k: v for k, v in details.items() if k != 'final'}), flush=True)

    def initial():
        state = opened()
        assert state['focused'] and state['focused']['activeFocus'], state
        assert state['query'] == '' and state['index'] == 0, state
        assert selected(state) == APP, state
        return {'observed': state}

    def typeahead():
        closed()
        # Single uinput invocation, zero inter-key delay, no IPC readiness wait:
        # Super+Space release immediately followed by the evdev "alpha" keys.
        codes = [30, 38, 25, 35, 30]
        keys(*SHORTCUT, *[s for c in codes for s in (f'{c}:1', f'{c}:0')])
        wait(lambda: snapshot()['open'])
        time.sleep(.25)
        state = snapshot()
        assert state['query'] == 'alpha', state
        return {'observed': state, 'injected': 'alpha', 'inter_key_delay_ms': 0}

    def launch(filtered):
        state = opened()
        if filtered:
            command(['ydotool', 'type', '--key-delay', '2', '--', 'Launcher Flow Alpha'])
            wait(lambda: snapshot()['query'] == 'Launcher Flow Alpha')
            state = snapshot()
        assert selected(state) == APP, state
        before = windows()
        evidence(('filtered' if filtered else 'top') + '-before-enter')
        press(28)
        try:
            window = wait(lambda: next((w for w in windows() if w['app_id'] == APP and w['id'] not in {old['id'] for old in before}), None), 5)
        except AssertionError:
            raise AssertionError({'before': state, 'after': snapshot(), 'windows': windows()}) from None
        assert not snapshot()['open'], snapshot()
        evidence(('filtered' if filtered else 'top') + '-window')
        command(['niri', 'msg', 'action', 'close-window', '--id', str(window['id'])])
        wait(lambda: all(w['id'] != window['id'] for w in windows()))
        return {'window_observed': window, 'before': state}

    def navigation():
        state = opened()
        assert len(state['results']) >= 3, state
        steps = []
        for code, expected in ((108, 1), (103, 0), (103, len(state['results']) - 1), (108, 0)):
            press(code)
            wait(lambda: snapshot()['index'] == expected)
            steps.append(snapshot())
        return {'steps': steps}

    def escape():
        opened()
        press(1)
        wait(lambda: not snapshot()['open'])
        return {'closed': True}

    def refresh():
        opened()
        press(108)
        wait(lambda: snapshot()['index'] == 1)
        before = snapshot()
        identity = selected(before)
        evidence('refresh-before')
        desktop('alpha', 'Launcher Flow Zeta')
        wait(lambda: any(e['name'] == 'Launcher Flow Zeta' for e in snapshot()['desktop']))
        time.sleep(.3)
        after = snapshot()
        assert selected(after) == identity, {'before': before, 'after': after}
        assert any(e['name'] == 'Launcher Flow Zeta' for e in after['results']), {'error': 'desktop source refreshed but visible results stale', 'before': before, 'after': after}
        return {'before': before, 'after': after}

    case('shortcut-focus-top', initial)
    case('immediate-typeahead', typeahead)
    case('shortcut-enter-window', lambda: launch(False))
    case('filter-enter-window', lambda: launch(True))
    case('up-down-wrap', navigation)
    case('escape-closes', escape)
    case('background-refresh-identity', refresh)
    closed()
    desktop('alpha')
    record['passed'] = all(c['status'] == 'PASS' for c in record['cases'])
    (output / 'result.json').write_text(json.dumps(record, indent=2))
    print(json.dumps({c['name']: c['status'] for c in record['cases']}, indent=2))
    return 0 if record['passed'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--prepare', action='store_true')
    group.add_argument('--observe', action='store_true')
    group.add_argument('--label')
    args = parser.parse_args()
    boundary()
    if args.observe:
        install_probe()
        return 0
    if args.prepare:
        prepare()
        return 0
    assert re.fullmatch(r'[a-z0-9][a-z0-9.-]*', args.label)
    return run(args.label)


if __name__ == '__main__':
    raise SystemExit(main())
