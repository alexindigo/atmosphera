#!/usr/bin/env python3
"""Finite parsed Bongo field/entry/observation/lifetime contract."""
import argparse
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('bongo_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
FIELDS = 'catColor catOffsetY catSize idleTimeout inputDevice inputDevices raveMode tappyMode useMprisFilter waitingTimeout widthPadding'.split()
CLIENT_FIELDS = 'catColor catOffsetY catSize idleTimeout inputDevices raveMode tappyMode useMprisFilter waitingTimeout'.split()
ANCHORS = {
    'Main.qml': ['property var _settingsConsumers: new Map()', 'property var _deviceMonitors: new Map()', 'if (!context || !context.current()) return null', 'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)', 'settingsContext: context', 'root._settingsConsumers.delete(context)', 'root.synchronizeDevices()', 'retired.destroy()', '_settingsConsumers.set(context, client)', 'settingsConsumerFor(pluginApi.settingsContext)', 'if (!client.current) continue', 'for (var device of client.inputDevices) wanted.add(device)', 'if (wanted.has(device)) continue', '_deviceMonitors.delete(device)', 'monitor.stop()', 'monitor.destroy()', 'if (_deviceMonitors.has(device)) continue', 'deviceFactory.createObject(root, { device: device, observation: root })', '_deviceMonitors.set(device, monitor)', 'if (!client.current || client.inputDevices.indexOf(device) < 0) continue', 'client.onKeyPress(bigHit)', 'client.onKeyRelease(bigHit)', 'client.onKeyRepeat(bigHit)', 'if (pluginApi && !_spectrumRegistered)', 'SpectrumService.registerComponent(spectrumInstanceId)', 'if (_spectrumRegistered) SpectrumService.unregisterComponent(spectrumInstanceId)', 'property bool paused: false', 'function pause() { root.paused = true', 'function resume() { root.paused = false', 'function toggle() { root.paused = !root.paused'],
    'BongoSettingsClient.qml': ['required property var settingsContext', 'settingsContext.current()', 'settingsContext.settingsView', 'readonly property bool paused: observation.paused', 'onInputDevicesChanged: if (_constructed && current) observation.synchronizeDevices()', 'onCurrentChanged: if (_constructed && !current) { stop(); retire(root); }', 'for (var timer of [beatCooldownTimer, flashTimer, stateResetTimer, idleTimer, waitingTimer, blinkIntervalTimer, blinkDurationTimer, flutterTimer]) timer.stop()', 'if (!root.current || root.paused) return', 'interval: root.idleTimeout', 'interval: root.waitingTimeout', 'running: root.current && !root.paused && !root.waiting', '!useMprisFilter || MediaService.isPlaying', 'target: SpectrumService', 'musicEvent(root.bassIntensity > root.bigBeatThreshold)', 'readonly property int idleTimeout: cfg.idleTimeout ?? 250', 'readonly property int waitingTimeout: cfg.waitingTimeout ?? 5000'],
    'BongoDeviceMonitor.qml': ['required property string device', 'required property var observation', 'property bool active: true', 'readonly property var retryIntervals: [30000, 90000, 300000]', 'active = false', 'restartTimer.stop()', 'evtestProc.running = false', 'deviceCheckProc.running = false', 'command: ["evtest", root.device]', 'if (!root.active || !data.includes("EV_KEY")) return', 'if (!root.active) return', 'root.retryCount++', 'if (root.retryCount > root.retryIntervals.length)', 'restartTimer.interval = root.retryIntervals[root.retryCount - 1]', 'onTriggered: if (root.active) deviceCheckProc.running = true', 'command: ["test", "-e", root.device]', 'if (exitCode === 0) evtestProc.running = true', 'observation.inputEvent(root.device, "press", bigHit)', 'observation.inputEvent(root.device, "release", bigHit)', 'observation.inputEvent(root.device, "repeat", bigHit)'],
    'BarWidget.qml': ['pluginApi?.settingsContext?.current() ? mainInstance?.settingsConsumerFor(pluginApi.settingsContext) : null', 'settingsConsumer?.catSize ?? 1.0', 'settingsConsumer?.catOffsetY ?? 0.0', 'settingsConsumer?.catState ?? 0', 'settingsConsumer?.waiting ?? false', 'settingsConsumer?.catColor ?? "default"', 'settingsConsumer?.blinking ?? false', 'settingsConsumer?.showRainbowColor ?? false', 'settingsConsumer?.currentRainbowColor ?? "#ff0000"', 'pluginApi?.pluginSettings?.widthPadding ?? 0.2', 'font.pixelSize: root.capsuleHeight * root.activeCatSize', 'root.mainInstance.paused = !root.mainInstance.paused'],
    'Settings.qml': ['visible: root.pluginApi?.scopeKind === "instance"', 'text: root.pluginApi?.tr("settings.shared-effect") ?? ""', 'pluginApi?.pluginSettings?.inputDevice ?? pluginApi?.manifest?.metadata?.defaultSettings?.inputDevice', 'root.inputDevicesField.set(list)']
}


def check(sources, manifest, dictionaries):
    code = {name: syntax.compact(text)[0] for name, text in sources.items()}
    fields = manifest['metadata']['settingsSchema']['fields']
    if set(fields) != set(FIELDS) or any(row['editorUsage'] != 'configuration' for row in fields.values()): raise ValueError('unreviewed Bongo leaves or classification')
    if manifest['entryPoints'] != dict(main='Main.qml', barWidget='BarWidget.qml', settings='Settings.qml'): raise ValueError('unreviewed Bongo runtime entry')
    for path, anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(code[path], anchor, path + ': Bongo ownership: ' + anchor)
    syntax.require(code['BarWidget.qml'], 'readonly property real widthPadding: pluginApi?.pluginSettings?.widthPadding ?? 0.2', 'direct originating width padding owner')
    for key in CLIENT_FIELDS:
        syntax.require(code['BongoSettingsClient.qml'], 'cfg.' + key, 'missing selected Bongo field: ' + key)
    syntax.require(code['BongoSettingsClient.qml'], 'const saved = cfg.inputDevices; if (saved && saved.length > 0) return saved; return [];', 'selected finite input list')
    for key in 'inputDevices catColor catSize catOffsetY raveMode tappyMode useMprisFilter'.split():
        syntax.require(code['Settings.qml'], 'pluginApi?.field("' + key + '")', 'missing Bongo page intent: ' + key)
    if 'pluginSettings' in code['Main.qml'] or 'pluginSettings' in code['BongoSettingsClient.qml']: raise ValueError('shared Bongo policy fallback')
    if any('saveSettings(' in code[p] or 'registerComponent(' in code[p] or 'Process{' in code[p] for p in ('BongoSettingsClient.qml', 'BarWidget.qml')): raise ValueError('duplicated physical/audio/preference owner')
    for locale, dictionary in dictionaries.items():
        if not dictionary.get('settings', {}).get('shared-effect', '').strip(): raise ValueError('missing common Bongo effect explanation: ' + locale)
    return dict(plugin='slowbongo', fields=FIELDS, selectedClientFields=CLIENT_FIELDS, directField='widthPadding', legacyDisplayOnly='inputDevice', physicalOwner='Main/device', audioRegistrationOwner='Main', pauseOwner='Main', runtimeAcceptance=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'report'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true'); args = parser.parse_args()
    root = args.plugins / 'slowbongo'; sources = {p.name: p.read_text() for p in root.glob('*.qml')}
    manifest = json.loads((root / 'manifest.json').read_text()); dictionaries = {p.stem: json.loads(p.read_text()) for p in (root / 'i18n').glob('*.json')}
    row = check(sources, manifest, dictionaries); controls = []
    if args.selftest:
        changes = [('BongoSettingsClient.qml', 'cfg.' + key, 'other.' + key, 'shared-' + key) for key in CLIENT_FIELDS]
        changes += [('Main.qml', 'root._settingsConsumers.delete(context)', 'context', 'retirement'), ('Main.qml', 'client.inputDevices.indexOf(device) < 0', 'false', 'source-filter'), ('Main.qml', 'monitor.stop()', 'monitor', 'source-stop'), ('Main.qml', 'if (_deviceMonitors.has(device)) continue;', 'if (false) continue;', 'duplicate-observer'), ('BarWidget.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(mainInstance.pluginApi.settingsContext)', 'shared-bar'), ('BarWidget.qml', 'pluginApi?.pluginSettings?.widthPadding ?? 0.2', 'mainInstance?.pluginApi?.pluginSettings?.widthPadding ?? 0.2', 'shared-width'), ('BongoDeviceMonitor.qml', 'deviceCheckProc.running = false', 'deviceCheckProc.running = true', 'held-check'), ('BongoDeviceMonitor.qml', 'if (!root.active || !data.includes("EV_KEY")) return;', 'if (!data.includes("EV_KEY")) return;', 'late-input'), ('BongoSettingsClient.qml', 'timer.stop()', 'timer', 'pending-animation'), ('Main.qml', 'if (pluginApi && !_spectrumRegistered)', 'if (pluginApi)', 'spectrum-duplicate')]
        for path, old, new, label in changes:
            if sources[path].count(old) != 1: raise RuntimeError('stale Bongo control: ' + label)
            anchors = [anchor for anchor in ANCHORS[path] if syntax.squash(old) in syntax.squash(anchor)]
            expected = {path + ': Bongo ownership: ' + anchor for anchor in anchors}
            if label.startswith('shared-') and path == 'BongoSettingsClient.qml':
                expected.add('missing selected Bongo field: ' + label.removeprefix('shared-'))
            if label == 'shared-width':
                expected.add('direct originating width padding owner')
            if not expected: raise RuntimeError('Bongo control has no expected diagnostic: ' + label)
            changed = dict(sources); changed[path] = sources[path].replace(old, new)
            try: check(changed, manifest, dictionaries)
            except ValueError as error:
                if str(error) not in expected:
                    raise RuntimeError('Bongo control rejected for the wrong reason: ' + label) from error
                controls.append(dict(control=label, rejectedAt=str(error)))
            else: raise RuntimeError('Bongo control escaped: ' + label)
    args.report.write_text(json.dumps(dict(status='PASS', member=row, controls=controls, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_BONGO_CHECK: PASS (11 leaves, %d controls)' % len(controls))


if __name__ == '__main__': main()
