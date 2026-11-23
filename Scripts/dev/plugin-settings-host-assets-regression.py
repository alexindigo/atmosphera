#!/usr/bin/env python3
"""Scoped plugin Settings contract witnesses. Execute only in the named guest.

Focused witnesses run in-process. The plan's registry cases (static, nesting,
routes, desktop-plugins, catalog, assets, lint and all) run the existing
qualified drivers in order, each in fresh roots under its own run lock. A
partial characterization can never produce RED_CONTROLS or overall PASS.
"""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from fixture_resources import FixtureResources
from guest_profile import ProcessIdentity, activate_profile, profile_argument


RED_IDS = ('P001', 'P048', 'P054', 'P055', 'P056', 'P143', 'P161', 'P169', 'G81.generic')
RED_PLUGINS = dict(P048='git-companion', P054='air-quality', P055='arch-updater',
                   P056='github-contributions', P143='github-contributions', P161='air-quality')


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def input_fingerprints(args):
    def selected(root, names):
        return {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                for name in names if (root / name).is_file()}
    fixtures = ['Scripts/dev/' + Path(__file__).name, 'Scripts/dev/fixtures/plugin-settings-fields-native.qml'] + [str(path.relative_to(args.source)) for path in
                sorted((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-host-*')) if path.is_file()]
    result = dict(harness=selected(args.source, fixtures))
    if os.environ.get('PHA_INPUT_INJECTOR'):
        injector = Path(os.environ['PHA_INPUT_INJECTOR'])
        result['inputInjector'] = dict(path=str(injector), sha256=hashlib.sha256(injector.read_bytes()).hexdigest())
    result['candidateShell'] = selected(args.source, [
        'Scripts/python/src/settings/plugin-schema.py', 'Configs/plugin-settings-overlays.json',
        'Services/Plugins/PluginInstances.qml', 'Services/Plugins/PluginPreferenceEditor.qml',
        'Services/Plugins/PluginSettingsPageApi.qml', 'Services/Plugins/PluginSettingsSession.qml',
        'Services/Plugins/PluginSettingsFields.qml', 'Services/Plugins/PluginInstanceApi.qml',
        'Services/Plugins/PluginSettingsRead.js', 'Services/Plugins/PluginContract.js',
        'Services/Plugins/PluginView.qml', 'Services/Plugins/Service.qml',
        'Services/Plugins/PluginLoader.qml', 'Widgets/NPluginSettingsPopup.qml',
        'Widgets/NPluginSettingsField.qml', 'Widgets/NTextInputButton.qml',
        'Services/UI/DesktopWidgetRegistry.qml',
        'Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml'])
    result['candidatePlugins'] = selected(args.plugins, [
        plugin + '/' + name for plugin in ('todo', 'git-companion', 'air-quality', 'arch-updater', 'github-contributions', 'pomodoro')
        for name in ('manifest.json', 'Settings.qml', 'Main.qml', 'DesktopWidget.qml', 'Panel.qml')])
    if args.baseline_source:
        result['baselineShell'] = selected(args.baseline_source, [
            'Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml',
            'Widgets/NPluginSettingsPopup.qml', 'Widgets/NToggle.qml',
            'Services/Plugins/PluginLoader.qml', 'Services/Plugins/PluginSettingsPageApi.qml',
            'Services/UI/SettingsPanelService.qml', 'Modules/Panels/Settings/SettingsContent.qml'])
    if args.baseline_plugins:
        result['baselinePlugins'] = selected(args.baseline_plugins, [
            plugin + '/' + name for plugin in ('todo', 'git-companion', 'air-quality', 'arch-updater', 'github-contributions', 'pomodoro')
            for name in ('manifest.json', 'Settings.qml', 'Main.qml', 'DesktopWidget.qml', 'Panel.qml')])
    return result


def seed_todo(case, plugins):
    for name in ('config/settings/plugins', 'cache', 'state'):
        (case / name).mkdir(parents=True)
    shutil.copytree(plugins / 'todo', case / 'config/plugins/todo')
    write_json(case / 'config/settings.json', {'settingsVersion': 62})
    write_json(case / 'config/plugins.json', {'version': 6, 'states': {}, 'sources': []})
    tasks = [dict(id=i, text='synthetic task ' + str(i), completed=False,
                  createdAt='2026-11-19', pageId=7, priority='medium', details='',
                  opaque={'keep': True}) for i in (1, 2)]
    values = dict(todos=tasks, pages=[dict(id=0, name='General'), dict(id=7, name='Synthetic')],
                  current_page_id=7, count=2, completedCount=0, isExpanded=True,
                  opaque={'keep': True})
    path = case / 'config/settings/plugins/todo.json'
    write_json(path, values)
    return path, values


def remove_completed_installs(case, output):
    """Retain receipts/configurations, not rebuildable per-run shell copies.

    Only call after the complete case (including cold readers) has finished.
    Failed cases keep their input copy for diagnosis. Source/baseline exports
    are outside these exclusively created case roots and are never selected.
    """
    removed = []
    for parent, directories, _ in os.walk(case):
        if 'install' not in directories:
            continue
        directories.remove('install')
        install = Path(parent) / 'install'
        if not (install / 'shell.qml').is_file() or not (install / 'Scripts/dev').is_dir():
            continue
        if install.is_symlink() or install.resolve() != install or not install.is_relative_to(case) or (install / '.git').exists():
            raise RuntimeError('completed-install cleanup refused an unowned path')
        removed.append(str(install))
        shutil.rmtree(install)
    write_json(output / 'install-cleanup.json', dict(removed=removed, retained='receipts, isolated configuration and source fingerprints'))


def run_fixture(profile, install, case, output, fixture, installed=False, extra_env=None, extra_lint=(), timeout=60):
    target = fixture if installed else install / fixture.name
    if not installed:
        shutil.copy2(fixture, target)
    # Existing ProbeFiles contract: the sentinel asks Quickshell to generate its
    # actual qs module universe. Do not lint against unresolved qs imports.
    qmlls = install / '.qmlls.ini'
    if not qmlls.exists():
        qmlls.touch(exist_ok=False)
    # The named workspace already uses most of sockaddr_un's 108-byte path.
    # Qt reserves two trailing/leading bytes even for pathname sockets on Linux
    # (qlocalserver_unix.cpp). An empty caller prefix retains the existing
    # private disk runtime while fitting Quickshell's variable-length instance ID.
    env = dict(os.environ, **profile.child_environment(''))
    env.update(ATMOSPHERA_CONFIG_DIR=str(case / 'config'),
               ATMOSPHERA_SETTINGS_FILE=str(case / 'config/settings.json'),
               ATMOSPHERA_CACHE_DIR=str(case / 'cache'),
               ATMOSPHERA_STATE_DIR=str(case / 'state'), QML_DISABLE_DISK_CACHE='1')
    env.update(extra_env or {})
    try:
        with (output / 'runtime.log').open('w') as log, FixtureResources() as resources:
            process = resources.spawn(['qs', '-p', str(target), '--no-color'], env=env,
                                      stdout=log, stderr=subprocess.STDOUT, timeout=10)
            code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError('fixture exceeded deadline; owned child joined, exit=' + str(process.returncode)) from error
    (output / 'runtime.exit').write_text(str(code) + '\n')
    text = (output / 'runtime.log').read_text()
    if code != 0:
        raise RuntimeError('actual fixture failed; see runtime.log, exit=' + str(code))
    if 'Failed to start IPC server' in text:
        raise RuntimeError('Quickshell IPC socket unavailable; see runtime.log')
    vfs = list((Path(env['XDG_RUNTIME_DIR']) / 'quickshell/vfs').iterdir())
    if len(vfs) != 1:
        raise RuntimeError('actual Quickshell lint universe missing or ambiguous')
    lint = subprocess.run(['bash', str(install / 'Scripts/dev/qmllint.sh'), str(target)] + [str(path) for path in extra_lint],
                          env=dict(env, QS_VFS=str(vfs[0])), cwd=install,
                          capture_output=True, text=True, timeout=120)
    (output / 'lint.log').write_text(lint.stdout + lint.stderr)
    if lint.returncode != 0:
        raise RuntimeError('fixture lint failed in the actual qs/native universe; see lint.log')
    profile.verify()
    return text


def startup(args, profile):
    """Run the complete production entry, with only an owned exit observation."""
    case, out = args.work_root / 'startup', args.output / 'startup'
    case.mkdir()
    out.mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install,
                    ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for name in ('config/settings', 'cache', 'state'):
        (case / name).mkdir(parents=True)
    write_json(case / 'config/settings.json', {'settingsVersion': 62})
    write_json(case / 'config/plugins.json', {'version': 6, 'states': {}, 'sources': []})
    entry = install / 'shell.qml'
    original = entry.read_text()
    # Disposable diagnostic mini-plan: observe the original bootstrap and full
    # ShellSession Loader; name that existing loader and append an exit timer;
    # canonical sources are untouched and the exact original hash is recorded.
    needle = '  Loader {\n'
    if original.count(needle) != 1 or not original.endswith('}\n'):
        raise RuntimeError('production entry changed; review cold observation insertion')
    observed = original.replace(needle, needle + '    id: coldSession\n', 1)
    observed = observed[:-2] + '''  Timer {
    interval: 12000
    running: true
    onTriggered: {
      if (!bootstrap.ready || coldSession.status !== Loader.Ready || !coldSession.item) {
        console.error("PLUGIN_SETTINGS_FULL_SHELL: FAIL (bootstrap/session)");
        Qt.exit(2);
        return;
      }
      console.log("PLUGIN_SETTINGS_FULL_SHELL: STARTED");
      Qt.exit(0);
    }
  }
}
'''
    entry.write_text(observed)
    text = run_fixture(profile, install, case, out, entry, installed=True)
    if 'PLUGIN_SETTINGS_FULL_SHELL: STARTED' not in text:
        raise RuntimeError('full shell startup endpoint missing')
    errors = [line for line in text.splitlines() if any(marker in line for marker in
              ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'is not installed',
               'Failed to start IPC server', 'Failed to load configuration'))]
    result = dict(id='startup', status='PASS' if not errors else 'FAIL',
                  fullProductionEntry=True, bootstrapReady=True, shellSessionReady=True,
                  originalEntrySha256=hashlib.sha256(original.encode()).hexdigest(), diagnostics=errors)
    stage_receipt(out / 'result.json', result)
    print('CASE startup: ' + result['status'], flush=True)
    return result


def metadata_case(args, profile):
    case, out = args.work_root / 'metadata', args.output / 'metadata'
    case.mkdir()
    out.mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install,
                    ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    path, _ = seed_todo(case, args.plugins)
    before = path.read_bytes()
    text = run_fixture(profile, install, case, out,
                       args.source / 'Scripts/dev/fixtures/plugin-settings-host-metadata.qml')
    if 'PLUGIN_SETTINGS_METADATA: NATIVE_READY' not in text or before != path.read_bytes():
        raise RuntimeError('candidate metadata/native owner endpoint mismatch')
    result = dict(id='metadata', status='PASS', declaredFields=True, nativeOwnerOpened=True,
                  nativeUntouchedApply='nothing_to_save', sharedBytesUnchanged=True,
                  productionPageProtection=False)
    stage_receipt(out / 'result.json', result)
    print('CASE metadata: PASS (compiler only; P001 protection pending)', flush=True)
    return result


def fields_case(args, profile):
    case, out = args.work_root / 'fields', args.output / 'fields'
    case.mkdir()
    out.mkdir()
    results = []
    for family in ('global-bar', 'monitor-bar', 'control-center', 'desktop'):
        selected_case, selected_out = case / family, out / family
        selected_case.mkdir()
        selected_out.mkdir()
        results.append(fields_family(args, profile, selected_case, selected_out, family))
    result = dict(id='fields', status='PASS', placementFamilies=results, productionPageAdoption=False,
                  pluginScopeReset='pending final shared-scope field unit')
    stage_receipt(out / 'result.json', result)
    print('CASE fields: PASS (four native placement families; adapter gate, not page adoption)', flush=True)
    return result


def fields_family(args, profile, case, out, family):
    install = case / 'install'
    shutil.copytree(args.source, install,
                    ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    shared, _ = seed_todo(case, args.plugins)
    before = shared.read_bytes()
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-fields-native.qml'
    env = {'PHA_FIELDS_FAMILY': family}
    text = run_fixture(profile, install, case, out, fixture, extra_env=env)
    bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
    if 'PLUGIN_SETTINGS_FIELDS: NATIVE_OPERATIONS_COMPLETE' not in text or shared.read_bytes() != before or any(marker in text for marker in bad):
        raise RuntimeError('native fields endpoint or exact shared-byte preservation failed')
    shard = 'bar' if family in ('global-bar', 'monitor-bar') else 'controlCenter' if family == 'control-center' else 'desktopWidgets'
    stored = json.loads((case / ('config/settings/' + shard + '.json')).read_text())
    rows = (stored['widgets']['left'] if family == 'global-bar' else
            stored['screenOverrides'][0]['widgets']['left'] if family == 'monitor-bar' else
            stored['shortcuts']['left'] if family == 'control-center' else stored['monitorWidgets'][0]['widgets'])
    expected = {'todos', 'pages', 'current_page_id', 'count', 'completedCount', 'opaque'}
    overrides = rows[0]['instanceSettings']
    if set(overrides) != expected or overrides['opaque'] != dict(keep='legacy') or overrides['todos'][0]['id'] != 91:
        raise RuntimeError('independent field Reset protected-content/opaque readback mismatch')
    if 'instanceSettings' in rows[1]:
        raise RuntimeError('native field intent reached sibling placement')
    cold = out / 'cold'
    cold.mkdir()
    text = run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_FIELDS_COLD='1'))
    if 'PLUGIN_SETTINGS_FIELDS: COLD_PASS' not in text or shared.read_bytes() != before or any(marker in text for marker in bad):
        raise RuntimeError('separate native field cold consumer failed')
    result = dict(id=family, status='PASS', actualNativeEditor=True,
                  instanceFieldIntent=True, instanceFieldAndWholeReset=True,
                  compoundReadIsolation=True, legacyContentAndOpaquePreserved=True,
                  sharedBytesUnchanged=True, siblingOverridesAbsent=True,
                  separateColdConsumer=True, productionPageAdoption=False,
                   pluginScopeReset='pending final shared-scope field unit')
    stage_receipt(out / 'result.json', result)
    print('CASE fields.' + family + ': PASS (native instance adapter; page adoption not certified)', flush=True)
    return result


def red_todo(args, profile):
    case, out = args.work_root / 'P001', args.output / 'P001'
    case.mkdir()
    out.mkdir()
    install = case / 'install'
    shutil.copytree(args.baseline_source, install,
                    ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    path, before = seed_todo(case, args.baseline_plugins)
    before_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    text = run_fixture(profile, install, case, out,
                       args.source / 'Scripts/dev/fixtures/plugin-settings-host-red-todo.qml')
    if 'RED_CONTROL P001: REPRODUCED' not in text:
        raise RuntimeError('P001 consumer marker missing')
    after = json.loads(path.read_text())
    if after.get('todos') != [] or after.get('pages') != [dict(id=0, name='General')]:
        raise RuntimeError('P001 independent persisted readback did not reproduce loss')
    if after.get('current_page_id') != 0 or after.get('opaque') != before['opaque']:
        raise RuntimeError('P001 persisted endpoint differs from characterized boundary')
    cold = out / 'cold'
    cold.mkdir()
    text = run_fixture(profile, install, case, cold,
                       args.source / 'Scripts/dev/fixtures/plugin-settings-host-red-todo.qml',
                       extra_env={'PHA_RED_COLD': '1'})
    if 'RED_CONTROL P001: COLD_REPRODUCED' not in text:
        raise RuntimeError('P001 separate cold consumer did not confirm persisted loss')
    result = dict(id='P001', status='REPRODUCED', beforeSha256=before_hash,
                  afterSha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                  beforeTasks=len(before['todos']), afterTasks=len(after['todos']),
                  nativeSave=True, mainAndDesktopObserved=True, persistedReadback=True,
                  separateColdConsumers=True)
    stage_receipt(out / 'result.json', result)
    print('RED_CONTROL P001: REPRODUCED', flush=True)
    return result


def todo_case(args, profile):
    case, out = args.work_root / 'todo', args.output / 'todo'
    case.mkdir()
    out.mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    shared, _ = seed_todo(case, args.plugins)
    before = shared.read_bytes()
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-host-todo.qml'
    bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
    observations = out / 'persisted'
    observations.mkdir()
    env = dict(PHA_TODO_DISK_PROBE=str(args.source / 'Scripts/dev/fixtures/plugin-settings-host-todo-disk.py'),
               PHA_TODO_SHARED_SHA256=hashlib.sha256(before).hexdigest(), PHA_TODO_OBSERVATIONS=str(observations))
    try:
        text = run_fixture(profile, install, case, out, fixture, extra_env=env)
    finally:
        (case / 'config/settings').chmod(0o755)
    if 'PLUGIN_SETTINGS_TODO: NATIVE_OPERATIONS_COMPLETE' not in text or any(item in text for item in bad):
        raise RuntimeError('actual Todo page/route/runtime gate failed')
    if shared.read_bytes() != before:
        raise RuntimeError('Todo instance operations changed shared bytes')
    rows = json.loads((case / 'config/settings/desktopWidgets.json').read_text())['monitorWidgets'][0]['widgets']
    expected = dict(todos=[dict(id=91, text='legacy task', completed=False, pageId=0, priority='medium', details='')],
                    pages=[dict(id=0, name='Legacy')], current_page_id=0, count=1, completedCount=0, opaque=dict(keep='legacy'))
    if rows != [dict(id='plugin:todo', tag='keep', instanceSettings=expected), dict(id='plugin:todo')]:
        raise RuntimeError('independent Todo protected/opaque/sibling/config Reset readback failed')
    cold = out / 'cold'
    cold.mkdir()
    text = run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_TODO_COLD='1'))
    if 'PLUGIN_SETTINGS_TODO: COLD_PASS' not in text or any(item in text for item in bad) or shared.read_bytes() != before:
        raise RuntimeError('separate cold Todo Main/Desktop consumer failed')
    expected_observations = {str(route) + '-' + phase + '.json' for route in (0, 1)
                             for phase in ('untouched', 'discard', 'apply', 'field-reset', 'failed', 'retry', 'reset')}
    if {path.name for path in observations.iterdir()} != expected_observations:
        raise RuntimeError('missing independent intermediate persisted endpoint')
    result = dict(id='todo', status='PASS', actualRuntimeRegistry=True, actualDesktopListGear=True,
                  untouchedClose=True, configDiscard=True, configApply=True, wholeConfigurationReset=True,
                  sharedBytesPreserved=True, legacyAndOpaquePreserved=True, coldMainAndDesktop=True,
                  genuineControlInput=True, fieldReset=True, realIoFailureAndRetry=True, intermediatePersistedReadbacks=14,
                  completeCatalog=False, inheritedDesktopConstructionDiagnosticNotExercised=True)
    stage_receipt(out / 'result.json', result)
    print('CASE todo: PASS (two real routes, keyboard input, IO Retry, Reset, protected bytes and cold consumers; catalog still pending)', flush=True)
    return result


def input_case(args, profile):
    case, out = args.work_root / 'input', args.output / 'input'
    case.mkdir()
    out.mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for part in ('config', 'cache', 'state'):
        (case / part).mkdir()
    fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-host-input.qml'
    text = run_fixture(profile, install, case, out, fixture)
    if 'PLUGIN_SETTINGS_INPUT: PASS' not in text or any(item in text for item in ('TypeError:', 'ReferenceError:', 'SyntaxError:')):
        raise RuntimeError('real input canary failed')
    injector = Path(os.environ['PHA_INPUT_INJECTOR'])
    if not injector.resolve().is_relative_to(profile.work_base):
        raise RuntimeError('injector is outside the task workspace')
    result = dict(id='input', status='PASS', injector=str(injector), sha256=hashlib.sha256(injector.read_bytes()).hexdigest(),
                  literalSlash=True, nativeTextField=True, nativeModalField=True, shiftedPunctuationAndCase=True,
                  nativeButton=True, namedEscape=True, namedSpace=True, controlA=True)
    stage_receipt(out / 'result.json', result)
    print('CASE input: PASS (real Wayland input and control canaries)', flush=True)
    return result


def red_consumer(args, profile, finding):
    plugin = RED_PLUGINS[finding]
    case, out = args.work_root / finding, args.output / finding
    case.mkdir()
    out.mkdir()
    install = case / 'install'
    shutil.copytree(args.baseline_source, install,
                    ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for name in ('config/settings/plugins', 'cache', 'state', 'bin'):
        (case / name).mkdir(parents=True)
    shutil.copytree(args.baseline_plugins / plugin, case / 'config/plugins' / plugin)
    write_json(case / 'config/settings.json', {'settingsVersion': 62})
    write_json(case / 'config/plugins.json', {'version': 6, 'states': {}, 'sources': []})
    endpoint_source = args.source / 'Scripts/dev/fixtures/plugin-settings-host-endpoint.py'
    for name in ('curl', 'gh', 'glab', 'plugin-settings-endpoint'):
        endpoint = case / 'bin' / name
        shutil.copy2(endpoint_source, endpoint)
        endpoint.chmod(0o700)
    endpoint = str(case / 'bin/plugin-settings-endpoint')
    if plugin == 'air-quality':
        before = dict(useNoctaliaLocation=False, customLatitude='1', customLongitude='2',
                      aqiScale='us', dataSource='open-meteo', aqicnToken='', refreshInterval=120)
        changed_key, changed_value = 'customLatitude', '' if finding == 'P161' else '3'
    elif plugin == 'github-contributions':
        before = dict(username='synthetic-alpha', token='', weeksShown=12, refreshInterval=360)
        changed_key, changed_value = 'username', '' if finding == 'P143' else 'synthetic-beta'
    elif plugin == 'arch-updater':
        before = dict(systemCmd=endpoint + ' system-old', aurCmd=endpoint + ' aur-empty',
                      updateCmd=endpoint + ' forbidden-update', flatpak=False, toast=False,
                      refreshInterval=720)
        changed_key, changed_value = 'systemCmd', endpoint + ' system-new'
    else:
        before = dict(platform='github', repo='synthetic/alpha', group='', refreshInterval=90)
        changed_key, changed_value = 'repo', 'synthetic/beta'
    path = case / 'config/settings/plugins' / (plugin + '.json')
    before['opaque'] = dict(keep=True)
    write_json(path, before)
    before_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    calls_path = out / 'endpoint-calls.jsonl'
    text = run_fixture(profile, install, case, out,
                       args.source / 'Scripts/dev/fixtures/plugin-settings-host-red-consumers.qml',
                       extra_env=dict(PHA_FINDING=finding, PHA_PLUGIN=plugin, PHA_ENDPOINT=endpoint,
                                      PHA_CALLS=str(calls_path), PATH=str(case / 'bin') + ':' + os.environ['PATH']))
    if 'RED_CONTROL ' + finding + ': REPRODUCED' not in text:
        raise RuntimeError(finding + ' real consumer marker missing')
    after = json.loads(path.read_text())
    if after.get(changed_key) != changed_value or after.get('opaque') != before['opaque']:
        raise RuntimeError(finding + ' independent persisted endpoint mismatch')
    calls = [json.loads(line) for line in calls_path.read_text().splitlines()]
    if not calls or any(c['endpoint'] not in ('curl', 'gh', 'glab', 'plugin-settings-endpoint') for c in calls):
        raise RuntimeError(finding + ' inert endpoint evidence missing')
    result = dict(id=finding, status='REPRODUCED', plugin=plugin,
                  beforeSha256=before_hash, afterSha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                  nativeSave=True, actualMain=True, desktopConstructed=True,
                  observedConsumer='panel-result-row' if finding == 'P048' else 'desktop', persistedReadback=True,
                  endpointCalls=len(calls), realWaylandTyping=finding == 'P048')
    stage_receipt(out / 'result.json', result)
    print('RED_CONTROL ' + finding + ': REPRODUCED', flush=True)
    return result


def red_navigation(args, profile):
    case, out = args.work_root / 'G81.generic', args.output / 'G81.generic'
    case.mkdir()
    out.mkdir()
    install = case / 'install'
    shutil.copytree(args.baseline_source, install,
                    ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    path, before = seed_todo(case, args.baseline_plugins)
    before_bytes = path.read_bytes()
    text = run_fixture(profile, install, case, out,
                       args.source / 'Scripts/dev/fixtures/plugin-settings-host-red-navigation.qml')
    if 'RED_CONTROL G81.generic: REPRODUCED' not in text:
        raise RuntimeError('G81.generic actual navigation marker missing')
    if path.read_bytes() != before_bytes:
        raise RuntimeError('G81.generic unexpectedly published shared preferences')
    placed = json.loads((case / 'config/settings/desktopWidgets.json').read_text())
    if 'instanceSettings' in placed['monitorWidgets'][0]['widgets'][0]:
        raise RuntimeError('G81.generic unexpectedly published placement preferences')
    result = dict(id='G81.generic', status='REPRODUCED', actualServiceNavigation=True,
                  actualPageDestroyed=True, directCloseRefused=True,
                  sharedBytesUnchanged=True, placementOverridesAbsent=True)
    stage_receipt(out / 'result.json', result)
    print('RED_CONTROL G81.generic: REPRODUCED', flush=True)
    return result


# The guest system interpreter carries pyatspi; the check virtualenv on PATH does not.
A11Y_PYTHON = '/usr/bin/python3'


def red_input(args, profile):
    subprocess.run([A11Y_PYTHON, '-c', 'import pyatspi'], check=True)
    case, out = args.work_root / 'P169', args.output / 'P169'
    case.mkdir()
    out.mkdir()
    install = case / 'install'
    shutil.copytree(args.baseline_source, install,
                    ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
    for name in ('config/settings/plugins', 'cache', 'state'):
        (case / name).mkdir(parents=True)
    shutil.copytree(args.baseline_plugins / 'pomodoro', case / 'config/plugins/pomodoro')
    write_json(case / 'config/settings.json', {'settingsVersion': 62})
    write_json(case / 'config/plugins.json', {'version': 6, 'states': {}, 'sources': []})
    before = dict(autoStartBreaks=False, autoStartWork=False, compactMode=False, playSound=True,
                  opaque=dict(keep=True))
    path = case / 'config/settings/plugins/pomodoro.json'
    write_json(path, before)
    text = run_fixture(profile, install, case, out,
                       args.source / 'Scripts/dev/fixtures/plugin-settings-host-red-input.qml',
                       extra_env=dict(QT_LINUX_ACCESSIBILITY_ALWAYS_ON='1', QT_FORCE_STDERR_LOGGING='1',
                                      PHA_A11Y_PYTHON=A11Y_PYTHON,
                                      PHA_A11Y_PROBE=str(args.source / 'Scripts/dev/fixtures/plugin-settings-host-a11y.py'),
                                      PHA_A11Y_RESULT=str(out / 'a11y.json')))
    if 'RED_CONTROL P169: REPRODUCED' not in text or text.count('P169_KEYBOARD_NO_INTENT:') != 4:
        raise RuntimeError('P169 actual keyboard/consumer markers missing')
    accessibility = json.loads((out / 'a11y.json').read_text())
    if len(accessibility['controls']) != 4 or any(c['actions'] for c in accessibility['controls']):
        raise RuntimeError('P169 actual accessibility action evidence mismatch')
    after = json.loads(path.read_text())
    if any(after.get(key) != value for key, value in before.items()):
        raise RuntimeError('P169 independent persisted consumer mismatch')
    result = dict(id='P169', status='REPRODUCED', actualPomodoroPage=True, actualMain=True,
                  keyboardControls=4, inaccessibleToggleActions=4, liveKeyboardCanary=True,
                  liveAtspiPressCanary=True, nativeApply=True, persistedReadback=True)
    stage_receipt(out / 'result.json', result)
    print('RED_CONTROL P169: REPRODUCED', flush=True)
    return result


FINAL_CASES = ('startup', 'static', 'red', 'nesting', 'routes', 'desktop-plugins', 'catalog', 'assets', 'lint')
CATALOG_COHORT = 16
# Plan section 6 matrix rows -> the existing qualified drivers that observe them.
# Each driver runs its own default (complete positive) mode in fresh roots and
# takes the per-run workspace lock itself; controls stay in their own units.
CASE_DRIVERS = {
    'nesting': ('values', 'shared-fields', 'shared-native', 'lifetime', 'session', 'context-incarnation',
                'context-lifetime', 'loader', 'chrome'),
    'routes': ('entry-routes', 'shared-routes'),
    'desktop-plugins': ('p001-safety', 'todo-export', 'selected-git', 'git-matrix', 'selected-air', 'selected-arch',
                        'selected-contributions', 'selected-catwalk', 'worker-matrix', 'catwalk-matrix'),
    'catalog': ('catalog-metadata', 'input'),
    'assets': ('music-action',),
}


def generic_entries(plugins):
    return sorted(path.parent.name for path in plugins.glob('*/manifest.json')
                  if json.loads(path.read_text()).get('entryPoints', {}).get('settings'))


def final_steps(args, case):
    """Ordered (name, argv, cwd, timeout) for one registry case."""
    dev = args.source / 'Scripts/dev'
    out = args.output / case
    def driver(name, *extra, timeout=1800):
        script = dev / ('plugin-settings-' + name.split(':')[0] + '-regression.py')
        usage = subprocess.run(['python3', '-B', str(script), '--help'], capture_output=True, text=True, cwd=args.source).stdout
        root = name.replace(':', '-')
        argv = ['python3', '-B', str(script), '--guest-profile', str(args.guest_profile), '--source', str(args.source)]
        if '--plugins' in usage:  # some drivers use a reviewed synthetic page only
            argv += ['--plugins', str(args.plugins)]
        return (name, argv + ['--work-root', str(args.work_root / case / root), '--output', str(out / root)] + list(extra),
                args.source, timeout)
    steps = []
    if case == 'static':
        for check in sorted(dev.glob('plugin-settings-*-check.py')):
            usage = subprocess.run(['python3', '-B', str(check), '--help'], capture_output=True, text=True, cwd=args.source).stdout
            argv = ['python3', '-B', str(check)]
            for option, value in (('--source', args.source), ('--plugins', args.plugins), ('--report', out / (check.stem + '.json'))):
                if option in usage:
                    argv += [option, str(value)]
            if '--selftest' in usage:
                argv.append('--selftest')
            steps.append((check.stem, argv, args.source, 300))
        steps.append(('consumer-inventory', ['python3', '-B', str(dev / 'plugin-settings-consumer-inventory.py'), '--plugins', str(args.plugins),
                                             '--output', str(out / 'consumer-inventory.json'), '--inventory',
                                             str(args.source / 'docs/development/plugin-settings-consumer-inventory.md'), '--check', '--selftest'], args.source, 300))
        steps.append(('settings-contracts', ['python3', '-B', str(dev / 'settings-contract-check.py')], args.source, 1200))
    elif case == 'lint':
        steps.append(('qmllint-core', ['bash', 'Scripts/dev/qmllint.sh', 'Services/Plugins', 'Widgets/NPluginSettingsPopup.qml',
                                       'Widgets/NPluginSettingsField.qml', 'Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml'],
                      args.source, 600))
        if args.baseline_source and args.baseline_plugins:
            # The core subset above is not permission to omit other changed QML.
            steps.append(('changed-qml', ['python3', '-B', str(dev / 'plugin-settings-changed-lint.py'), '--guest-profile', str(args.guest_profile),
                                          '--source', str(args.source), '--plugins', str(args.plugins),
                                          '--baseline-source', str(args.baseline_source), '--baseline-plugins', str(args.baseline_plugins),
                                          '--work-root', str(args.work_root / case / 'changed-qml'), '--output', str(out / 'changed-qml')],
                          args.source, 3600))
    elif case == 'nesting':
        steps += [driver(name) for name in CASE_DRIVERS[case]]
        if args.baseline_source:
            steps.append(driver('focus', '--baseline-ntoggle', str(args.baseline_source / 'Widgets/NToggle.qml')))
    elif case == 'routes' and args.baseline_source:
        steps += [driver(name) for name in CASE_DRIVERS[case]]
        red_log = args.output / 'red/G81.generic/runtime.log'
        for presentation in ('window', 'attached', 'centered'):
            steps.append(driver('navigation:' + presentation, '--baseline-source', str(args.baseline_source),
                                '--baseline-log', str(red_log), '--presentation', presentation))
    elif case == 'catalog':
        for name in CASE_DRIVERS[case]:
            # The injector was validated in main(): a task-owned executable under the guest work root.
            steps.append(driver(name, *(('--injector', os.environ['PHA_INPUT_INJECTOR']) if name == 'input' else ())))
        steps.append(driver('catalog-budget', '--mode', 'ordinary'))
        ids = generic_entries(args.plugins)
        for index in range(0, len(ids), CATALOG_COHORT):
            cohort = ids[index:index + CATALOG_COHORT]
            steps.append(driver('catalog-pages:' + str(index // CATALOG_COHORT + 1), '--ids', ','.join(cohort), timeout=60 + 40 * len(cohort)))
    elif case == 'assets':
        steps += [driver(name) for name in CASE_DRIVERS[case]]
        steps.append(('music-search-assets', ['python3', '-B', '-m', 'unittest', '-v', 'tests/music-search/test_download_limit.py'], args.plugins, 900))
    elif case == 'desktop-plugins':
        for name in CASE_DRIVERS[case]:
            # Inherited original-widget diagnostics are characterized against the pinned baseline.
            extra = ('--baseline-plugins', str(args.baseline_plugins)) if name == 'git-matrix' and args.baseline_plugins else ()
            steps.append(driver(name, *extra))
    else:
        steps += [driver(name) for name in CASE_DRIVERS[case]]
    return steps


def step_leftovers(markers):
    """Processes of this user, other than this runner, still naming a step root."""
    found = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit() or int(entry.name) == os.getpid():
            continue
        try:
            if entry.stat().st_uid != os.getuid():
                continue
            text = (entry / 'cmdline').read_bytes() + b'\0' + (entry / 'environ').read_bytes()
        except OSError:
            continue
        if any(marker.encode() in text for marker in markers):
            found.append(ProcessIdentity.read(int(entry.name)).record())
    return found


def retire_step_runtime(profile, before, keep):
    """Preserve a finished step's Quickshell logs, then retire its generated runtime roots.

    Only roots created during the step whose processes have all exited are
    selected; each launch otherwise leaves ~700 cache entries behind.
    """
    created = [path for path in sorted(set(profile.runtime_base.iterdir()) - before)
               if path.is_dir() and not path.is_symlink() and path.resolve().parent == profile.runtime_base.resolve()]
    if not created or step_leftovers([str(path) for path in created]):
        return
    manifest = {}
    for path in created:
        for log in path.glob('quickshell/by-id/*/log.*'):
            if log.is_file():
                target = keep / path.name / log.relative_to(path)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(log, target)
                manifest[str(target.relative_to(keep))] = hashlib.sha256(target.read_bytes()).hexdigest()
                if hashlib.sha256(log.read_bytes()).hexdigest() != manifest[str(target.relative_to(keep))]:
                    raise RuntimeError('runtime log preservation mismatch: ' + str(log))
    for path in created:
        shutil.rmtree(path)
    keep.mkdir(parents=True, exist_ok=True)
    write_json(keep / 'manifest.json', dict(retiredRoots=[str(path) for path in created], preservedLogs=manifest))


def run_registry_case(args, profile, case, cases, record):
    if case == 'startup':
        cases.append(dict(startup(args, profile), case='startup'))
        if cases[-1]['status'] == 'PASS':
            remove_completed_installs(args.work_root / 'startup', args.output / 'startup')
        record('RUNNING')
        return cases[-1]['status'] == 'PASS'
    if case == 'red':
        sub = argparse.Namespace(**vars(args))
        sub.work_root, sub.output = args.work_root / 'red', args.output / 'red'
        sub.work_root.mkdir()
        sub.output.mkdir()
        for finding in RED_IDS:
            handler = red_todo if finding == 'P001' else red_navigation if finding == 'G81.generic' else red_input if finding == 'P169' else None
            result = handler(sub, profile) if handler else red_consumer(sub, profile, finding)
            cases.append(dict(result, case='red'))
            if result['status'] == 'REPRODUCED':
                # This finding's receipts are complete; keep inode use to one copy.
                remove_completed_installs(sub.work_root / finding, sub.output / finding)
            record('RUNNING')
        return all(c['status'] == 'REPRODUCED' for c in cases if c.get('case') == 'red')
    (args.work_root / case).mkdir()
    (args.output / case).mkdir()
    ok = True
    for name, argv, cwd, timeout in final_steps(args, case):
        log_path = args.output / case / (name.replace(':', '-') + '.log')
        runtime_before = set(profile.runtime_base.iterdir())
        started = time.monotonic()
        try:
            with log_path.open('w') as log, FixtureResources() as resources:
                process = resources.spawn(argv, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, timeout=30)
                code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            code = 'timeout:' + str(process.returncode)
        leftovers = step_leftovers([str(args.work_root / case / name.replace(':', '-')), str(args.output / case / name.replace(':', '-'))])
        for item in leftovers:
            with contextlib.suppress(ProcessLookupError):
                os.kill(item['pid'], 9)
        status = 'PASS' if code == 0 and not leftovers else 'FAIL'
        retire_step_runtime(profile, runtime_before, args.output / case / (name.replace(':', '-') + '-runtime-logs'))
        if status == 'PASS' and (args.work_root / case / name.replace(':', '-')).is_dir():
            # The driver and its cold readers have exited; keep receipts, not shell copies.
            remove_completed_installs(args.work_root / case / name.replace(':', '-'), args.output / case / name.replace(':', '-'))
        tail = log_path.read_text(errors='replace').strip().splitlines()[-3:]
        cases.append(dict(id=case + '/' + name, case=case, status=status, exit=code, seconds=round(time.monotonic() - started, 3),
                          leftovers=leftovers, tail=tail))
        print('STEP %s/%s: %s (%ss)' % (case, name, status, cases[-1]['seconds']), flush=True)
        record('RUNNING')
        ok = ok and status == 'PASS'
    return ok


def final_main(args, profile):
    """Ordered registry cases. Drivers take the per-run lock; this owns its own."""
    selected = [case for case in FINAL_CASES if case != 'red' or args.baseline_source] if args.case == 'all' else [args.case]
    with (profile.work_base / '.plugin-settings-final.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        start = time.monotonic()
        cases, finished = [], {}
        worker = ProcessIdentity.read(os.getpid()).record()
        worker['cgroup'] = Path('/proc/self/cgroup').read_text().strip()
        inputs = input_fingerprints(args)

        def record(status):
            done = [c for c in cases if c['status'] in ('PASS', 'REPRODUCED')]
            data = dict(status=status, guest=profile.record(), elapsedSeconds=round(time.monotonic() - start, 3), pid=os.getpid(),
                        worker=worker, inputs=inputs, selectedCases=selected, finishedCases=finished,
                        remainingCases=[case for case in selected if case not in finished],
                        completedSteps=len(done), failedSteps=[c['id'] for c in cases if c not in done], cases=cases)
            if status == 'RUNNING':
                write_json(args.output / 'status.json', data)
            else:
                stage_receipt(args.output / 'status.json', data)
            (args.output / 'interim-report.md').write_text(
                '# Plugin Settings final runner\n\n' + status + ', elapsed ' + str(data['elapsedSeconds']) + 's, cases ' +
                str(len(finished)) + '/' + str(len(selected)) + '\n\n' +
                '\n'.join('- ' + c['id'] + ': ' + c['status'] + (' (' + str(c['seconds']) + 's)' if 'seconds' in c else '') for c in cases) + '\n')
            return data

        record('RUNNING')
        for case in selected:
            try:
                finished[case] = 'PASS' if run_registry_case(args, profile, case, cases, record) else 'FAIL'
            except Exception as error:
                cases.append(dict(id=case, case=case, status='FAIL', error=str(error)))
                finished[case] = 'FAIL'
            print('CASE %s: %s' % (case, finished[case]), flush=True)
            record('RUNNING')
        status = 'PASS' if all(value == 'PASS' for value in finished.values()) else 'FAIL'
        result = record(status)
        stage_receipt(args.output / 'result.json', result)
        if status == 'PASS':
            remove_completed_installs(args.work_root, args.output)
        if args.case == 'all' or status != 'PASS':
            print('PLUGIN_SETTINGS_HOST_ASSETS: ' + status, flush=True)
        return 0 if status == 'PASS' else 2


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('baseline-source', 'baseline-plugins'):
        parser.add_argument('--' + name, type=Path)
    parser.add_argument('--case', choices=('red', 'startup', 'metadata', 'fields', 'todo', 'input', 'static', 'nesting', 'routes', 'desktop-plugins', 'catalog', 'assets', 'lint', 'all'), required=True)
    parser.add_argument('--finding', choices=RED_IDS, help='one red characterization, never full-suite success')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or not path.is_relative_to(parent) or path == parent:
            parser.error('fresh work/output children must belong to the verified profile roots')
    if args.case == 'red' and (args.baseline_source is None or args.baseline_plugins is None):
        parser.error('red requires explicit baseline trees')
    if args.finding and args.case != 'red':
        parser.error('--finding is only valid for red characterization')
    if args.case in ('input', 'todo', 'red', 'catalog', 'all'):
        injector = Path(os.environ.get('PHA_INPUT_INJECTOR', ''))
        if not injector.is_absolute() or not injector.resolve().is_relative_to(profile.work_base) or not injector.is_file() or not os.access(injector, os.X_OK):
            parser.error('PHA_INPUT_INJECTOR must select a task-owned executable under the verified guest work root')
    profile.prepare_roots()
    if args.case in FINAL_CASES[1:] + ('all',) and args.case != 'red':
        return final_main(args, profile)
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        start = time.monotonic()
        cases = []
        inputs = input_fingerprints(args)
        worker = ProcessIdentity.read(os.getpid()).record()
        worker['cgroup'] = Path('/proc/self/cgroup').read_text().strip()

        def record(status):
            data = dict(status=status, guest=profile.record(), elapsedSeconds=round(time.monotonic()-start, 3),
                        pid=os.getpid(), worker=worker, inputs=inputs, cases=cases, expectedRed=list(RED_IDS),
                        completed=sum(c['status'] == 'REPRODUCED' for c in cases))
            if status == 'RUNNING':
                write_json(args.output / 'status.json', data)
            else:
                stage_receipt(args.output / 'status.json', data)
            (args.output / 'interim-report.md').write_text(
                '# Plugin Settings characterization\n\n' + status + '\n\n' +
                '\n'.join(c['id'] + ': ' + c['status'] for c in cases) + '\n')
            return data

        record('RUNNING')
        try:
            if args.case in ('startup', 'metadata', 'fields', 'todo', 'input'):
                cases.append({'startup': startup, 'metadata': metadata_case, 'fields': fields_case, 'todo': todo_case, 'input': input_case}[args.case](args, profile))
                status = cases[-1]['status']
                stage_receipt(args.output / 'result.json', record(status))
                if status == 'PASS':
                    remove_completed_installs(args.work_root, args.output)
                return 0 if status == 'PASS' else 2
            elif args.case == 'red':
                for finding in (args.finding,) if args.finding else RED_IDS:
                    if finding == 'P001':
                        cases.append(red_todo(args, profile))
                    elif finding in RED_PLUGINS:
                        cases.append(red_consumer(args, profile, finding))
                    elif finding == 'G81.generic':
                        cases.append(red_navigation(args, profile))
                    elif finding == 'P169':
                        cases.append(red_input(args, profile))
                    else:
                        cases.append(dict(id=finding, status='BLOCKED', reason='witness not implemented yet'))
                    record('RUNNING')
                if not args.finding and len(cases) == len(RED_IDS) and all(c['status'] == 'REPRODUCED' for c in cases):
                    stage_receipt(args.output / 'result.json', record('RED_CONTROLS_PASS'))
                    remove_completed_installs(args.work_root, args.output)
                    print('RED_CONTROLS: PASS (characterization only; production correction pending)', flush=True)
                    return 0
            else:
                cases.append(dict(id=args.case, status='BLOCKED', reason='witness not implemented yet'))
            result = record('BLOCKED')
            stage_receipt(args.output / 'result.json', result)
            print('PLUGIN_SETTINGS_HOST_ASSETS: BLOCKED (incomplete witness registry)', flush=True)
            return 3
        except Exception as error:
            cases.append(dict(id=args.case, status='FAIL', error=str(error)))
            stage_receipt(args.output / 'result.json', record('FAIL'))
            print('PLUGIN_SETTINGS_HOST_ASSETS: FAIL (' + str(error) + ')', flush=True)
            return 2


if __name__ == '__main__':
    raise SystemExit(main())
