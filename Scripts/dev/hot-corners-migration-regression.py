#!/usr/bin/env python3
"""Registry v6: Hot Corners plugin import and removal. Assigned niri VM only.

Part 1 runs PluginProfileMigration.planV6 over synthetic inputs through
Scripts/dev/fixtures/hot-corners-migration.qml. Part 2 cold-starts one copy of
--source over private synthetic profiles (cases M1-M8) and checks each profile
after every start. Nothing outside --workspace is written.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys

from presentation_harness import check_execution_paths, run_harness, write_receipt
from qml_probe import inject_probe, probe_owner_path

REGISTRY_URL = 'https://github.com/alexindigo/atmosphera-plugins'
OTHER_URL = 'https://example.invalid/hot-corners-fork'
KEY = hashlib.sha256(REGISTRY_URL.encode()).hexdigest()[:6] + ':hot-corners'
OTHER_KEY = hashlib.sha256(OTHER_URL.encode()).hexdigest()[:6] + ':hot-corners'
CORNERS = ['topLeft', 'topRight', 'bottomLeft', 'bottomRight']
EMPTY = {corner: '' for corner in CORNERS}
ERRORS = re.compile(r'TypeError:|ReferenceError:|SyntaxError:|is not a type|Failed to load configuration')

PROBE = r'''
  property var v6LoadEvents: []
  Connections {
    target: Service
    function onPluginLoaded(pluginId) { shellRoot.v6LoadEvents = shellRoot.v6LoadEvents.concat([pluginId]); }
  }
  Timer {
    property int settled: 0
    interval: 200; running: true; repeat: true
    onTriggered: {
      if (!Settings.isLoaded || !Service.pluginsFullyLoaded) return;
      // Let the registry, settings and plugins.json writes settle before quitting.
      if (++settled < 15) return;
      stop();
      var corners = Settings.data.general.hotCorners;
      console.log("HOT_CORNERS_V6|" + JSON.stringify({loadEvents: shellRoot.v6LoadEvents,
        loaded: Object.keys(Service.loadedPlugins), states: Registry.pluginStates, pending: Registry._v6Pending,
        corners: {topLeft: corners.topLeft, topRight: corners.topRight, bottomLeft: corners.bottomLeft,
                  bottomRight: corners.bottomRight, delayMs: corners.delayMs}}));
      Qt.quit();
    }
  }
'''


def settings_text(**corners):
    return json.dumps({'corners': {name[0].upper() + name[1:]: value for name, value in corners.items()}})


def plan_cases():
    enabled, disabled = {'enabled': True, 'sourceUrl': REGISTRY_URL}, {'enabled': False, 'sourceUrl': REGISTRY_URL}
    files = lambda *keys: [f for key in keys for f in (f'settings/plugins/{key}.json', f'settings/plugins/{key}.config.json')]
    cases, expected = {}, {}

    def case(name, states, settings, core, corners, removals, warnings=0):
        cases[name] = {'states': states, 'settings': settings, 'core': core}
        expected[name] = {'corners': corners, 'removals': removals, 'files': files(*removals), 'warnings': warnings}

    case('primary', {KEY: enabled}, {KEY: {'primary': settings_text(topLeft='a', bottomRight='b', topRight=''), 'legacy': None}},
         EMPTY, {'topLeft': 'a', 'bottomRight': 'b'}, [KEY])
    case('non-string values', {KEY: enabled}, {KEY: {'primary': json.dumps({'corners': {'TopLeft': 5, 'TopRight': None,
                                                                                        'BottomLeft': ['x'], 'BottomRight': 'ok'}}),
                                                      'legacy': None}}, EMPTY, {'bottomRight': 'ok'}, [KEY])
    case('legacy only', {KEY: enabled}, {KEY: {'primary': None, 'legacy': settings_text(bottomLeft='legacy cmd')}},
         EMPTY, {'bottomLeft': 'legacy cmd'}, [KEY])
    case('primary wins', {KEY: enabled}, {KEY: {'primary': settings_text(topRight='p'), 'legacy': settings_text(topRight='l', topLeft='l2')}},
         EMPTY, {'topRight': 'p'}, [KEY])
    case('disabled', {KEY: disabled}, {KEY: {'primary': settings_text(topLeft='x'), 'legacy': None}}, EMPTY, {}, [KEY])
    case('key order', {'b:hot-corners': enabled, 'Z:hot-corners': enabled, 'a:hot-corners': enabled},
         {'b:hot-corners': {'primary': settings_text(topLeft='b1', topRight='b2'), 'legacy': None},
          'Z:hot-corners': {'primary': settings_text(topLeft='z1', topRight=''), 'legacy': None},
          'a:hot-corners': {'primary': settings_text(topLeft='', bottomLeft='a3'), 'legacy': None}},
         EMPTY, {'topLeft': 'z1', 'bottomLeft': 'a3', 'topRight': 'b2'}, ['Z:hot-corners', 'a:hot-corners', 'b:hot-corners'])
    case('core kept', {KEY: enabled}, {KEY: {'primary': settings_text(topLeft='plugin', bottomRight='br'), 'legacy': None}},
         dict(EMPTY, topLeft='keep'), {'bottomRight': 'br'}, [KEY])
    case('malformed', {KEY: enabled}, {KEY: {'primary': '{"corners": ', 'legacy': settings_text(topLeft='l')}},
         EMPTY, {}, [KEY], warnings=1)
    case('candidates', {'hot-corners': {'enabled': True, 'sourceUrl': None}, KEY + '-extra': enabled, 'x:other': enabled},
         {'hot-corners': {'primary': None, 'legacy': None}}, EMPTY, {}, ['hot-corners'])
    case('no settings', {KEY: enabled, OTHER_KEY: None}, {}, EMPTY, {}, sorted([KEY, OTHER_KEY]))
    case('nothing to do', {'x:other': enabled}, {}, EMPTY, {}, [])
    return cases, expected


def run_planner(shell, work, env):
    cases, expected = plan_cases()
    # Quickshell resolves imports inside the config root only: a private tree
    # holds the planner and the fixture, and its shell.qml loads the fixture.
    tree = work / 'planner'
    for rel in ('Helpers/PluginProfileMigration.js', 'Scripts/dev/fixtures/hot-corners-migration.qml'):
        (tree / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(shell / rel, tree / rel)
    (tree / 'shell.qml').write_text('import QtQuick\nItem { Loader { source: "Scripts/dev/fixtures/hot-corners-migration.qml" } }\n')
    result = subprocess.run(['qs', '-p', str(tree / 'shell.qml'), '--no-color'], text=True, capture_output=True, timeout=120,
                            env=dict(env, HOT_CORNERS_PLAN_CASES=json.dumps(cases)))
    text = result.stdout + result.stderr
    (work / 'planner.log').write_text(text)
    observed = {}
    for line in text.splitlines():
        if 'HOT_CORNERS_PLAN|' in line:
            name, value = line.split('HOT_CORNERS_PLAN|', 1)[1].split('|', 1)
            plan = json.loads(value)
            plan['warnings'] = len(plan['warnings'])
            observed[name] = plan
    rows = [dict(case='planner:' + name, observed=observed.get(name), expected=want, passed=observed.get(name) == want)
            for name, want in expected.items()]
    rows.append(dict(case='planner:completed', observed='HOT_CORNERS_PLAN_DONE' in text and not ERRORS.search(text),
                     expected=True, passed='HOT_CORNERS_PLAN_DONE' in text and not ERRORS.search(text)))
    return rows


MANIFEST = {'id': 'hot-corners', 'name': 'Hot Corners', 'version': '0.0.7', 'minAtmospheraVersion': '0.9.0',
            'author': 'synthetic', 'license': 'MIT', 'description': 'Synthetic v6 migration fixture.',
            'entryPoints': {'main': 'Main.qml'}, 'dependencies': {'plugins': []},
            'metadata': {'settingsSchema': {'version': 1, 'fields': {'corners': {
                'type': 'Record', 'optional': True,
                'fields': {name: {'type': 'String', 'optional': True}
                           for name in ('TopLeft', 'TopRight', 'BottomLeft', 'BottomRight')}}}}}}


class Profile:
    def __init__(self, root, name):
        self.root = root / 'profiles' / name
        self.config = self.root / 'config/atmosphera'
        for leaf in ('home', 'config/atmosphera/settings', 'data', 'cache', 'state'):
            (self.root / leaf).mkdir(parents=True)
        self.write('settings/general.json', {'showChangelogOnStartup': False})
        self.starts = 0

    def write(self, rel, value):
        path = self.config / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value if isinstance(value, str) else json.dumps(value))

    def plugin(self, key, enabled, primary=None, legacy=None):
        self.write(f'plugins/{key}/manifest.json', MANIFEST)
        self.write(f'plugins/{key}/Main.qml', 'import QtQuick\nItem {\n  property var pluginApi: null\n}\n')
        if legacy is not None:
            self.write(f'plugins/{key}/settings.json', legacy)
        if primary is not None:
            self.write(f'settings/plugins/{key}.json', primary)
        return {'enabled': enabled, 'sourceUrl': REGISTRY_URL if key == KEY else OTHER_URL}

    def plugins_json(self, states):
        self.write('plugins.json', {'version': 5, 'sources': [], 'states': states})

    def start(self, shell, base_env):
        self.starts += 1
        log = self.root / f'start-{self.starts}'
        log.mkdir()
        env = dict(base_env)
        for key, leaf in [('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                          ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state')]:
            env[key] = str(self.root / leaf)
        execution = run_harness(['dbus-run-session', '--', 'qs', '-p', str(shell), '--no-color'], log, env, 120)
        text = (log / 'shell.log').read_text(errors='replace')
        state = next((json.loads(line.split('HOT_CORNERS_V6|', 1)[1]) for line in text.splitlines()
                      if 'HOT_CORNERS_V6|' in line), None)
        return dict(execution=execution, text=text, state=state, errors=[l for l in text.splitlines() if ERRORS.search(l)])

    def plugins(self):
        return json.loads((self.config / 'plugins.json').read_text())

    def shard(self):
        stored = json.loads((self.config / 'settings/general.json').read_text()).get('hotCorners', {})
        return {corner: stored.get(corner, '') for corner in CORNERS}

    def backups(self):
        root = self.config / 'backups'
        return sorted(root.glob('plugins-v6-*')) if root.is_dir() else []

    def exists(self, rel):
        return (self.config / rel).exists()


def cold_starts(shell, root, env):
    rows = []

    def check(case, name, observed, expected):
        rows.append(dict(case=f'{case}:{name}', observed=observed, expected=expected, passed=observed == expected))

    def started(case, run):
        check(case, 'start completed', bool(run['state']) and run['execution']['exit_code'] == 0 and not run['execution']['timed_out'], True)
        check(case, 'no QML errors', run['errors'], [])

    def migrated(case, profile, run, corners, keys, backed_up):
        started(case, run)
        state = run['state'] or {}
        check(case, 'core corners', {c: (state.get('corners') or {}).get(c) for c in CORNERS}, corners)
        check(case, 'general shard', profile.shard(), corners)
        check(case, 'delayMs untouched', (state.get('corners') or {}).get('delayMs'), 200)
        plugins = profile.plugins()
        check(case, 'plugins.json version 6', plugins.get('version'), 6)
        check(case, 'states removed', sorted(k for k in plugins.get('states', {}) if k.endswith('hot-corners')), [])
        check(case, 'never loaded', [k for k in state.get('loadEvents', []) + state.get('loaded', []) if 'hot-corners' in k], [])
        check(case, 'folders and files removed', [rel for key in keys for rel in (f'plugins/{key}', f'settings/plugins/{key}.json')
                                                  if profile.exists(rel)], [])
        backups = profile.backups()
        check(case, 'one backup', len(backups), 1)
        if backups:
            held = sorted(p.relative_to(backups[0]).as_posix() for p in backups[0].rglob('*') if p.is_file())
            check(case, 'backup holds plugins.json, folders and settings', [rel for rel in backed_up if rel not in held], [])

    # M1: enabled registry install, primary settings with TL/BR.
    p = Profile(root, 'm1')
    p.plugins_json({KEY: p.plugin(KEY, True, primary=settings_text(topLeft='m1 top left', bottomRight="printf '%s' \"m1 br\""))})
    run = p.start(shell, env)
    migrated('M1', p, run, dict(EMPTY, topLeft='m1 top left', bottomRight="printf '%s' \"m1 br\""), [KEY],
             ['plugins.json', f'plugins/{KEY}/manifest.json', f'settings/plugins/{KEY}.json'])
    check('M1', 'import and removal logged', all(s in run['text'] for s in ('v6 migration: imported', 'v6 migration: removed the hot-corners plugin')), True)

    # M2: legacy settings.json only.
    p = Profile(root, 'm2')
    p.plugins_json({KEY: p.plugin(KEY, True, legacy=settings_text(topRight='m2 legacy'))})
    migrated('M2', p, p.start(shell, env), dict(EMPTY, topRight='m2 legacy'), [KEY],
             ['plugins.json', f'plugins/{KEY}/settings.json'])

    # M3: both files, different values: primary wins.
    p = Profile(root, 'm3')
    p.plugins_json({KEY: p.plugin(KEY, True, primary=settings_text(bottomLeft='m3 primary'),
                                  legacy=settings_text(bottomLeft='m3 legacy', topLeft='m3 legacy only'))})
    migrated('M3', p, p.start(shell, env), dict(EMPTY, bottomLeft='m3 primary'), [KEY],
             ['plugins.json', f'plugins/{KEY}/settings.json', f'settings/plugins/{KEY}.json'])

    # M4: disabled install with commands: nothing imported, removed and backed up.
    p = Profile(root, 'm4')
    p.plugins_json({KEY: p.plugin(KEY, False, primary=settings_text(topLeft='m4 disabled'))})
    migrated('M4', p, p.start(shell, env), EMPTY, [KEY], ['plugins.json', f'plugins/{KEY}/Main.qml', f'settings/plugins/{KEY}.json'])

    # M5: two enabled installs: first non-empty per corner in key code-unit order.
    first, second = sorted([KEY, OTHER_KEY])
    p = Profile(root, 'm5')
    p.plugins_json({second: p.plugin(second, True, primary=settings_text(topLeft='second tl', topRight='second tr')),
                    first: p.plugin(first, True, primary=settings_text(topLeft='first tl', topRight='', bottomRight='first br'))})
    migrated('M5', p, p.start(shell, env), dict(EMPTY, topLeft='first tl', topRight='second tr', bottomRight='first br'),
             [first, second], ['plugins.json', f'plugins/{first}/manifest.json', f'plugins/{second}/manifest.json',
                               f'settings/plugins/{first}.json', f'settings/plugins/{second}.json'])

    # M6: core TL already set: kept.
    p = Profile(root, 'm6')
    p.write('settings/general.json', {'showChangelogOnStartup': False, 'hotCorners': {'topLeft': 'core keeps this'}})
    p.plugins_json({KEY: p.plugin(KEY, True, primary=settings_text(topLeft='m6 plugin', bottomLeft='m6 bl'))})
    migrated('M6', p, p.start(shell, env), dict(EMPTY, topLeft='core keeps this', bottomLeft='m6 bl'), [KEY],
             ['plugins.json', f'settings/plugins/{KEY}.json'])

    # M7: malformed settings JSON: nothing imported, warning, removed.
    p = Profile(root, 'm7')
    p.plugins_json({KEY: p.plugin(KEY, True, primary='{"corners": {"TopLeft": ')})
    run = p.start(shell, env)
    migrated('M7', p, run, EMPTY, [KEY], ['plugins.json', f'settings/plugins/{KEY}.json'])
    check('M7', 'warning logged', bool(re.search(r'v6 migration:.*not valid JSON', run['text'])), True)

    # M8: backup directory not writable: nothing changes, the plugin loads; then it migrates once.
    p = Profile(root, 'm8')
    p.plugins_json({KEY: p.plugin(KEY, True, primary=settings_text(topLeft='m8 tl'))})
    backups = p.config / 'backups'
    backups.mkdir()
    backups.chmod(stat.S_IRUSR | stat.S_IXUSR)
    before = (p.config / 'plugins.json').read_bytes()
    run = p.start(shell, env)
    started('M8 locked', run)
    state = run['state'] or {}
    check('M8 locked', 'core unchanged', {c: (state.get('corners') or {}).get(c) for c in CORNERS}, EMPTY)
    check('M8 locked', 'plugins.json version 5 with the install', (p.plugins().get('version'), KEY in p.plugins().get('states', {})), (5, True))
    check('M8 locked', 'files kept', [p.exists(f'plugins/{KEY}/manifest.json'), p.exists(f'settings/plugins/{KEY}.json')], [True, True])
    check('M8 locked', 'plugin loads as before', KEY in state.get('loaded', []), True)
    check('M8 locked', 'pending kept', state.get('pending'), True)
    check('M8 locked', 'backup failure logged', 'v6 migration: backup failed' in run['text'], True)
    check('M8 locked', 'no backup written', p.backups(), [])
    check('M8 locked', 'plugins.json content unchanged', json.loads((p.config / 'plugins.json').read_bytes()), json.loads(before))
    backups.chmod(stat.S_IRWXU)
    run = p.start(shell, env)
    migrated('M8 restored', p, run, dict(EMPTY, topLeft='m8 tl'), [KEY], ['plugins.json', f'settings/plugins/{KEY}.json'])
    after = (p.config / 'plugins.json').read_bytes()
    shard = p.shard()
    run = p.start(shell, env)
    started('M8 again', run)
    check('M8 again', 'no migration work', 'v6 migration' in run['text'], False)
    check('M8 again', 'profile unchanged', (json.loads((p.config / 'plugins.json').read_bytes()), p.shard(), len(p.backups())),
          (json.loads(after), shard, 1))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--workspace', type=Path, required=True)
    args = parser.parse_args()
    work = args.workspace.resolve()
    check_execution_paths(parser, work, source=args.source)
    work.mkdir()
    shell = work / 'shell'
    shutil.copytree(args.source, shell, ignore=shutil.ignore_patterns('.git', '.envrc', '.qmlls.ini', '__pycache__', '*.bak'))
    owner = probe_owner_path(shell)
    owner.write_text('import qs.Services.Plugins\n' + inject_probe(owner.read_text(), PROBE))
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', DISPLAY='',
               ATMOSPHERA_UPGRADELOG_URL='http://127.0.0.1:9')
    rows = run_planner(shell, work, env)
    rows += cold_starts(shell, work, env)
    failures = [row for row in rows if not row['passed']]
    receipt = dict(passed=not failures, cases=len(rows), failures=failures)
    (work / 'cases.json').write_text(json.dumps(rows, indent=2))
    execution = dict(exit_code=0 if not failures else 1, timed_out=False, cleanup_complete=True)
    write_receipt(work, receipt, execution)
    print(json.dumps(dict(passed=receipt['passed'], cases=len(rows), failures=failures), indent=2))
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
