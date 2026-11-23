#!/usr/bin/env python3
"""Reviewed catalog usage preparation, not generic-page adoption. Guest only."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import copy
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


runner = module('host_regression', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))

# Independent test oracle from the Settings/runtime writer review. Production
# consumes only the authored descriptors. Neither machineLocal nor names infer
# usage. In particular repo aliases and user-supplied credentials remain config.
REVIEWED = {
    'todo': dict(configuration='exportEmptySections exportFormat exportPath isExpanded priorityColors showBackground showCompleted useCustomColors',
                 content='todos pages current_page_id', operational='count completedCount'),
    'git-companion': dict(configuration='group platform refreshInterval repo selectedRepo'),
    'air-quality': dict(configuration='aqiScale aqicnToken boldText customLatitude customLongitude dataSource refreshInterval useNoctaliaLocation'),
    'arch-updater': dict(configuration='aurCmd aurHomepageCmd boldText boldVer boldVerDesktop boldVerPanel closeButton closeOnSettings customIconPath desktopTip enableColorization flatpak hideOnEmpty hoverTip iconColor iconName noctalia panelContext panelTooltip refreshInterval refreshTimer systemCmd toast tooltip updateCmd useDistroLogo'),
    'github-contributions': dict(configuration='layout refreshInterval showLabels showTotal token username weeksShown'),
    'catwalk': dict(configuration='hideBackground minimumThreshold'),
    'notes-scratchpad': dict(configuration='filePath fontSize panelHeight panelWidth useMonospace',
                           content='scratchpadContent', operational='cursorPosition scrollPositionX scrollPositionY'),
    'simple-notes': dict(configuration='showCountInBar', content='notes', operational='count'),
    'saved-desktop-widgets': dict(configuration='loadWidgets saveWidgets', content='monitorWidgets'),
    'pomodoro': dict(configuration='autoStartBreaks autoStartWork compactMode longBreakDuration playSound sessionsBeforeLongBreak shortBreakDuration workDuration'),
    'rss-feed': dict(configuration='feeds markAsReadOnClick maxItemsPerFeed showOnlyUnread updateInterval', operational='readItems'),
    'tamagotchi': dict(configuration='difficulty showDebug showPercentage volume', operational='hunger happiness cleanliness energy'),
}
CONSUMERS = {
    'todo': ('showCompleted', False), 'git-companion': ('repo', 'synthetic/reviewed'),
    'air-quality': ('customLatitude', '3'), 'arch-updater': ('flatpak', False),
    'github-contributions': ('username', 'synthetic-reviewed'), 'catwalk': ('minimumThreshold', 0),
    'notes-scratchpad': ('fontSize', 13), 'simple-notes': ('showCountInBar', False),
    'saved-desktop-widgets': ('saveWidgets', False), 'pomodoro': ('workDuration', 0),
    'rss-feed': ('updateInterval', 620), 'tamagotchi': ('difficulty', 55),
}
PROTECTED = {
    'todo': dict(todos=[dict(id=91, text='synthetic preserved task', completed=False)],
                 pages=[dict(id=7, name='Synthetic')], current_page_id=7, count=1, completedCount=0),
    'notes-scratchpad': dict(scratchpadContent='synthetic preserved text', cursorPosition=3,
                           scrollPositionX=0, scrollPositionY=0.25),
    'simple-notes': dict(notes=[dict(id='synthetic', title='keep', content='synthetic note')], count=1),
    # P084 populated snapshot schema repair is not part of usage annotation.
    'saved-desktop-widgets': dict(monitorWidgets={}),
    'rss-feed': dict(readItems=['synthetic-read-item']),
    'tamagotchi': dict(hunger=11, happiness=22, cleanliness=33, energy=44),
}


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    schema = module('plugin_schema', args.source / 'Scripts/python/src/settings/plugin-schema.py')
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or not path.is_relative_to(parent) or path == parent:
            parser.error('fresh roots must belong to the explicit guest profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        case, out = args.work_root, args.output
        install = case / 'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        for part in ('config/settings/plugins', 'config/plugins', 'cache', 'state'):
            (case / part).mkdir(parents=True, exist_ok=True)
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        overlays = json.loads((args.source / 'Configs/plugin-settings-overlays.json').read_text())
        expected, before, fingerprints, inventory, compatibility = [], {}, {}, [], {}
        for path in sorted(args.plugins.glob('*/manifest.json')):
            manifest = json.loads(path.read_text())
            entry = manifest.get('entryPoints', {}).get('settings')
            if entry:
                local = path.parent / entry.split('?', 1)[0]
                if not local.is_file() or not local.resolve().is_relative_to(path.parent.resolve()):
                    raise RuntimeError('generic entry missing or outside plugin: ' + manifest['id'])
                metadata = schema.editor_metadata(manifest, overlays)
                inventory.append(dict(id=manifest['id'], version=manifest['version'], entry=entry,
                                      metadataReady=metadata['ready'], error=metadata['error'],
                                      pageAdoptionVerified=False))
        runner.write_json(out / 'catalog-inventory.json', inventory)
        for name, roles in REVIEWED.items():
            path = args.plugins / name / 'manifest.json'
            manifest = json.loads(path.read_text())
            metadata = schema.editor_metadata(manifest, overlays)
            usage = {key: role for role, keys in roles.items() for key in keys.split()}
            if not metadata['ready'] or {k: v['usage'] for k, v in metadata['fields'].items()} != usage:
                raise RuntimeError('reviewed usage coverage differs: ' + name)
            plain = copy.deepcopy(manifest)
            for declaration in plain['metadata']['settingsSchema']['fields'].values():
                del declaration['editorUsage']
            if schema.compile_schema(manifest, overlays)[0] != schema.compile_schema(plain, overlays)[0]:
                raise RuntimeError('usage changed native value admission: ' + name)
            versions = overlays['plugins'][name]
            if len(versions) != 1:
                raise RuntimeError('review added exact-version variants before extending this witness: ' + name)
            frozen = copy.deepcopy(manifest)
            frozen['version'] = next(iter(versions))
            del frozen['metadata']['settingsSchema']
            frozen_metadata = schema.editor_metadata(frozen, overlays)
            if not frozen_metadata['ready'] or {k: v['usage'] for k, v in frozen_metadata['fields'].items()} != usage:
                raise RuntimeError('reviewed exact-version usage differs: ' + name)
            plain_overlays = copy.deepcopy(overlays)
            for declaration in plain_overlays['plugins'][name][frozen['version']]['fields'].values():
                del declaration['editorUsage']
            if schema.compile_schema(frozen, overlays)[0] != schema.compile_schema(frozen, plain_overlays)[0]:
                raise RuntimeError('exact-version usage changed native admission: ' + name)
            compatibility[name] = frozen
            shutil.copytree(args.plugins / name, case / 'config/plugins' / name)
            consumer, value = CONSUMERS[name]
            stored = dict(PROTECTED.get(name, {}), **{consumer: value}, opaque=dict(keep=name))
            target = case / 'config/settings/plugins' / (name + '.json')
            runner.write_json(target, stored)
            before[name] = hashlib.sha256(target.read_bytes()).hexdigest()
            expected.append(dict(id=name, usage=usage, consumer=consumer, consumerText=str(value).lower() if isinstance(value, bool) else str(value),
                                 values=dict(manifest['metadata']['defaultSettings'], **{k: v for k, v in stored.items() if k != 'opaque'})))
            fingerprints[name + '/manifest.json'] = hashlib.sha256(path.read_bytes()).hexdigest()
        runner.write_json(case / 'expected.json', expected)
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-catalog-metadata.qml'
        env = dict(PHA_CATALOG_EXPECTED=str(case / 'expected.json'))
        bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
        for phase in ('warm', 'cold', 'compatibility', 'compatibility-cold'):
            if phase == 'compatibility':
                for name, manifest in compatibility.items():
                    runner.write_json(case / 'config/plugins' / name / 'manifest.json', manifest)
            phase_out = out / phase
            phase_out.mkdir()
            text = runner.run_fixture(profile, install, case, phase_out, fixture, extra_env=env)
            if text.count('CATALOG_METADATA_NATIVE: PASS ') != len(expected) or any(marker in text for marker in bad):
                raise RuntimeError('native metadata/consumer diagnostics; see ' + phase + '/runtime.log')
            for name, digest in before.items():
                if hashlib.sha256((case / 'config/settings/plugins' / (name + '.json')).read_bytes()).hexdigest() != digest:
                    raise RuntimeError('untouched Apply changed exact stored bytes: ' + name)
        stage_receipt(out / 'result.json', dict(status='PASS', reviewedPlugins=len(expected), genericEntries=len(inventory),
                          inputs=fingerprints, storedSha256=before, nativeAdmissionUnchanged=True,
                          shellInputs={name: hashlib.sha256((args.source / name).read_bytes()).hexdigest() for name in (
                              'Scripts/dev/plugin-settings-catalog-metadata-regression.py',
                              'Scripts/dev/fixtures/plugin-settings-catalog-metadata.qml',
                              'Scripts/python/src/settings/plugin-schema.py', 'Configs/plugin-settings-overlays.json')},
                          actualNativeOwners=True, boundConsumerPerOwner=True, untouchedApply=True,
                          protectedBytesUnchanged=True, separateColdConsumers=True, exactVersionCompatibility=True,
                          pageAdoptionVerified=False))
        print('PLUGIN_SETTINGS_CATALOG_METADATA: PASS (12 reviewed owners; no page adoption claim)', flush=True)


if __name__ == '__main__':
    main()
