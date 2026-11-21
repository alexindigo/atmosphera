#!/usr/bin/env python3
"""Finite parsed G1b contract for ten reviewed consumer mappings, not runtime proof."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('poll_check', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)

# Every declared field is checked in these reviewed runtime readers. Inline
# clients are isolated to their factory subtree, not Main's compatibility cfg.
MEMBERS = {
 'latency-monitor': ('LatencySettingsClient.qml', 'animations barHost colorCritical colorGood colorWarning hosts intervalSeconds showHostName thresholdGood thresholdWarning', []),
 'ramadan-iftar': ('PrayerSettingsClient.qml', 'city country method showAlways showCountdown', ['BarWidget.qml']),
 'mpris-lyric': ('MprisSettingsClient.qml', 'hideWhenInactive playerName updateInterval width', ['BarWidget.qml']),
 'hassio': ('HassSettingsClient.qml', 'entities haToken haUrl', ['HassQueryWorker.qml', 'BrowserView.qml']),
 'syncthing-status': ('SyncthingSettingsClient.qml', 'apiKey apiUrl configPath enabled folderIds pollIntervalMs verifyTls', []),
 'kubectl-ctx': ('KubectlSettingsClient.qml', 'iconColor kubeconfigPath panelHeight panelWidth pollInterval showErrorBadge terminal', ['BarWidget.qml', 'Panel.qml']),
 'update-count': ('UpdateSettingsClient.qml', 'currentIconName customCmdDoSystemUpdate customCmdGetNumUpdates hideOnZero updateIntervalMinutes updateTerminalCommand', ['BarWidget.qml']),
 'keep-awake-plus': (None, 'activateOnLeftClick defaultScope durations includeUnlimited quickExtendMinutes showRemainingText', []),
 'lyrics-fetch': (None, 'adaptScrollSpeed fontFamily fontSize hideWhenEmpty hideWhenPaused scrollMode scrollSpeed verticalRotationDirection widgetWidth', ['BarWidget.qml']),
 'ssh-sessions': (None, 'pollInterval showInactiveHosts terminalCommand', []),
}
ANCHORS = {
 'latency-monitor/LatencySettingsClient.qml': ['readonly property var cfg: settingsContext.settingsView', 'intervalMs: intervalSeconds * 1000', 'thresholdGood: thresholdGood', 'thresholdWarning: thresholdWarning', 'h.stop()', 'h.destroy()', 'retire(root)', 'function _queueHosts() { if (!_constructed) return; _retireHosts(); replacement.restart(); }', 'onHostsCfgChanged: _queueHosts()', 'onIntervalSecondsChanged: _queueHosts()', 'replacement.stop(); _retireHosts(); retire(root)'],
 'latency-monitor/Host.qml': ['if (!root.active) return', 'active = false', '_timer.stop()', 'proc.running = false', 'running: root.active', 'root.address'],
 'ramadan-iftar/PrayerSettingsClient.qml': ['JSON.stringify([city, country, method])', '_retireWorker()', 'old.stop()', 'old.destroy()', 'city: city, country: country, method: method', 'retire(root)'],
 'ramadan-iftar/PrayerQueryWorker.qml': ['required property string city', 'required property string country', 'required property int method', 'if (!root.active) return', 'fetchProcess.running = false', 'running: root.active && prayerTimings !== null'],
 'mpris-lyric/MprisSettingsClient.qml': ['readonly property var cfg: settingsContext.settingsView', 'if (current) forceRefreshLyrics()', 'enabled: root.current && root.targetPlayer !== null', 'running: root.current && root.isPlaying && root.parsedLyrics.length > 0', 'identity.includes(playerName.toLowerCase())', 'retire(root)'],
 'hassio/HassSettingsClient.qml': ['JSON.stringify([haUrl, haToken])', 'old.stop()', 'old.destroy(); sourceChanged()', 'haUrl: haUrl, haToken: haToken', 'retire(root)'],
 'hassio/BrowserView.qml': ['function _invalidate()', '_requestId++; _allEntities = []; _filteredModel.clear(); _loading = false', 'function onSourceChanged() { root._invalidate(); }', 'function onAuthenticatedChanged()', 'if (root.main?.authenticated) root._fetchAll(); else root._invalidate()', 'if (!_requested || !root.main?.authenticated) return', 'const owner = root.main', 'const request = ++root._requestId', 'if (root.main !== owner || root._requestId !== request) return'],
 'hassio/HassQueryWorker.qml': ['required property string haUrl', 'required property string haToken', 'settingsContext.settingsView.entities', 'active: root.active && url !== ""', 'if (!root.active) return', '_pendingCallbacks = ({})', '_socket.active = false'],
 'hassio/Settings.qml': ['settingsConsumerFor(root.pluginApi.runtimeContext)?.reloadSettings()', 'result.refreshState !== "current"'],
 'syncthing-status/SyncthingSettingsClient.qml': ['JSON.stringify([apiUrl, apiKey, configPath, verifyTls, folderIds])', 'old.stop()', 'old.destroy()', 'runtimeApi?.settingsContext !== settingsContext', 'runtimeApi.pluginSettings.folderIds = Array.from(ids)', 'runtimeApi.saveSettings()', 'retire(root)'],
 'syncthing-status/SyncthingQueryWorker.qml': ['required property string apiUrl', 'required property string apiKey', 'required property string configPath', 'required property bool verifyTls', 'required property var folderIds', 'readonly property var settings: settingsContext.settingsView', 'if (!root.active) return', 'pollProcess.running = false', 'running: root.active && root.enabled'],
 'syncthing-status/Settings.qml': ['settingsConsumerFor(pluginApi.runtimeContext)', 'result.refreshState !== "current"', 'root.mainInst?.requestPoll(true)'],
 'kubectl-ctx/KubectlSettingsClient.qml': ['onKubeconfigPathChanged: _replaceQuery()', 'old.stop()', 'old.destroy()', 'kubeconfigPath: kubeconfigPath', 'retire(root)'],
 'kubectl-ctx/KubectlQueryWorker.qml': ['required property string kubeconfigPath', 'readonly property var cfg: settingsContext.settingsView', 'base = base.concat(["--kubeconfig", root.kubeconfigPath])', 'running: root.active', 'process.running = false', 'if (!active) return'],
 'update-count/UpdateSettingsClient.qml': ['customUpdater.cmdGetNumUpdates || updater?.cmdGetNumUpdates || ""', 'old.stop()', 'old.destroy()', 'queryCommand: _queryCommand', 'interval: root.updateIntervalMinutes * 60000', 'running: root.current', 'domain.performSystemUpdate(customUpdater.cmdDoSystemUpdate || updater?.cmdDoSystemUpdate ||', 'updateTerminalCommand)', 'retire(root)'],
 'update-count/UpdateCountQueryWorker.qml': ['required property string queryCommand', 'command: ["sh", "-c", root.queryCommand]', 'if (!root.active) return', 'query.running = false'],
 'update-count/Main.qml': ['function performSystemUpdate(updateCmd, terminalCommand)', 'const term = terminalCommand.trim()', 'doSystemUpdate.command = ["sh", "-c", fullCmd]'],
 'update-count/Settings.qml': ['settingsConsumerFor(root.pluginApi.runtimeContext)?.startGetNumUpdates()', 'result.refreshState !== "current"'],
 'keep-awake-plus/Main.qml': ['readonly property var cfg: settingsContext.settingsView', 'readonly property bool active: root.active', 'readonly property var endEpoch: root.endEpoch', 'if (current) root.start(seconds, scope)', 'if (current) root.extend(seconds)', 'retire(client)'],
 'lyrics-fetch/Main.qml': ['readonly property var cfg: settingsContext.settingsView', 'readonly property string currentLyric: root.lyricFor(hideWhenPaused, hideWhenEmpty)', 'function lyricFor(hidePaused, hideEmpty)', 'retire(client)'],
 'ssh-sessions/Main.qml': ['PluginSettingsPoller {', 'readonly property var cfg: settingsContext.settingsView', 'sourceInterval: (cfg.pollInterval ?? root.defaults.pollInterval ?? 10) * 1000', 'root.sortedHostsFor(cfg.showInactiveHosts ?? root.defaults.showInactiveHosts ?? true)', 'if (current) root.connectWithTerminal(name, terminalCommand)', 'requestRefresh: function() { root.refreshSessions()']
}
SHARED = {'mpris-lyric', 'hassio', 'kubectl-ctx', 'update-count', 'keep-awake-plus', 'lyrics-fetch'}
ROUTE_ONLY = {'kubectl-ctx/ControlCenterWidget.qml': 'pluginApi.togglePanel(screen, this)'}


def subtree(source):
    data = source.encode(); _, tree = syntax.compact(source)
    for node in syntax.walk(tree.root_node):
        if node.type == 'ui_object_definition':
            text = data[node.start_byte:node.end_byte].decode()
            if re.match(r'Component\s*\{\s*id:\s*clientFactory\b', text):
                return syntax.compact(text)[0]
    raise ValueError('missing inline client factory subtree')


def check(sources, manifests):
    rows = []
    for name, (client_file, fields, direct) in MEMBERS.items():
        main = syntax.compact(sources[name + '/Main.qml'])[0]
        for anchor in ('property var _settingsConsumers: new Map()', 'if (!context || !context.current()) return null',
                       'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)',
                       'settingsContext: context', 'root._settingsConsumers.delete(context)', 'retired.destroy()',
                       '_settingsConsumers.set(context, client)', 'return client'):
            syntax.require(main, anchor, name + ': Main context factory/cache/retirement: ' + anchor)
        client = syntax.compact(sources[name + '/' + client_file])[0] if client_file else subtree(sources[name + '/Main.qml'])
        syntax.require(client, 'settingsContext', name + ': client context missing')
        if not any(syntax.squash(anchor) in client for anchor in (
                'readonly property var cfg: settingsContext.settingsView',
                'readonly property var cfg: settingsContext?.settingsView ?? ({})')):
            raise ValueError(name + ': client must read the captured settings view')
        wanted_fields = set(fields.split())
        if set(manifests[name]['metadata']['settingsSchema']['fields']) != wanted_fields:
            raise ValueError(name + ': unreviewed declared field set')
        readers = client + ''.join(syntax.compact(sources[name + '/' + path])[0] for path in direct)
        for field in wanted_fields:
            if not re.search(r'(?:cfg|settingsView|pluginSettings)(?:\?|)\.' + re.escape(field) + r'\b', readers):
                raise ValueError(name + ': selected field mapping missing: ' + field)
        entries = {path.split('?')[0] for kind, path in manifests[name]['entryPoints'].items()
                   if kind in {'barWidget', 'panel', 'controlCenterWidget', 'desktopWidget', 'launcherProvider'}}
        for entry in entries:
            code = syntax.compact(sources[name + '/' + entry])[0]
            if name + '/' + entry in ROUTE_ONLY:
                if 'mainInstance' in code:
                    raise ValueError(name + ': route-only entry gained an unreviewed Main consumer')
                syntax.require(code, ROUTE_ONLY[name + '/' + entry], name + ': originating API must open its own selected Panel')
                continue
            syntax.require(code, 'settingsConsumerFor(pluginApi.settingsContext)', name + ': missing selected runtime entry: ' + entry)
            # The actual runtime API is injected by PluginLoader; no other direct
            # shared Main dereference is admitted in these reviewed entry roots.
            without_selection = code.replace('pluginApi?.mainInstance?.settingsConsumerFor(pluginApi.settingsContext)', '')
            if 'pluginApi?.mainInstance' in without_selection:
                raise ValueError(name + ': extra shared runtime Main edge: ' + entry)
        if name in SHARED:
            code = syntax.compact(sources[name + '/Settings.qml'])[0]
            syntax.require(code, 'visible: root.pluginApi?.scopeKind === "instance"', name + ': missing shared-effect scope')
            syntax.require(code, 'root.pluginApi?.tr("settings.shared-effect")', name + ': missing shared-effect explanation')
        rows.append(dict(plugin=name, declaredFields=sorted(wanted_fields), runtimeEntries=sorted(entries)))
    for path, anchors in ANCHORS.items():
        code = syntax.compact(sources[path])[0]
        for anchor in anchors:
            syntax.require(code, anchor, path + ': reviewed consumer mapping missing: ' + anchor)
    for path, interval in [('ramadan-iftar/PrayerSettingsClient.qml', 0), ('hassio/HassSettingsClient.qml', 300), ('syncthing-status/SyncthingSettingsClient.qml', 0)]:
        code = syntax.compact(sources[path])[0]
        for anchor in ('function _queueQuery()', '_retireWorker(); replacement.restart()', 'interval: ' + str(interval), 'on_QueryIdentityChanged: _queueQuery()', 'replacement.stop()'):
            syntax.require(code, anchor, path + ': settled typed source capture/lifetime: ' + anchor)
    poll = syntax.compact(sources['shell/PluginSettingsPoller.qml'])[0]
    syntax.require(poll, 'if (!current && _constructed) { poll.stop(); retire(root); }', 'shared scheduler retirement')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'report'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true'); args = parser.parse_args()
    sources = {'shell/PluginSettingsPoller.qml': (args.source / 'Services/Plugins/PluginSettingsPoller.qml').read_text()}
    manifests = {}
    for member in MEMBERS:
        manifests[member] = json.loads((args.plugins / member / 'manifest.json').read_text())
        sources.update({member + '/' + path.name: path.read_text() for path in (args.plugins / member).glob('*.qml')})
    rows = check(sources, manifests); controls = []
    if args.selftest:
        for member in MEMBERS:
            entry = next(path for kind, path in manifests[member]['entryPoints'].items() if kind in {'barWidget', 'panel'})
            path = member + '/' + entry
            old = 'settingsConsumerFor(pluginApi.settingsContext)'
            mutated = dict(sources); mutated[path] = mutated[path].replace(old, 'settingsConsumerFor(pluginApi.base.settingsContext)', 1)
            try: check(mutated, manifests)
            except ValueError as error: controls.append(dict(plugin=member, control='wrong-entry-context', rejectedAt=str(error)))
            else: raise RuntimeError('wrong-context control escaped: ' + member)
            path = member + '/Main.qml'; mutated = dict(sources)
            mutated[path] = mutated[path].replace('root._settingsConsumers.delete(context)', '/* omitted retirement */', 1)
            try: check(mutated, manifests)
            except ValueError as error: controls.append(dict(plugin=member, control='missing-retirement', rejectedAt=str(error)))
            else: raise RuntimeError('retirement control escaped: ' + member)
            client_file = MEMBERS[member][0] or 'Main.qml'
            path = member + '/' + client_file; mutated = dict(sources)
            old = 'settingsContext?.settingsView' if 'settingsContext?.settingsView' in sources[path] else 'settingsContext.settingsView'
            if old not in sources[path]: raise RuntimeError('stale selected-reader control ' + member)
            mutated[path] = mutated[path].replace(old, 'pluginApi.pluginSettings', 1)
            try: check(mutated, manifests)
            except ValueError as error: controls.append(dict(plugin=member, control='shared-policy-reader', rejectedAt=str(error)))
            else: raise RuntimeError('shared-policy-reader control escaped: ' + member)
        for path, old, new, name in (
            ('latency-monitor/LatencySettingsClient.qml', '_retireHosts();\n    replacement.restart();', 'replacement.restart();', 'deferred-host-retirement'),
            ('hassio/BrowserView.qml', '_allEntities = [];', '/* retain old entities */', 'retained-browser-cache'),
            ('hassio/BrowserView.qml', 'if (root.main !== owner || root._requestId !== request) return;', '/* accept old callback */', 'unfenced-browser-callback')):
            if sources[path].count(old) != 1: raise RuntimeError('stale handoff control ' + name)
            mutated = dict(sources); mutated[path] = mutated[path].replace(old, new, 1)
            try: check(mutated, manifests)
            except ValueError as error: controls.append(dict(control=name, rejectedAt=str(error)))
            else: raise RuntimeError('handoff control escaped: ' + name)
        for member in ('hassio', 'syncthing-status', 'update-count'):
            path = member + '/Settings.qml'; mutated = dict(sources)
            if sources[path].count('pluginApi.runtimeContext') != 1: raise RuntimeError('stale Settings completion control: ' + member)
            mutated[path] = mutated[path].replace('pluginApi.runtimeContext', 'pluginApi.settingsContext', 1)
            try: check(mutated, manifests)
            except ValueError as error: controls.append(dict(plugin=member, control='wrong-page-completion-context', rejectedAt=str(error)))
            else: raise RuntimeError('Settings completion control escaped: ' + member)
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-contract', members=rows, controls=controls, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_QUERY_GROUP_CHECK: PASS (%d members, %d controls)' % (len(rows), len(controls)))


if __name__ == '__main__': main()
