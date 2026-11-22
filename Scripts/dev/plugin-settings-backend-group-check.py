#!/usr/bin/env python3
"""Finite parsed backend-owner contract for all three G4 members."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('backend_syntax', Path(__file__).with_name('plugin-settings-action-group-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
MEMBERS = {
    'auto-cpufreq': {'compactMode', 'refreshInterval', 'showGovernor', 'showTurbo'},
    'battery-and-power-management': {'batteryDevice', 'colorPerformance', 'colorPowerSaver', 'colorizeByProfile', 'showBalancedIcon', 'showProfile'},
    'thinkpad-fan': {'allowPopupOpening', 'colorActive', 'colorAuto', 'colorLevel0', 'colorizeByStatus'},
}
PAGES = {'auto-cpufreq': 'Settings.qml', 'battery-and-power-management': 'SettingsView.qml', 'thinkpad-fan': 'SettingsView.qml'}
POPUPS = {'auto-cpufreq': 'Panel.qml', 'battery-and-power-management': 'BatteryPopup.qml', 'thinkpad-fan': 'FanPopup.qml'}
ANCHORS = {
    'auto-cpufreq/Main.qml': [
        'readonly property int sourceInterval: settingsContext.settingsView.refreshInterval ?? root.pluginApi?.manifest?.metadata?.defaultSettings?.refreshInterval ?? 3000',
        'readonly property int interval: sourceInterval', 'interval: client.interval', 'running: client.current repeat: true',
        'triggeredOnStart: true', 'onTriggered: client.refreshAll()', 'function refreshAll() { if (current) root.refreshAll(settingsContext); }',
        'function setForce(mode) { if (current) root.setForce(mode, settingsContext); }', 'function setTurbo(mode) { if (current) root.setTurbo(mode, settingsContext); }',
        'onForceCurrentChanged: if (!forceCurrent) forceProc.running = false', 'onTurboCurrentChanged: if (!turboCurrent) turboProc.running = false',
        'if (!root.forceCurrent) return', 'if (!root.turboCurrent) return', 'root.refreshAll(root.forceContext)', 'root.refreshAll(root.turboContext)',
        'forceContext = context', 'turboContext = context', 'forceProc.command = ["pkexec", "auto-cpufreq", "--force=" + mode]',
        'turboProc.command = ["pkexec", "auto-cpufreq", "--turbo=" + mode]',
        'governorFile.reload(); noTurboFile.reload(); boostFile.reload()',
    ],
    'auto-cpufreq/BarWidget.qml': ['property var cfg: pluginApi?.pluginSettings || ({})', 'cfg.compactMode ?? defaults.compactMode ?? false',
        'function setForce(mode) { settingsConsumer?.setForce(mode); }', 'function setTurbo(mode) { settingsConsumer?.setTurbo(mode); }'],
    'auto-cpufreq/Panel.qml': ['root.main?.setForce("performance")', 'root.main?.setTurbo("always")', 'text: root.main?.governor ?? "—"'],
    'battery-and-power-management/Main.qml': [
        'owner: root, settingsContext: context', 'Component { id: batteryFactory; BatterySource {} }',
        'if (!_batterySources.has(path)) _batterySources.set(path, batteryFactory.createObject(root, {devicePath: path}))',
        'source.subscribers++', 'source.subscribers--', 'if (source.subscribers === 0)', '_batterySources.delete(source.devicePath)',
        'source.active = false', 'source.destroy()', 'profileSetter.command = ["powerprofilesctl", "set", profile]',
        'command: ["powerprofilesctl", "get"]', 'Component.onCompleted: updatePowerProfile()',
    ],
    'battery-and-power-management/BatteryClient.qml': [
        'readonly property bool current: settingsContext.current()', 'settingsContext.settingsView.batteryDevice ?? "/sys/class/power_supply/BAT0"',
        'observation = current ? owner.acquireBattery(devicePath) : null', 'owner.releaseBattery(previous)',
        'onDevicePathChanged: if (_constructed) replaceSource()', 'onCurrentChanged: if (!current && _constructed) { replaceSource(); retire(root); }',
        'Component.onDestruction: owner.releaseBattery(observation)',
        'function setBatteryThreshold(value) { if (current) observation?.setBatteryThreshold(value, settingsContext); }',
        'function setPowerProfile(profile) { if (current) owner.setPowerProfile(profile, settingsContext); }',
    ],
    'battery-and-power-management/BatterySource.qml': [
        'required property string devicePath', 'readonly property bool actionCurrent: active && !!actionContext && actionContext.current()',
        'onActionCurrentChanged: if (!actionCurrent) thresholdSetter.running = false',
        'onActiveChanged: if (!active) { etaGetter.running = false; thresholdSetter.running = false; }',
        'if (!active || !context || !context.current()) return', 'actionContext = context',
        'thresholdSetter.command = ["sh", "-c", "echo " + value + " > " + devicePath + "/charge_control_end_threshold"]',
        'onStreamFinished: if (root.active) root.timeRemaining = root.parseEta(text)',
        'running: root.active && root.subscribers > 0', 'if (!etaGetter.running) etaGetter.running = true',
    ],
    'thinkpad-fan/Main.qml': [
        'readonly property bool current: settingsContext.current()', 'readonly property var cfg: settingsContext.settingsView',
        'cfg.colorizeByStatus', 'cfg.allowPopupOpening', 'cfg.colorLevel0', 'cfg.colorActive', 'cfg.colorAuto',
        'function setFanSpeed(level) { if (current) root.setFanSpeed(level, settingsContext); }',
        'readonly property bool actionCurrent: !!actionContext && actionContext.current()',
        'onActionCurrentChanged: if (!actionCurrent) { fanProcess.running = false; refreshTimer.stop(); }',
        'onExited: if (root.actionCurrent) refreshTimer.restart()', 'if (!isInitialized || !context || !context.current()) return',
        'actionContext = context', 'fanProcess.command = ["sh", "-c", "echo level " + level + " > /proc/acpi/ibm/fan"]',
        'interval: 300', 'onTriggered: if (root.actionCurrent) { fanLoader.reload(); tempLoader.reload(); }',
        'interval: 2000',
    ],
    'thinkpad-fan/FanPopup.qml': ['root.mainWidget.setFanSpeed(level)', '(root.mainWidget?.colorAuto ?? Style.capsuleColor)'],
}


def check(sources, manifests, dictionaries):
    codes = {p: syntax.syntax.compact(text)[0] for p, text in sources.items()}
    rows = []
    for name, fields in MEMBERS.items():
        manifest = manifests[name]
        if set(manifest['metadata']['settingsSchema']['fields']) != fields: raise ValueError(name + ': unreviewed fields')
        entries = dict(main='Main.qml', barWidget='BarWidget.qml', panel=POPUPS[name], settings=PAGES[name])
        if manifest['entryPoints'] != entries: raise ValueError(name + ': unreviewed entries')
        expected = set(entries.values()) | ({'BatteryClient.qml', 'BatterySource.qml'} if name == 'battery-and-power-management' else set())
        if {p.split('/')[1] for p in sources if p.startswith(name+'/')} != expected: raise ValueError(name + ': unreviewed component')
        for path in [name+'/BarWidget.qml', name+'/'+POPUPS[name]]:
            code = codes[path]; raw = sources[path].encode(); tree = syntax.syntax.compact(sources[path])[1]
            for node in syntax.syntax.walk(tree.root_node):
                if node.type == 'ui_object_definition' and re.match(rb'(?:Process|FileView)\s*\{', raw[node.start_byte:node.end_byte]):
                    raise ValueError(path + ': renderer owns physical backend')
            if 'mainInstance=' in code or 'execDetached(' in code: raise ValueError(path + ': renderer replaces backend')
            syntax.require(code, 'settingsConsumerFor(pluginApi.settingsContext)', path + ': selected client')
        owners = {'Main.qml': (6,4)} if name == 'auto-cpufreq' else {'Main.qml': (1,2)} if name == 'thinkpad-fan' else {'Main.qml': (2,0), 'BatterySource.qml': (2,2), 'BatteryClient.qml': (0,0)}
        for component, expected_counts in owners.items():
            path = name+'/'+component; raw = sources[path].encode(); tree = syntax.syntax.compact(sources[path])[1]
            counts = tuple(sum(node.type == 'ui_object_definition' and bool(re.match(kind+rb'\s*\{', raw[node.start_byte:node.end_byte])) for node in syntax.syntax.walk(tree.root_node)) for kind in (b'Process', b'FileView'))
            if counts != expected_counts or 'execDetached(' in codes[path]: raise ValueError(path + ': singular physical owners')
        page = codes[name+'/'+PAGES[name]]
        syntax.require(page, 'visible: root.pluginApi?.scopeKind === "instance"', name + ': shared visibility')
        syntax.require(page, 'root.pluginApi?.tr("settings.shared-effect")', name + ': shared explanation')
        for locale, data in dictionaries[name].items():
            if not data.get('settings',{}).get('shared-effect','').strip(): raise ValueError(name + ': missing explanation '+locale)
        main = codes[name+'/Main.qml']
        for anchor in ['new Map()', 'if (!context || !context.current()) return null', '_settingsConsumers.has(context)',
                       '_settingsConsumers.get(context)', '_settingsConsumers.set(context, client)', '_settingsConsumers.delete(context)', 'retired.destroy()']:
            syntax.require(main, anchor, name + ': context identity/lifetime')
        if 'pluginSettings' in main or 'saveSettings(' in main: raise ValueError(name + ': shared preference reader/writer')
        for field in fields - {'refreshInterval','batteryDevice','showGovernor','showTurbo'}:
            bar = codes[name+'/BarWidget.qml']
            syntax.require(bar, ('cfg.' if name == 'auto-cpufreq' else 'pluginApi?.pluginSettings?.') + field, name + ': selected '+field)
        if name != 'battery-and-power-management':
            syntax.require(main, 'onCurrentChanged: if (!current && _constructed) retire(client)', name + ': client retirement')
        rows.append(dict(plugin=name, fields=sorted(fields), entries=entries, physicalOwner='Main and device-keyed BatterySource' if name == 'battery-and-power-management' else 'Main',
                         preservedFeatureGaps=['showGovernor','showTurbo'] if name == 'auto-cpufreq' else []))
    for path, anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(codes[path], anchor, path + ': ' + anchor)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('plugins','report'): parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true'); args = parser.parse_args()
    sources = {name+'/'+p.name:p.read_text() for name in MEMBERS for p in (args.plugins/name).glob('*.qml')}
    manifests = {name:json.loads((args.plugins/name/'manifest.json').read_text()) for name in MEMBERS}
    dictionaries = {name:{p.name:json.loads(p.read_text()) for p in (args.plugins/name/'i18n').glob('*.json')} for name in MEMBERS}
    rows = check(sources, manifests, dictionaries); controls = []
    if args.selftest:
        mutations = []
        for name in MEMBERS:
            mutations += [
                (name+'/BarWidget.qml', 'property var pluginApi: null', 'property var pluginApi: null\nComponent.onCompleted: pluginApi.mainInstance = root', 'last-renderer'),
                (name+'/'+POPUPS[name], 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)', 'shared-popup'),
                (name+'/BarWidget.qml', 'property var pluginApi: null', 'property var pluginApi: null\nProcess { command: ["true"] }', 'duplicate-backend'),
                (name+'/Main.qml', '_settingsConsumers.has(context)', '_settingsConsumers.has(pluginApi.settingsContext)', 'shared-client-cache'),
                (name+'/Main.qml', 'property var pluginApi: null', 'property var pluginApi: null\nProcess { command: ["true"] }', 'duplicate-main-owner'),
            ]
        mutations += [
            ('auto-cpufreq/Main.qml','readonly property int sourceInterval','readonly property real sourceInterval','typed-polling'),
            ('auto-cpufreq/Main.qml','running: client.current','running: client.current && client.interval > 0','zero-domain'),
            ('auto-cpufreq/Main.qml','if (!root.turboCurrent) return','if (!root.pluginApi) return','retired-turbo'),
            ('battery-and-power-management/BatteryClient.qml','settingsContext.settingsView.batteryDevice','owner.pluginApi.settingsView.batteryDevice','shared-device'),
            ('battery-and-power-management/BatteryClient.qml','owner.releaseBattery(previous)','owner.releaseBattery(null)','old-device-subscription'),
            ('battery-and-power-management/BatterySource.qml','if (!active || !context || !context.current()) return','if (!active) return','retired-threshold'),
            ('thinkpad-fan/Main.qml','settingsContext.settingsView','root.pluginApi.settingsView','shared-palette'),
            ('thinkpad-fan/Main.qml','if (root.actionCurrent) refreshTimer.restart()','refreshTimer.restart()','retired-delayed-refresh'),
        ]
        for path, old, new, label in mutations:
            assert sources[path].count(old) == 1, (path,label)
            changed = dict(sources); changed[path] = changed[path].replace(old,new)
            try: check(changed, manifests, dictionaries)
            except ValueError as error: controls.append(dict(control=label, path=path, rejectedAt=str(error)))
            else: raise RuntimeError('backend control escaped: '+path+'/'+label)
        for name in MEMBERS:
            changed = json.loads(json.dumps(manifests)); changed[name]['entryPoints']['main'] = 'BarWidget.qml'
            try: check(sources,changed,dictionaries)
            except ValueError as error: controls.append(dict(control='bar-as-main-entry',plugin=name,rejectedAt=str(error)))
            else: raise RuntimeError('bar as Main escaped '+name)
    args.report.write_text(json.dumps(dict(status='PASS',kind='finite-parsed-contract',members=rows,controls=controls,runtimeAcceptance=False,completeGroupAcceptance=False),indent=2)+'\n')
    print('PLUGIN_SETTINGS_BACKEND_GROUP_CHECK: PASS (%d members, %d controls)' % (len(rows),len(controls)))


if __name__ == '__main__': main()
