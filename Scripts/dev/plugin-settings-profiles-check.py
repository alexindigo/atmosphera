#!/usr/bin/env python3
"""Finite Profiles settings, listing, action capture and native-writer mappings."""
import argparse
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('profiles_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
CONFIG = ['profilesDir','icon','iconColor','includeWallpapers','backupEnabled','backupCount']
ANCHORS = {
    'Main.qml': ['property var _settingsConsumers: new Map()', '_settingsConsumers.has(context)', 'settingsContext: context',
        '_settingsConsumers.set(context, client)', 'root._settingsConsumers.delete(context); retired.destroy()',
        'var api = origin === undefined ? pluginApi : origin', 'var cfg = api.pluginSettings',
        'directory: path, backups: path + "_backups/"', 'backupEnabled: cfg.backupEnabled ?? true',
        'backupCount: Math.max(1, Math.min(20, cfg.backupCount ?? 5))',
        'lastApplied: settingsConsumerFor(api.settingsContext).lastAppliedProfile',
        'request.context.current() && request.api && request.api.settingsContext === request.context',
        'request.backups', 'String(request.backupCount)', 'var dirPath = request.directory + trimmed',
        '["rm", "-rf", request.directory + trimmed]', '["mv", request.directory + oldT, request.directory + newT]',
        'var api = request.api', 'PluginInstances.address(api.placement)', 'var handle = address ? Settings.store : api.settingsHandle',
        'api.pluginSettings.lastAppliedProfile = name', 'handle.info(path).latestInput === input', 'api.saveSettings(function (receipt)',
        'if (ok) { var client = root.settingsConsumerFor(request.context); if (client) client.lastAppliedProfile = name; }',
        'if (!_current(request)) return', 'root._settleCommand(exitCode, commandOutput.text, commandErrors.text)',
        'if (!running && root._lifetime.alive) root._settleCommand(-1',
        'cmdProc.pendingCallback = null', 'Service.synchronizePreferences(operation',
        'root.applyProfile(name, includeWallpapers)'],
    'ProfileSettingsClient.qml': ['required property var settingsContext', 'readonly property var cfg: settingsContext.settingsView',
        'var path = cfg.profilesDir || ""', 'property string lastAppliedProfile: ""',
        'Component.onCompleted: { lastAppliedProfile = cfg.lastAppliedProfile || "";',
        'api.settingsContext === settingsContext', 'saveAction(name, callback, api)', 'applyAction(name, includeWallpapers, callback, api)',
        'deleteAction(name, callback, api)', 'renameAction(oldName, newName, callback, api)',
        '_listing = null', 'previous.running = false; previous.destroy()', 'directory: profilesDir',
        '_listing !== listing || listing.directory !== profilesDir', 'onProfilesDirChanged: if (_constructed) listProfiles()',
        'stopListing(); profiles = []; profileMeta = ({}); retire(root)'],
    'Panel.qml': ['settingsConsumerFor(pluginApi.settingsContext)', 'pluginApi?.pluginSettings?.includeWallpapers',
        'service?.saveProfile(name, function(ok, msg)', '}, root.pluginApi)', 'service: root.service', 'pluginApi: root.pluginApi'],
    'ProfileRow.qml': ['service?.saveProfile(root.profileName, null, root.pluginApi)', 'service?.deleteProfile(root.profileName, null, root.pluginApi)',
        'service?.renameProfile(root.profileName, newName, function (ok, msg)', '}, root.pluginApi)',
        'service?.applyProfile(root.profileName, root.includeWallpapers, null, root.pluginApi)', 'text: root.profileName', 'service?.lastAppliedProfile'],
    'BarWidget.qml': ['readonly property string widgetIcon: pluginApi?.pluginSettings?.icon', 'readonly property string iconColorKey: pluginApi?.pluginSettings?.iconColor', 'icon: root.widgetIcon', 'color: root.iconColor'],
    'Settings.qml': ['pluginApi?.scopeKind === "instance"','pluginApi?.tr("settings.shared-effect")'],
}


def check(sources, manifest, dictionaries):
    code = {key: syntax.compact(value)[0] for key,value in sources.items()}
    fields = manifest['metadata']['settingsSchema']['fields']
    assert set(fields) == set(CONFIG+['lastAppliedProfile'])
    for key in CONFIG:
        assert fields[key]['editorUsage'] == 'configuration'
        syntax.require(code['Settings.qml'], 'pluginApi?.field("'+key+'")', key+' intent')
    assert fields['lastAppliedProfile']['editorUsage'] == 'operational'
    for name, anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(code[name], anchor, name+': '+anchor)
    assert code['Main.qml'].count(syntax.squash('var request = _capture(origin)')) == 4, 'every profile action captures its origin'
    assert code['Main.qml'].count(syntax.squash('if (isBusy)')) == 4, 'one common busy admission for every effect'
    assert 'pluginSettings.lastAppliedProfile' not in code['ProfileSettingsClient.qml'], 'listing is not a writer'
    assert syntax.squash('readonly property string lastAppliedProfile: cfg.lastAppliedProfile') not in code['ProfileSettingsClient.qml'], 'active marker is confirmed, never optimistic native intent'
    for name,value in dictionaries.items():
        assert value['settings']['shared-effect'] == dictionaries['en.json']['settings']['shared-effect'], name+' explicit shared-effect fallback'
    return dict(configuration=CONFIG,operational=['lastAppliedProfile'],listingOwner='Main per captured context',effectOwner='one serial Main',runtimeAcceptance=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('source','plugins','report'): parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--selftest',action='store_true'); args=parser.parse_args(); root=args.plugins/'shell-profiles'
    sources={p.name:p.read_text() for p in root.glob('*.qml')}; manifest=json.loads((root/'manifest.json').read_text())
    dictionaries={p.name:json.loads(p.read_text()) for p in (root/'i18n').glob('*.json')}
    member=check(sources,manifest,dictionaries); controls=[]
    mutations=[('Main.qml','var api = origin === undefined ? pluginApi : origin','var api = pluginApi','shared-capture'),
        ('Main.qml','var api = request.api;','var api = pluginApi;','shared-marker-writer'),
        ('Main.qml','String(request.backupCount)','String(request.api.pluginSettings.backupCount)','late-backup-policy'),
        ('Main.qml','if (!_current(request)) return;','if (!request) return;','late-feedback'),
        ('Main.qml','root._settleCommand(-1','root._settleCommand(0','failed-start-success'),
        ('Main.qml','if (client) client.lastAppliedProfile = name;','if (client) client.lastAppliedProfile = "wrong";','confirmed-marker'),
        ('ProfileSettingsClient.qml','property string lastAppliedProfile: ""','readonly property string lastAppliedProfile: cfg.lastAppliedProfile || ""','optimistic-marker'),
        ('ProfileSettingsClient.qml','directory: profilesDir','directory: "shared"','wrong-directory'),
        ('ProfileSettingsClient.qml','_listing !== listing || listing.directory !== profilesDir','false','stale-listing'),
        ('ProfileSettingsClient.qml','previous.running = false; previous.destroy();','previous.destroy();','listing-process-retirement'),
        ('ProfileSettingsClient.qml','retire(root);','/* leak */','listing-retirement'),
        ('Panel.qml','settingsConsumerFor(pluginApi.settingsContext)','settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)','shared-panel'),
        ('ProfileRow.qml','null, root.pluginApi','null, undefined','missing-row-origin'),
        ('ProfileRow.qml','text: root.profileName','text: "wrong"','rendered-row'),
        ('BarWidget.qml','pluginApi?.pluginSettings?.iconColor','pluginApi?.mainInstance?.pluginApi?.pluginSettings?.iconColor','shared-bar-color')]
    if args.selftest:
        for name,old,new,label in mutations:
            assert old in sources[name],label
            changed=dict(sources); changed[name]=sources[name].replace(old,new)
            try: check(changed,manifest,dictionaries)
            except (AssertionError,ValueError) as error: controls.append(dict(control=label,rejectedAt=str(error)))
            else: raise RuntimeError('profiles control escaped: '+label)
    args.report.write_text(json.dumps(dict(status='PASS',member=member,controls=controls,runtimeAcceptance=False),indent=2)+'\n')
    print('PROFILES_CHECK: PASS (6 configuration, 1 operational, %d controls)'%len(controls))


if __name__=='__main__': main()
