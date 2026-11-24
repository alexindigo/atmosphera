#!/usr/bin/env python3
"""Finite parsed observation-policy contract for the admitted G1c subgroup."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('observation_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec)
spec.loader.exec_module(syntax)

MEMBERS = {
    'port-monitor': ('PortSettingsClient.qml', 'hideSystemPorts hideWhenEmpty refreshInterval'),
    'mullvad': ('MullvadSettingsClient.qml', 'clickAction compactMode confirmDisconnectInLockdown expiryWarningDays favoriteCountries refreshInterval relayClickConnects showCityName showCountryFlag showIp'),
}
ANCHORS = {
    'port-monitor/Main.qml': ['root.rawPorts = projectPorts(allPorts, false)', 'readonly property var portList: projectPorts(rawPorts, cfg.hideSystemPorts ?? defaults.hideSystemPorts ?? false)', 'Quickshell.execDetached(["kill", pid])', 'var portNum = parseInt(port)', 'portNum < 1 || portNum > 65535', 'proto === "TCP" ? "tcp" : "udp"'],
    'port-monitor/PortSettingsClient.qml': ['sourceInterval: (cfg.refreshInterval ?? defaults.refreshInterval ?? 5) * 1000', 'requestRefresh: function() { observation.refresh(); }', 'observation.projectPorts(observation.rawPorts, hideSystemPorts)', 'if (current) observation.killProcess(pid)', 'if (current) observation.killPortElevated(port, proto)'],
    'port-monitor/BarWidget.qml': ['pluginApi?.pluginSettings?.hideWhenEmpty', 'root.mainInstance?.refresh()'],
    'port-monitor/Panel.qml': ['root.pendingKillPid = modelData.pid ?? ""', 'root.mainInstance?.killProcess(root.pendingKillPid)', 'root.mainInstance?.killPortElevated(root.pendingKillPort, root.pendingKillProto)', 'root.mainInstance?.refresh()'],
    'port-monitor/Settings.qml': ['result.refreshState !== "current"', 'root.pluginApi.mainInstance?.refresh()'],
    'mullvad/MullvadSettingsClient.qml': ['sourceInterval: cfg.refreshInterval ?? defaults.refreshInterval ?? 3000', 'if (!observation.installed) observation.checkInstalled(); else observation.updateStatus()', 'state: observation.state', 'readonly property var currentLocation: observation.currentLocation', 'if (current) observation.toggleVpn()', 'if (current) observation.setLocation(country, city, hostname)'],
    'mullvad/Main.qml': ['id: accountTimer', 'interval: 5 * 60 * 1000', 'running: true', 'onTriggered: refreshAccount()', 'connectProcess.command = ["mullvad", "connect"]', 'disconnectProcess.command = ["mullvad", "disconnect"]', 'setLocationProcess.command = args'],
    'mullvad/BarWidget.qml': ['root.main?.clickAction || "toggle"', 'root.main?.toggleVpn()'],
    'mullvad/Panel.qml': ['root.main?.relayClickConnects ?? true', 'root.main?.favoriteCountries || []', 'root.main?.expiryWarningDays ?? 7', 'root.main?.setLockdown(checked)'],
    'shell/PluginSettingsPoller.qml': ['function refresh() { if (current) requestRefresh(); }', 'if (!current && _constructed) { poll.stop(); retire(root); }'],
}


def check(sources, manifests, dictionaries):
    rows = []
    for name, (client_file, field_text) in MEMBERS.items():
        main = syntax.compact(sources[name + '/Main.qml'])[0]
        for anchor in ('property var _settingsConsumers: new Map()', 'if (!context || !context.current()) return null', 'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)', 'settingsContext: context', 'observation: root', 'root._settingsConsumers.delete(context)', 'retired.destroy()', '_settingsConsumers.set(context, client)'):
            syntax.require(main, anchor, name + ': Main cache/lifetime contract: ' + anchor)
        client = syntax.compact(sources[name + '/' + client_file])[0]
        syntax.require(client, 'PluginSettingsPoller {', name + ': shared typed scheduler')
        syntax.require(client, 'readonly property var cfg: settingsContext.settingsView', name + ': captured selected read')
        fields = set(field_text.split())
        if fields != set(manifests[name]['metadata']['settingsSchema']['fields']):
            raise ValueError(name + ': declared field set changed')
        readers = client + syntax.compact(sources[name + '/BarWidget.qml'])[0]
        for field in fields:
            if not re.search(r'(?:cfg|pluginSettings)(?:\?|)\.' + field + r'\b', readers):
                raise ValueError(name + ': selected field mapping missing: ' + field)
        entries = {value for key, value in manifests[name]['entryPoints'].items() if key in {'barWidget', 'panel', 'desktopWidget', 'controlCenterWidget', 'launcherProvider'}}
        for entry in entries:
            code = syntax.compact(sources[name + '/' + entry])[0]
            syntax.require(code, 'settingsConsumerFor(pluginApi.settingsContext)', name + ': selected runtime entry: ' + entry)
            without = code.replace('pluginApi?.mainInstance?.settingsConsumerFor(pluginApi.settingsContext)', '')
            if 'pluginApi?.mainInstance' in without:
                raise ValueError(name + ': extra shared runtime Main edge')
        settings = syntax.compact(sources[name + '/Settings.qml'])[0]
        syntax.require(settings, 'visible: root.pluginApi?.scopeKind === "instance"', name + ': shared-effect scope')
        syntax.require(settings, 'root.pluginApi?.tr("settings.shared-effect")', name + ': shared-effect explanation')
        for locale, dictionary in dictionaries[name].items():
            if not dictionary.get('settings', {}).get('shared-effect', '').strip():
                raise ValueError(name + ': missing existing dictionary: ' + locale)
        rows.append(dict(plugin=name, fields=sorted(fields), runtimeEntries=sorted(entries)))
    for path, anchors in ANCHORS.items():
        code = syntax.compact(sources[path])[0]
        for anchor in anchors:
            syntax.require(code, anchor, path + ': reviewed observation/action mapping: ' + anchor)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'report'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true')
    args = parser.parse_args()
    sources = {'shell/PluginSettingsPoller.qml': (args.source / 'Services/Plugins/PluginSettingsPoller.qml').read_text()}
    manifests, dictionaries = {}, {}
    for member in MEMBERS:
        manifests[member] = json.loads((args.plugins / member / 'manifest.json').read_text())
        dictionaries[member] = {path.name: json.loads(path.read_text()) for path in (args.plugins / member / 'i18n').glob('*.json')}
        sources.update({member + '/' + path.name: path.read_text() for path in (args.plugins / member).glob('*.qml')})
    rows = check(sources, manifests, dictionaries)
    controls = []
    if args.selftest:
        mutations = []
        for member, (client_file, _) in MEMBERS.items():
            mutations += [(member + '/BarWidget.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.base.settingsContext)', 'wrong-entry-context'),
                          (member + '/Main.qml', 'root._settingsConsumers.delete(context)', '/* no retirement */', 'missing-retirement'),
                          (member + '/' + client_file, 'settingsContext.settingsView', 'observation.cfg', 'shared-policy-reader')]
        mutations += [('port-monitor/Main.qml', 'projectPorts(allPorts, false)', 'projectPorts(allPorts, true)', 'filtered-shared-observation'),
                      ('port-monitor/PortSettingsClient.qml', ') * 1000', ')', 'wrong-interval-unit'),
                      ('mullvad/MullvadSettingsClient.qml', 'cfg.relayClickConnects', 'observation.relayClickConnects', 'shared-relay-policy'),
                      ('mullvad/Main.qml', '5 * 60 * 1000', '3000', 'lost-account-timer'),
                      ('shell/PluginSettingsPoller.qml', 'requestRefresh();', '/* no refresh */', 'lost-inherited-refresh')]
        for path, old, new, label in mutations:
            if sources[path].count(old) != 1:
                raise RuntimeError('stale observation control ' + path + ': ' + label)
            mutated = dict(sources)
            mutated[path] = mutated[path].replace(old, new, 1)
            try:
                check(mutated, manifests, dictionaries)
            except ValueError as error:
                controls.append(dict(control=label, path=path, rejectedAt=str(error)))
            else:
                raise RuntimeError('observation control escaped: ' + label)
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-contract', members=rows, controls=controls, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_OBSERVATION_GROUP_CHECK: PASS (%d members, %d controls)' % (len(rows), len(controls)))


if __name__ == '__main__':
    main()
