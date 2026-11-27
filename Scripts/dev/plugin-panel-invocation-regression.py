#!/usr/bin/env python3
"""Exercise real plugin panels and Quickshell IPC on a two-output Wayland VM."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time

from presentation_harness import (
    add_execution_arguments, check_execution_paths, remaining_budget, run_harness, write_receipt,
)
from qml_probe import inject_probe, probe_owner_path


MAIN = '''import QtQuick
import Quickshell.Io
Item {
  id: main
  property var pluginApi: null
  property var placements: []
  IpcHandler {
    target: "invocation-main-" + (main.pluginApi?.pluginId ?? "loading")
    function invoke(operation: string) { main.invoke(operation); }
  }
  function invoke(operation, screen, placed) {
    const api = placed || pluginApi;
    if (operation === "open")
      api.openPanel(screen);
    else if (operation === "toggle")
      api.togglePanel(screen);
    else
      api.closePanel(screen);
  }
}
'''

BAR = '''import QtQuick
Item {
  property var pluginApi: null
  implicitWidth: 24
  implicitHeight: 24
  onPluginApiChanged: {
    const main = pluginApi?.mainInstance;
    if (main && !main.placements.includes(pluginApi))
      main.placements = main.placements.concat([pluginApi]);
  }
}
'''

PANEL = '''import QtQuick
Item {
  property var pluginApi: null
  property var screen: null
  readonly property bool exclusiveOpen: screen?.name === "Virtual-2"
  readonly property real contentPreferredWidth: 240
  readonly property real contentPreferredHeight: 180
}
'''

PROBE = r'''
  property var firstFallback: null
  property var oldHost: null
  property int cornerFires: 0
  property bool immediateOpenAccepted: false
  property bool deferredOpenQueued: false
  QtObject {
    id: fixtureFocus
    function withCurrentScreen(callback) {
      callback([...Quickshell.screens].sort((a, b) => a.name.localeCompare(b.name))[0]);
    }
  }
  Connections {
    target: HotCornersService
    function onFired(corner, screenName) { shellRoot.cornerFires++; }
  }
  IpcHandler {
    target: "invocationProbe"

    // Keep IPC focused on output 1 regardless of the host pointer; the
    // corner must still transfer to real output 2, not this default output.
    function fixFocus() { Service.screenDetector = fixtureFocus; }

    function state(): string {
      const placed = Service.getPluginAPI("niri-windows-map");
      const unplaced = Service.getPluginAPI("invocation-unplaced");
      const map = placed?.mainInstance;
      const fallback = unplaced ? PluginInstances.latestInvocationApi(unplaced) : null;
      const outputs = [...Quickshell.screens].sort((a, b) => a.name.localeCompare(b.name));
      let registered = outputs.length === 2;
      let visible = [];
      let settled = true;
      for (const screen of outputs) {
        for (const number of [1, 2]) {
          const slot = PanelService.getPanel("pluginPanel" + number, screen, false);
          registered = registered && !!slot;
          if (!slot?.isPanelOpen)
            continue;
          if (slot.isClosing || !slot.pluginInstance || !slot.sizeAnimationComplete) {
            settled = false;
            continue;
          }
          const api = slot.pluginInstance.pluginApi;
          visible.push({screen: screen.name, slot: number, id: api.pluginId,
                        placement: api.placement?.section ?? "", owned: api.panelHost === slot});
        }
      }
      return JSON.stringify({outputs: outputs.map(screen => screen.name), visible, settled,
        ready: !!(registered && map && unplaced?.mainInstance && !delayedInitTimer.running && !wizardRetryTimer.running),
        placements: (map?.placements ?? []).map(api => api.placement.section),
         latest: placed ? PluginInstances.latestInvocationApi(placed)?.placement?.section ?? "" : "",
         mapScreen: placed?.panelOpenScreen?.name ?? "", cornerFires: shellRoot.cornerFires,
         mapVersion: Service.loadedPlugins["niri-windows-map"]?.manifest?.version ?? "",
         mapPickerReady: !!(registered && placed && ActionRegistry.ready && !delayedInitTimer.running && !wizardRetryTimer.running),
        panelOnlyLoaded: !!Service.getPluginAPI("invocation-panel-only"),
        exactFloor: Service.checkPluginCompatibility({minAtmospheraVersion: Version.currentVersion}),
        futureFloor: Service.checkPluginCompatibility({minAtmospheraVersion: "99.0.0"}),
        fallbackScreen: fallback?.panelOpenScreen?.name ?? "",
        immediateOpenAccepted: shellRoot.immediateOpenAccepted,
        deferredOpenQueued: shellRoot.deferredOpenQueued,
        distinctFallback: !!(fallback && fallback !== unplaced && fallback.mainInstance === unplaced.mainInstance),
        sameFallback: !!(fallback && fallback === shellRoot.firstFallback)});
    }

    function actions(): string {
      return JSON.stringify(ActionRegistry.actions.filter(row => row.key.startsWith("invocation-")).map(row =>
         ({key: row.key, command: ActionRegistry.compose(row, {})})));
    }

    function mapActions(): string {
      return JSON.stringify(ActionRegistry.actions.filter(row => row.group === "Niri Windows Map" ||
        row.key.startsWith("niri-windows-map/")).map(row =>
          ({key: row.key, label: row.label, command: ActionRegistry.compose(row, {})})));
    }

    function cornerCommand(): string { return Settings.data.general.hotCorners.bottomRight; }
    function allowClose(name: string) {
      const screen = Quickshell.screens.find(output => output.name === name);
      PanelService.getPanel("pluginPanel2", screen, false).closeAdmission = null;
    }

    function rememberFallback() {
      shellRoot.firstFallback = PluginInstances.latestInvocationApi(Service.getPluginAPI("invocation-unplaced"));
    }

    function fromMain(operation: string, name: string, section: string) {
      const base = Service.getPluginAPI("niri-windows-map");
      const output = Quickshell.screens.find(screen => screen.name === name);
      const placed = base.mainInstance.placements.find(api => api.placement.section === section);
      base.mainInstance.invoke(operation, output, placed);
    }

    function corner(name: string) {
      HotCornersService.cancel();
      HotCornersService.enter({key: name + ":bottomRight", screenName: name, corner: "bottomRight"}, 0, shellRoot);
    }

    function rememberHost() {
      shellRoot.oldHost = PluginInstances.latestInvocationApi(Service.getPluginAPI("niri-windows-map")).panelHost;
    }

    function staleUnload() { shellRoot.oldHost.unloadPluginPanel(); }
    function emptyFirstSlot(name: string) {
      const screen = Quickshell.screens.find(output => output.name === name);
      const slot = PanelService.getPanel("pluginPanel1", screen, false);
      if (!slot.isPanelOpen)
        slot.unloadPluginPanel();
    }
    function probeOpenRefusal(name: string) {
      const screen = Quickshell.screens.find(output => output.name === name);
      const blocker = PanelService.getPanel("pluginPanel2", screen, false);
      const target = PanelService.getPanel("pluginPanel1", screen, false);
      const base = Service.getPluginAPI("invocation-unplaced");
      blocker.closeAdmission = () => false;
      // Exercise the synchronous claim with behavior already known; then let
      // the next request discover its behavior by loading real panel content.
      target.panelBehaviorReady = true;
      shellRoot.immediateOpenAccepted = base.openPanel(screen);
      target.panelBehaviorReady = Qt.binding(() => target.currentPluginId === "" || target.pluginInstance !== null);
      shellRoot.deferredOpenQueued = base.openPanel(screen);
    }
    function finish() { Qt.callLater(Qt.quit); }
  }
'''

ERRORS = re.compile(r'Failed to load configuration|TypeError:|ReferenceError:|SyntaxError:|is not a type|is unavailable')


def exercise(work, real_map=False):
    """Drive consumer IPC inside the same private PID and D-Bus namespaces."""
    shell = subprocess.Popen(['qs', '-n', '-p', str(work / 'shell'), '--no-color'])
    try:
        def ipc(*args):
            return subprocess.check_output(['qs', 'ipc', '--pid', str(shell.pid), 'call', *args],
                                           text=True, stderr=subprocess.PIPE, timeout=5).strip()

        def probe(*args):
            return ipc('invocationProbe', *args)

        def cli(*args):
            return subprocess.check_output([work / 'shell/Scripts/bash/atmosphera', *args],
                                           text=True, stderr=subprocess.STDOUT, timeout=8).strip()

        def wait(name, predicate):
            deadline = time.monotonic() + min(20, remaining_budget())
            last = None
            while time.monotonic() < deadline and shell.poll() is None:
                try:
                    last = json.loads(probe('state'))
                    if last['settled'] and predicate(last):
                        print('INVOCATION_CASE ' + json.dumps(dict(name=name, state=last)), flush=True)
                        return last
                except (subprocess.CalledProcessError, json.JSONDecodeError):
                    if last is not None:
                        raise
                time.sleep(.1)
            raise AssertionError(f'{name}: {last!r}; shell exit={shell.poll()}')

        def at(screen, slot, placement='', plugin='niri-windows-map'):
            return dict(screen=screen, slot=slot, id=plugin, placement=placement, owned=True)

        def visible(name, *panels, also=lambda _: True):
            return wait(name, lambda state: state['visible'] == list(panels) and also(state))

        def generic(operation, key='invocation-unplaced'):
            ipc('plugin', operation + 'Panel', key)

        if real_map:
            plugin_id = 'niri-windows-map'
            manifest = json.loads((work / 'config/atmosphera/plugins' / plugin_id / 'manifest.json').read_text())
            initial = wait('real-map-ready-two-outputs', lambda s: s['mapPickerReady'] and s['mapVersion'] == manifest['version'])
            available = manifest.get('actions', [dict(id='toggle', label='Windows map', panel='toggle')])
            expected = [dict(key=f'{plugin_id}/{a["id"]}', label=a['label'],
                             command=f'atmosphera ipc plugin {a["panel"]}Panel {plugin_id}') for a in available]
            rows = json.loads(probe('mapActions'))
            assert rows == expected, f'map {manifest["version"]} picker returned {rows}, expected {expected}'
            print('INVOCATION_CASE ' + json.dumps(dict(name='real-map-picker-actions', version=manifest['version'],
                                                       rows=rows)), flush=True)
            probe('fixFocus')
            toggle = next(row for row in rows if row['key'] == f'{plugin_id}/toggle')
            cli(*shlex.split(toggle['command'])[1:])
            wait('real-map-picker-opens', lambda s: len(s['visible']) == 1 and s['visible'][0]['id'] == plugin_id and
                 s['visible'][0]['screen'] == initial['outputs'][0] and s['visible'][0]['owned'])
            cli(*shlex.split(toggle['command'])[1:])
            visible('real-map-picker-closes')
            probe('finish')
            return shell.wait(timeout=5)

        initial = wait('ready-two-outputs', lambda s: s['ready'] and s['placements'] == ['left'])
        probe('fixFocus')
        generic('close')
        visible('close-does-not-create', also=lambda s: not s['distinctFallback'])
        generic('open')
        selected = wait('generic-open-creates-distinct-fallback',
                        lambda s: s['distinctFallback'] and len(s['visible']) == 1 and
                        s['visible'][0]['id'] == 'invocation-unplaced' and s['visible'][0]['owned'])['visible'][0]
        one = selected['screen']
        two = next(name for name in initial['outputs'] if name != one)
        probe('rememberFallback')
        generic('open')
        visible('generic-open-idempotent', selected, also=lambda s: s['sameFallback'])
        generic('toggle')
        visible('generic-toggle-off', also=lambda s: s['sameFallback'])
        generic('toggle')
        visible('generic-toggle-on-reuses', selected, also=lambda s: s['sameFallback'])
        generic('close')
        visible('generic-close-reuses', also=lambda s: s['sameFallback'])

        settings = work / 'config/atmosphera/settings'
        bar = settings / 'bar.json'
        edited = json.loads(bar.read_text())
        edited['widgets']['right'] = edited['widgets']['left']
        new = bar.with_suffix('.new')
        new.write_text(json.dumps(edited))
        new.replace(bar)
        wait('two-placements-latest-spawned',
             lambda s: s['placements'] == ['left', 'right'] and s['latest'] == 'right')

        # The saved CLI commands must still take the same latest instance each time.
        cli('ipc', 'niriWindowsMap', 'open')
        # The fallback retains its closed slot 1. The first map open takes
        # slot 2 and must keep matching it even after slot 1 changes owners.
        map_panel = at(one, 2, 'right')
        visible('map-ipc-open-latest', map_panel)
        cli('ipc', 'niriWindowsMap', 'toggle')
        visible('map-ipc-toggle-off')
        cli('ipc', 'niriWindowsMap', 'toggle')
        visible('map-ipc-toggle-on', map_panel)
        cli('ipc', 'niriWindowsMap', 'close')
        visible('map-ipc-close')

        probe('fromMain', 'open', one, 'left')
        visible('main-forwards-first-placement', at(one, 1, 'left'))
        probe('fromMain', 'open', one, '')
        visible('main-without-placement-selects-latest', at(one, 1, 'left'), at(one, 2, 'right'))
        probe('fromMain', 'close', one, 'left')
        visible('main-close-is-exact', at(one, 2, 'right'))
        probe('emptyFirstSlot', one)
        ipc('invocation-main-niri-windows-map', 'invoke', 'open')
        visible('exact-slot-precedes-empty-slot', at(one, 2, 'right'))
        probe('fromMain', 'toggle', one, 'right')
        visible('placed-toggle-is-exact')

        ipc('invocation-main-niri-windows-map', 'invoke', 'open')
        visible('plugin-ipc-opens-latest-on-first-output', at(one, 2, 'right'))
        probe('rememberHost')
        probe('corner', two)
        visible('corner-transfers-to-trigger-output', at(two, 1, 'right'),
                also=lambda s: s['cornerFires'] == 1 and s['mapScreen'] == two)
        probe('staleUnload')
        probe('fromMain', 'close', one, '')
        visible('stale-close-does-not-clobber-transfer', at(two, 1, 'right'),
                also=lambda s: s['mapScreen'] == two)
        probe('corner', two)
        visible('corner-toggle-closes-on-trigger-output', also=lambda s: s['cornerFires'] == 2 and not s['mapScreen'])

        # The older explicit placement is open; the newer one still wins
        # invocation selection but does not hide the open panel from Main.
        probe('fromMain', 'open', two, 'left')
        older = at(two, 2, 'left')
        observed = visible('older-placement-is-open', older)
        probe('probeOpenRefusal', two)
        refusal = visible('dirty-owner-survives-open-refusal', older)
        problems = []
        if observed['mapScreen'] != two or observed['latest'] != 'right':
            problems.append(f"base panel screen does not follow the open older placement: {observed}")
        if refusal['immediateOpenAccepted'] or not refusal['deferredOpenQueued'] or refusal['fallbackScreen']:
            problems.append(f"refused open reported success or kept a host: {refusal}")
        if problems:
            raise AssertionError('\n'.join(problems))

        probe('allowClose', two)
        probe('fromMain', 'close', two, 'left')
        visible('legacy-placement-closed-before-new-actions')
        modern = 'invocation-panel-only'
        version_gate = wait('manifest-version-gate', lambda s: s['panelOnlyLoaded'] and s['exactFloor']['compatible'] and
                            not s['futureFloor']['compatible'] and s['futureFloor']['track'] == 'atmosphera')
        rows = {row['key']: row['command'] for row in json.loads(probe('actions'))}
        names = ('open', 'toggle', 'close')
        expected = {f'{modern}/{op}': f'atmosphera ipc plugin {op}Panel {modern}' for op in names}
        assert rows == expected, f'picker returned {rows}, expected {expected}'
        opened = f'{modern}/open'
        cli(*shlex.split(rows[opened])[1:])
        first = wait('picker-open-command-activates-panel', lambda s: len(s['visible']) == 1 and
                     s['visible'][0]['id'] == modern and s['visible'][0]['screen'] == one)['visible'][0]
        cli(*shlex.split(rows[f'{modern}/close'])[1:])
        visible('manifest-ipc-close')

        general = settings / 'general.json'
        updated = json.loads((work / 'shell/Configs/defaults.json').read_text())['general']
        updated['hotCorners']['bottomRight'] = rows[f'{modern}/toggle']
        new = general.with_suffix('.new')
        new.write_text(json.dumps(updated))
        new.replace(general)
        wait('new-corner-command-loaded', lambda s: ipc('invocationProbe', 'cornerCommand') == rows[f'{modern}/toggle'])
        probe('corner', two)
        wait('manifest-corner-opens-on-requesting-output', lambda s: len(s['visible']) == 1 and
             s['visible'][0]['id'] == modern and s['visible'][0]['screen'] == two and
             s['visible'][0]['owned'] and s['cornerFires'] == version_gate['cornerFires'] + 1)
        probe('corner', two)
        visible('manifest-corner-toggle-closes', also=lambda s: s['cornerFires'] == version_gate['cornerFires'] + 2)
        cli(*shlex.split(rows[f'{modern}/toggle'])[1:])
        wait('manifest-ipc-toggle-opens-on-current-output', lambda s: len(s['visible']) == 1 and
             s['visible'][0]['id'] == first['id'] and s['visible'][0]['screen'] == one)
        cli(*shlex.split(rows[f'{modern}/toggle'])[1:])
        visible('manifest-ipc-toggle-closes')
        probe('finish')
        return shell.wait(timeout=5)
    finally:
        # Don't wait for QS on failures: the harness reaps the private namespace.
        if shell.poll() is None:
            try:
                probe('finish')
            except (subprocess.SubprocessError, OSError):
                pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--map-plugin', type=Path, help='run the picker regression with this Windows Map plugin directory')
    add_execution_arguments(parser)
    args = parser.parse_args()
    work = args.workspace.resolve()
    check_execution_paths(parser, work, source=args.source)
    work.mkdir()
    shell = work / 'shell'
    shutil.copytree(args.source, shell, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__', '*.bak'))
    owner = probe_owner_path(shell)
    owner.write_text(inject_probe('import Quickshell.Io\nimport qs.Services.Actions\n' + owner.read_text(), PROBE))
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software')
    for key, leaf in (('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state')):
        directory = work / leaf
        directory.mkdir()
        env[key] = str(directory)
    config = work / 'config/atmosphera'
    env['ATMOSPHERA_CONFIG_DIR'] = str(config) + '/'
    states = {}
    for key in ('niri-windows-map', 'invocation-unplaced', 'invocation-panel-only'):
        plugin = config / 'plugins' / key
        if key == 'niri-windows-map' and args.map_plugin:
            shutil.copytree(args.map_plugin, plugin)
            states[key] = dict(enabled=True)
            continue
        plugin.mkdir(parents=True)
        entries = dict(panel='Panel.qml')
        extra = {}
        if key in ('niri-windows-map', 'invocation-unplaced'):
            entries['main'] = 'Main.qml'
            (plugin / 'Main.qml').write_text(MAIN)
        else:
            extra['actions'] = [dict(id=op, panel=op, label=op, description=f'{op} panel.', icon='terminal')
                                for op in ('open', 'toggle', 'close')]
        if key == 'niri-windows-map':
            entries['barWidget'] = 'Bar.qml'
            (plugin / 'Bar.qml').write_text(BAR)
        (plugin / 'Panel.qml').write_text(PANEL)
        (plugin / 'manifest.json').write_text(json.dumps(dict(
            id=key, name=key, version='1.0.0',
            minAtmospheraVersion=(shell / 'VERSION').read_text().strip(),
            author='Atmosphera',
            description='Panel invocation regression fixture.', entryPoints=entries,
            metadata=dict(settingsSchema=dict(version=1, fields={})), **extra,
        )))
        states[key] = dict(enabled=True)
    (config / 'plugins.json').write_text(json.dumps(dict(version=5, sources=[], states=states)))
    defaults = json.loads((shell / 'Configs/defaults.json').read_text())
    defaults['general']['hotCorners']['bottomRight'] = 'atmosphera ipc niriWindowsMap toggle'
    (config / 'settings.json').write_text(json.dumps(defaults))
    (config / 'settings').mkdir()
    bar = dict(defaults['bar'], widgets=dict(left=[dict(id='plugin:niri-windows-map')], center=[], right=[]))
    (config / 'settings/bar.json').write_text(json.dumps(bar))
    driver = '--drive-map' if args.map_plugin else '--drive'
    execution = run_harness(['dbus-run-session', '--', sys.executable, '-B', Path(__file__).resolve(),
                              driver, work], work, env, args.budget)
    text = (work / 'shell.log').read_text(errors='replace')
    cases = [json.loads(line.split('INVOCATION_CASE ', 1)[1]) for line in text.splitlines()
             if line.startswith('INVOCATION_CASE ')]
    errors = [line for line in text.splitlines() if ERRORS.search(line)]
    final_case = 'real-map-picker-closes' if args.map_plugin else 'manifest-ipc-toggle-closes'
    receipt = dict(passed=bool(cases and cases[-1]['name'] == final_case and not errors and execution['exit_code'] == 0),
                   cases=cases, qml_errors=errors)
    write_receipt(work, receipt, execution)
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] in ('--drive', '--drive-map'):
        raise SystemExit(exercise(Path(sys.argv[2]), real_map=sys.argv[1] == '--drive-map'))
    raise SystemExit(main())
