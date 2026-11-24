#!/usr/bin/env python3
"""Finite parsed G1d factory, leaf, projection and action-ownership contracts."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('projection_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
FIELDS = {
    'privacy-indicator': {'PrivacySettingsClient.qml': 'micFilterRegex camFilterRegex enableToast', 'BarWidget.qml': 'hideInactive removeMargins iconSpacing activeColor inactiveColor'},
    'kde-connect': {'KdeSettingsClient.qml': 'mainDeviceId hideIfNoDeviceConnected'},
    'noctalia-calculator': {'CalculatorSettingsClient.qml': 'precision showBarValue'},
}
CLIENTS = dict(zip(FIELDS, ('PrivacySettingsClient.qml', 'KdeSettingsClient.qml', 'CalculatorSettingsClient.qml')))
ANCHORS = {
    'privacy-indicator/Main.qml': ['rawMic = Projection.microphone(nodes, links)', 'rawCamera = apps', 'readonly property var microphone: Projection.filteredMicrophone(rawMic, micFilterRegex)', 'root._toastIssued.has(type)', 'root._toastIssued.set(type, requesters)', 'root._toastIssued.delete(type)', 'if (!Array.from(requesters).some(requester => requester.current())) return', 'checkAppChanges(micApps, _prevMicApps, "Microphone", "microphone", activeColorKey)'],
    'privacy-indicator/PrivacySettingsClient.qml': ['Projection.filteredMicrophone(observation.rawMic, cfg.micFilterRegex ?? "")', 'Projection.camera(observation.rawCamera, cfg.camFilterRegex ?? "")', 'readonly property var accessHistory: observation.accessHistory', 'if (current && enableToast) observation.requestToast(type, settingsContext)', 'if (current) observation.clearHistory()'],
    'kde-connect/KdeSettingsClient.qml': ['observation.selectDevice(deviceId, checkReachable)', 'api.settingsContext !== settingsContext', 'api.pluginSettings.mainDeviceId = id', 'api.saveSettings()', 'if (current && mainDevice) observation.triggerFindMyPhone(mainDevice.id)', 'if (current && mainDevice) observation.browseFiles(mainDevice.id)', 'if (current && mainDevice) observation.wakeUpDevice(mainDevice.id)', 'if (current && mainDevice) observation.unpairDevice(mainDevice.id)', 'if (current && id) observation.shareFile(id, path)'],
    'kde-connect/Panel.qml': ['property string capturedDeviceId: ""', 'capturedDeviceId = root.settingsConsumer?.mainDevice?.id || ""', 'root.settingsConsumer?.shareFile(capturedDeviceId, path)', 'root.settingsConsumer?.selectDevice(modelData.id, root.pluginApi)'],
    'kde-connect/Services/KDEConnect.qml': ['function selectDevice(deviceId, checkReachable)', 'newMain = devices.find((device) => device.id === deviceId && device.reachable)', 'newMain = devices.find((device) => device.reachable)', 'newMain = devices.length === 0 ? null : devices[0]'],
    'noctalia-calculator/CalculatorSettingsClient.qml': ['calculation.pressButton(action, precision)', 'calculation.handleKeyEvent(event, precision)', 'readonly property string currentInput: calculation.currentInput', 'readonly property string badgeText: showBarValue ? calculation.compactDisplay(displayText, 9, precision) : ""'],
    'noctalia-calculator/Main.qml': ['function _numberToString(value, selectedPrecision)', 'selectedPrecision === undefined ? precision : selectedPrecision', 'function evaluate(selectedPrecision)', '_numberToString(result, selectedPrecision)', 'function applyPercent(selectedPrecision)', '_numberToString(numeric / 100, selectedPrecision)', 'function pressButton(action, selectedPrecision)', 'evaluate(selectedPrecision)', 'applyPercent(selectedPrecision)', 'function handleKeyEvent(event, selectedPrecision)', 'pressButton(action, selectedPrecision)'],
}


def check(sources, manifests, dictionaries):
    code = {path: syntax.compact(text)[0] for path, text in sources.items()}
    rows = []
    for name, mapping in FIELDS.items():
        fields = {field for keys in mapping.values() for field in keys.split()}
        if fields != set(manifests[name]['metadata']['settingsSchema']['fields']):
            raise ValueError(name + ': unreviewed declared leaves')
        main = code[name + '/Main.qml']
        for anchor in ('property var _settingsConsumers: new Map()', 'if (!context || !context.current()) return null', 'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)', 'settingsContext: context', 'root._settingsConsumers.delete(context)', 'retired.destroy()', '_settingsConsumers.set(context, client)'):
            syntax.require(main, anchor, name + ': captured cache/retirement: ' + anchor)
        client = code[name + '/' + CLIENTS[name]]
        for anchor in ('settingsContext.settingsView', 'settingsContext.current()', 'if (!current && _constructed) retire('):
            syntax.require(client, anchor, name + ': selected lifetime: ' + anchor)
        for filename, keys in mapping.items():
            for key in keys.split():
                if not re.search(r'(?:cfg|pluginSettings)(?:\?|)\.' + key + r'\b', code[name + '/' + filename]):
                    raise ValueError(name + ': selected leaf missing: ' + key)
        entries = {value for key, value in manifests[name]['entryPoints'].items() if key in {'barWidget', 'panel', 'controlCenterWidget', 'desktopWidget', 'launcherProvider'}}
        for entry in entries:
            syntax.require(code[name + '/' + entry], 'settingsConsumerFor(pluginApi.settingsContext)', name + ': selected runtime entry: ' + entry)
        for anchor in ('visible: root.pluginApi?.scopeKind === "instance"', 'root.pluginApi?.tr("settings.shared-effect")'):
            syntax.require(code[name + '/Settings.qml'], anchor, name + ': explicit shared-effect UI')
        for locale, dictionary in dictionaries[name].items():
            if not dictionary.get('settings', {}).get('shared-effect', '').strip():
                raise ValueError(name + ': missing shared-effect dictionary: ' + locale)
        rows.append(dict(plugin=name, fields=sorted(fields), runtimeEntries=sorted(entries)))
    for path, anchors in ANCHORS.items():
        for anchor in anchors:
            syntax.require(code[path], anchor, path + ': projection/action contract: ' + anchor)
    if 'KDEConnect.mainDevice' in sources['kde-connect/Panel.qml'] or 'KDEConnect.setMainDevice' in sources['kde-connect/Panel.qml']:
        raise ValueError('KDE Panel still changes/reads singleton selection')
    if 'property var tokens:' in sources['noctalia-calculator/CalculatorSettingsClient.qml'] or 'property string currentInput:' in sources['noctalia-calculator/CalculatorSettingsClient.qml'].replace('readonly property string currentInput:', ''):
        raise ValueError('calculator copied shared input state')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'report'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true')
    args = parser.parse_args()
    sources, manifests, dictionaries = {}, {}, {}
    for name in FIELDS:
        manifests[name] = json.loads((args.plugins / name / 'manifest.json').read_text())
        dictionaries[name] = {p.stem: json.loads(p.read_text()) for p in (args.plugins / name / 'i18n').glob('*.json')}
        sources.update({name + '/' + str(p.relative_to(args.plugins / name)): p.read_text() for p in (args.plugins / name).rglob('*.qml')})
    rows = check(sources, manifests, dictionaries)
    controls = []
    if args.selftest:
        mutations = [(name + '/Main.qml', 'root._settingsConsumers.delete(context)', 'context', 'retirement') for name in FIELDS]
        mutations += [(name + '/BarWidget.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.base.settingsContext)', 'shared-view') for name in FIELDS]
        mutations += [('privacy-indicator/PrivacySettingsClient.qml', 'cfg.micFilterRegex', 'observation.cfg.micFilterRegex', 'shared-filter'), ('privacy-indicator/Main.qml', 'root._toastIssued.has(type)', 'false', 'duplicate-toast'), ('kde-connect/Panel.qml', 'shareFile(capturedDeviceId, path)', 'shareFile("wrong-device", path)', 'chooser-target'), ('kde-connect/KdeSettingsClient.qml', 'api.saveSettings()', 'observation.saveSettings()', 'shared-writer'), ('noctalia-calculator/Main.qml', '_numberToString(result, selectedPrecision)', '_numberToString(result)', 'shared-evaluation')]
        for path, old, new, label in mutations:
            if sources[path].count(old) != 1:
                raise RuntimeError('stale projection control: ' + path + '/' + old)
            changed = dict(sources); changed[path] = sources[path].replace(old, new)
            try:
                check(changed, manifests, dictionaries)
            except ValueError as error:
                controls.append(dict(path=path, control=label, rejectedAt=str(error)))
            else:
                raise RuntimeError('projection control escaped: ' + label)
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-projection-contract', members=rows, controls=controls, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_PROJECTION_CHECK: PASS (%d members, %d controls)' % (len(rows), len(controls)))


if __name__ == '__main__':
    main()
