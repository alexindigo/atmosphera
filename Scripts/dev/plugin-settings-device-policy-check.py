#!/usr/bin/env python3
"""Finite parsed field, observer-lease and action contract for five G1 members."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('device_policy_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec)
spec.loader.exec_module(syntax)

# Each declared leaf has an explicit selected reader, not just a fingerprint.
FIELDS = {
    'amd-gpu-monitor': {
        'GpuSettingsClient.qml': 'deviceIndex',
        'BarWidget.qml': 'compactMode iconColor textColor useMonospaceFont usePadding showGpuUse showTempJunction showTempEdge showTempMemory showVram showVramActivity showFanSpeed showPower showSclk showMclk showFclk showSocclk showDcefclk',
    },
    'battery-monitor-plus': {
        'BatterySettingsClient.qml': 'deviceNativePath refreshIntervalSeconds',
        'BarWidget.qml': 'displayMode hideIfNotDetected hideIfIdle showPowerProfiles showNoctaliaPerformance showPowerInBar showTimeInBar',
    },
    'netbird': {
        'NetbirdSettingsClient.qml': 'compactMode showIpAddress showPing refreshInterval managementUrl',
        'Panel.qml': 'hideDisconnected terminalCommand pingCount defaultPeerAction',
    },
    'openvpn3': {
        'OpenvpnSettingsClient.qml': 'pollInterval showNotifications',
        'BarWidget.qml': 'connectedColor disconnectedColor displayMode hideWhenInactive',
        'Panel.qml': 'defaultPersistent',
    },
    'tailscale': {
        'TailscaleSettingsClient.qml': 'compactMode showIpAddress showPeerCount refreshInterval taildropEnabled taildropDownloadDir taildropReceiveMode loginServer',
        'Panel.qml': 'hideDisconnected hideMullvadExitNodes showSearchBar terminalCommand sshUsername pingCount defaultPeerAction',
    },
}
CLIENTS = dict(zip(FIELDS, ('GpuSettingsClient.qml', 'BatterySettingsClient.qml', 'NetbirdSettingsClient.qml', 'OpenvpnSettingsClient.qml', 'TailscaleSettingsClient.qml')))
ANCHORS = {
    'amd-gpu-monitor/Main.qml': ['_observations.set(index, {observer: observer, clients: new Set()})', 'entry.clients.add(client)', 'entry.clients.delete(client)', 'if (entry.clients.size === 0)', '_observations.delete(index)', 'entry.observer.destroy()'],
    'amd-gpu-monitor/GpuSettingsClient.qml': ['Math.floor(cfg.deviceIndex)', 'releaseObservation(_capturedIndex, root)', 'observation = acquireObservation(_capturedIndex, root)', 'old.unregisterPoller(_consumerId)', 'onDeviceIndexChanged: selectObservation()', 'release(); retire(root)', 'Component.onDestruction: release()'],
    'amd-gpu-monitor/GpuObservation.qml': ['required property int deviceIndex', 'String(deviceIndex)', 'onStreamFinished: root.parseRocmOutput(text)', 'readonly property bool shouldPoll: Object.keys(_consumers).length > 0', 'running: root.shouldPoll', 'triggeredOnStart: true', 'onTriggered: root.refreshNow()', 'function refreshNow() { if (!rocmProcess.running) rocmProcess.running = true; }'],
    'amd-gpu-monitor/Settings.qml': ['settingsConsumerFor(pluginApi.runtimeContext)', 'result.refreshState !== "current"', 'root.mainInstance?.refreshNow()'],
    'battery-monitor-plus/Main.qml': ['deviceNativePath: path', '_observations.set(path, {observer: observer, clients: new Set()})', 'entry.clients.delete(client)', 'if (entry.clients.size === 0)', '_observations.delete(path)', 'entry.observer.destroy()', 'retired.releaseObservationLease()'],
    'battery-monitor-plus/BatterySettingsClient.qml': ['readonly property int refreshIntervalSeconds: Math.max(1, cfg.refreshIntervalSeconds ?? defaults.refreshIntervalSeconds ?? 5)', 'sourceInterval: refreshIntervalSeconds', 'intervalScale: 1000', 'requestRefresh: function() { observation?.scanSysfs(); }', 'releaseObservation(_capturedPath, root)', 'observation = acquireObservation(_capturedPath, root)', 'onDeviceNativePathChanged: selectObservation()'],
    'battery-monitor-plus/BatteryObservation.qml': ['BatteryService.findDevice(deviceNativePath)', 'BatteryService.isDevicePresent(device) ? device : null', '(aggregateSelection ? (BatteryService.laptopBatteries[0] || null) : null)', 'root.deviceNativePath]', 'if (direct > 0 || !aggregateSelection) return direct', 'if (!BatteryService.isDeviceReady(selectedDevice)) return 0'],
    'netbird/NetbirdSettingsClient.qml': ['sourceInterval: cfg.refreshInterval ?? 5000', 'onShowPingChanged: observation.updatePingDemand()', 'observation.normalizeManagementUrl(cfg.managementUrl ?? "")', 'readonly property string detectedTerminal: observation.detectedTerminal'],
    'netbird/Main.qml': ['root.updatePingDemand()', 'client.current && client.showPing', 'pingQueue = []; currentPingIp = ""; pingProcess.running = false', 'if (!root.pingRequested || ip === "") return', 'if (!root.pingRequested || root.pingQueue.length === 0)'],
    'netbird/Panel.qml': ['pluginApi?.pluginSettings?.terminalCommand', 'mainInstance?.detectedTerminal', 'Quickshell.execDetached(buildTerminalCmd(["ssh", selectedPeer.netbirdIp]))', 'Quickshell.execDetached(buildTerminalCmd(["ping", "-c", root.pingCount.toString(), selectedPeer.netbirdIp]))'],
    'openvpn3/OpenvpnSettingsClient.qml': ['readonly property int pollInterval: (cfg.pollInterval ?? 5) * 1000', 'interval: Math.max(root.pollInterval * 3, 15000)', 'running: root.current && root.panelOpen', 'panels.set(token, logs)', 'observation.updatePanelDemand()', 'observation.connectTo(path, showNotifications)', 'observation.disconnectFrom(path, showNotifications)', 'observation.restartSession(path, showNotifications)', 'observation.importConfig(path, name, persistent, showNotifications)', 'observation.renameConfig(path, name, showNotifications)', 'observation.deleteConfig(path, showNotifications)'],
    'openvpn3/Main.qml': ['client.current && client.panelOpen && client.logStreamActive', '_syncLogStream()', '_connectProc.notifyErrors = notificationPolicy === undefined ? showNotifications : notificationPolicy', 'if (exitCode !== 0 && notifyErrors)', '_logProc.running = false'],
    'openvpn3/Panel.qml': ['_panelClient.unregisterPanel(_panelToken)', 'main.registerPanel(_panelToken, _logsRequested)', 'onVisibleChanged: syncPanelDemand()', 'Component.onDestruction:', 'root.syncPanelDemand()'],
    'tailscale/TailscaleSettingsClient.qml': ['sourceInterval: cfg.refreshInterval ?? 5000', 'observation.loginTailscale(cfg.loginServer || "")', 'context: context', 'enabled: taildropEnabled', 'directory: taildropDownloadDir', 'mode: taildropReceiveMode', 'current: function() { return context.current(); }', 'observation.sendFilesViaTaildrop(files, peerTarget, taildropEnabled)'],
    'tailscale/Main.qml': ['root.cancelTaildropReceive(context)', 'if (_taildropOperation !== operation || !taildropRequestCurrent()) return', '_taildropOperation = null; _taildropRequest = null', 'operation.cancel(); operation.destroy()', 'root._taildropOperation.start()', 'selectedLoginServer === undefined ? pluginApi?.pluginSettings?.loginServer || "" : selectedLoginServer'],
    'tailscale/TaildropReceive.qml': ['function current() { return active && request.current(); }', 'preScan.running = false; receive.running = false; postScan.running = false', 'if (!root.current()) return', '["tailscale", "file", "get", root.request.directory]', 'postScan.command = ["ls", "-1", root.request.directory]', 'root.completed(root, {ok: true, files: added})'],
}


def check(sources, manifests, dictionaries):
    code = {path: syntax.compact(text)[0] for path, text in sources.items()}
    rows = []
    for name, mapping in FIELDS.items():
        fields = {field for values in mapping.values() for field in values.split()}
        if fields != set(manifests[name]['metadata']['settingsSchema']['fields']):
            raise ValueError(name + ': declared field set differs')
        main = code[name + '/Main.qml']
        for anchor in ('property var _settingsConsumers: new Map()', 'if (!context || !context.current()) return null', 'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)', 'settingsContext: context', 'root._settingsConsumers.delete(context)', 'retired.destroy()', '_settingsConsumers.set(context, client)'):
            syntax.require(main, anchor, name + ': captured cache/retirement: ' + anchor)
        syntax.require(code[name + '/' + CLIENTS[name]], 'settingsContext.settingsView', name + ': selected client read')
        for filename, keys in mapping.items():
            source = code[name + '/' + filename]
            for key in keys.split():
                pattern = r'(?:cfg|pluginSettings)(?:\?|)\.' + key + r'\b|cfgBool\("' + key + r'"'
                if not re.search(pattern, source):
                    raise ValueError(name + ': selected leaf missing: ' + filename + '/' + key)
            if filename in ('BarWidget.qml', 'Panel.qml'):
                syntax.require(source, 'pluginApi?.pluginSettings', name + ': local runtime API read')
        entries = {value for key, value in manifests[name]['entryPoints'].items() if key in {'barWidget', 'panel', 'controlCenterWidget', 'desktopWidget', 'launcherProvider'}}
        for entry in entries:
            source = code[name + '/' + entry]
            syntax.require(source, 'settingsConsumerFor(pluginApi.settingsContext)', name + ': selected runtime entry: ' + entry)
            without = source.replace('pluginApi?.mainInstance?.settingsConsumerFor(pluginApi.settingsContext)', '')
            if 'pluginApi?.mainInstance' in without:
                raise ValueError(name + ': extra shared Main edge')
        settings = code[name + '/Settings.qml']
        for anchor in ('visible: root.pluginApi?.scopeKind === "instance"', 'root.pluginApi?.tr("settings.shared-effect")'):
            syntax.require(settings, anchor, name + ': shared-effect UI')
        for locale, data in dictionaries[name].items():
            if not data.get('settings', {}).get('shared-effect', '').strip():
                raise ValueError(name + ': missing shared-effect dictionary: ' + locale)
        rows.append(dict(plugin=name, fields=sorted(fields), runtimeEntries=sorted(entries)))
    for path, anchors in ANCHORS.items():
        for anchor in anchors:
            syntax.require(code[path], anchor, path + ': reviewed owner/action: ' + anchor)
    fallback = 'if (direct > 0 || !aggregateSelection) return direct'
    if code['battery-monitor-plus/BatteryObservation.qml'].count(syntax.squash(fallback)) != 2:
        raise ValueError('battery-monitor-plus: both power and time forbid foreign-device fallback')
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
        dictionaries[name] = {path.stem: json.loads(path.read_text()) for path in (args.plugins / name / 'i18n').glob('*.json')}
        sources.update({name + '/' + path.name: path.read_text() for path in (args.plugins / name).glob('*.qml')})
    rows = check(sources, manifests, dictionaries)
    controls = []
    if args.selftest:
        mutations = []
        for name in FIELDS:
            mutations += [(name + '/BarWidget.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.base.settingsContext)', 'wrong-context'),
                          (name + '/Main.qml', 'root._settingsConsumers.delete(context)', '/* retained */', 'missing-retirement'),
                          (name + '/' + CLIENTS[name], 'settingsContext.settingsView', 'observation.pluginApi.pluginSettings', 'shared-client-read')]
        mutations += [('amd-gpu-monitor/Main.qml', 'entry.observer.destroy()', 'entry.observer', 'retained-gpu-observer'),
                      ('amd-gpu-monitor/GpuObservation.qml', 'running: root.shouldPoll', 'running: true', 'unowned-gpu-poll'),
                      ('amd-gpu-monitor/GpuObservation.qml', 'if (!rocmProcess.running)', 'if (true)', 'overlapping-gpu-refresh'),
                      ('battery-monitor-plus/BatteryObservation.qml', 'if (direct > 0 || !aggregateSelection) return direct', 'if (direct > 0) return direct', 'foreign-battery-fallback'),
                      ('netbird/Main.qml', 'pingProcess.running = false', 'pingProcess.running = true', 'retained-last-ping'),
                      ('openvpn3/OpenvpnSettingsClient.qml', 'observation.connectTo(path, showNotifications)', 'observation.connectTo(path)', 'lost-originating-notification'),
                      ('tailscale/Main.qml', 'if (_taildropOperation !== operation || !taildropRequestCurrent()) return', 'if (!taildropRequestCurrent()) return', 'lost-operation-identity')]
        for path, old, new, label in mutations:
            expected = 2 if label == 'foreign-battery-fallback' else 1
            if sources[path].count(old) != expected:
                raise RuntimeError('stale device-policy control: ' + path + '/' + label)
            changed = dict(sources); changed[path] = changed[path].replace(old, new, 1)
            try:
                check(changed, manifests, dictionaries)
            except ValueError as error:
                controls.append(dict(path=path, control=label, rejectedAt=str(error)))
            else:
                raise RuntimeError('device-policy control escaped: ' + path + '/' + label)
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-device-policy-contract', members=rows, controls=controls, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_DEVICE_POLICY_CHECK: PASS (%d members, %d controls)' % (len(rows), len(controls)))


if __name__ == '__main__':
    main()
