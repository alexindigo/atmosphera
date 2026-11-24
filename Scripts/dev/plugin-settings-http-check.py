#!/usr/bin/env python3
"""Finite parsed G1e fields, producers, immutable chains and retained writers."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('http_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
FIELDS = {
    'news': {'NewsSettingsClient.qml': 'apiKey country language category refreshInterval maxHeadlines', 'BarWidget.qml': 'rollingSpeed widgetWidth'},
    'ntfy-notifications': {'NtfySettingsClient.qml': 'serverUrl topics authMethod authToken authUsername authPassword pollInterval enableToasts maxMessages', 'Main.qml': 'readMessageIds'},
    'habitica': {'HabiticaSettingsClient.qml': 'habiticaUserId habiticaApiToken refreshInterval maxDailies maxTodos maxHabits showHabits enableTagFilter selectedTagId', 'BarWidget.qml': 'showNotificationBadge colorizationEnabled colorizationIcon colorizationBadge colorizationBadgeText', 'Panel.qml': 'showChecklistItems', 'Main.qml': '_habiticaCache'},
}
CLIENTS = dict(zip(FIELDS, ('NewsSettingsClient.qml', 'NtfySettingsClient.qml', 'HabiticaSettingsClient.qml')))
ANCHORS = {
    'news/NewsSettingsClient.qml': ['readonly property int refreshInterval: cfg.refreshInterval || defaults.refreshInterval || 30', 'interval: client.refreshInterval * 60 * 1000', 'var generation = _generation, limit = maxHeadlines', 'countryLanguageMap[country] || language || "en"', 'encodeURIComponent(query)', 'response.articles.slice(0, limit)', 'generation !== client._generation || client._request !== xhr', 'previous.abort()', 'newsData = []', 'onSourceKeyChanged: if (_constructed) replaceSource()'],
    'news/BarWidget.qml': ['readonly property var main: settingsConsumer', 'text: parent.displayText', 'duration: newsText.contentWidth * rollingSpeed', 'return widgetWidth'],
    'ntfy-notifications/NtfySettingsClient.qml': ['readonly property string sourceKey: JSON.stringify([serverUrl, topics, authMethod, authToken, authUsername, authPassword])', 'interval: client.pollInterval * 1000', 'if (!xhr || _request !== xhr) return false; xhr.onreadystatechange = function() {}; deadline.stop(); _request = null; return true', 'if (xhr.readyState !== XMLHttpRequest.DONE || !client.current || !client._releaseRequest(xhr)) return', 'if (_releaseRequest(xhr)) xhr.abort()', 'cancel(); messages = []; lastPollTimestamp = 0', 'onSourceKeyChanged: if (_constructed) replaceSource()', 'Component.onDestruction: cancel()', 'observation.showToasts(client, server, trulyNew)', 'observation.persistReadIds(client, [messageId])', 'observation.persistReadIds(client, messages.map(message => message.id))', 'observation.readMessageIdIndex.has(messageId)'],
    'ntfy-notifications/Main.qml': ['_settingsConsumers.get(caller.settingsContext) !== caller', 'readonly property var readMessageIdIndex: new Set(readMessageIds)', 'var merged = new Set(readMessageIdIndex)', 'merged.add(id)', 'pluginApi.pluginSettings.readMessageIds = Array.from(merged)', 'root._notified.has(key)', 'root._notified.add(key)', 'JSON.stringify([server, message.id])'],
    'habitica/HabiticaSettingsClient.qml': ['readonly property string sourceKey: JSON.stringify([userId, apiToken, refreshInterval, showHabits, enableTagFilter])', 'var old = _worker; _worker = null; old.active = false; old.destroy()', 'configuration: Object.freeze({userId: userId, apiToken: apiToken, refreshInterval: refreshInterval, showHabits: showHabits, enableTagFilter: enableTagFilter})', 'limitTasks(filterTasks(dailies, "daily"), maxDailies)', 'limitTasks(filterTasks(todos, "todo"), maxTodos)', 'limitTasks(filterTasks(habits, "habit"), maxHabits)', 'var tag = enableTagFilter ? selectedTagId : ""'],
    'habitica/HabiticaQueryWorker.qml': ['if (!active || !client.current || !isConfigured || apiProcess.running) return false', '"x-api-user: " + userId.trim()', '"x-api-key: " + apiToken.trim()', 'if (worker.active && worker.client.current) worker.handleApiResponse', 'if (!worker.active || !worker.client.current) return', 'nextRequestTimer.stop(); apiProcess.running = false; releaseScore()', 'observation.saveCache(client, worker,', 'observation.claimScore(worker)', 'observation.releaseScore(worker)', 'encodeURIComponent(taskId)', 'encodeURIComponent(item.id)', 'interval: worker.refreshInterval * 1000'],
    'habitica/Main.qml': ['caller === settingsConsumer && caller.current && caller._worker === worker && worker.active', 'cached.schema === 1 && cached.sourceUserId === worker.userId', 'pluginApi.pluginSettings._habiticaCache = JSON.stringify(Object.assign({schema: 1, sourceUserId: worker.userId}, data))', '(_scoreOwner && _scoreOwner !== worker)', 'if (_scoreOwner === worker) _scoreOwner = null'],
}


def check(sources, manifests, dictionaries):
    # Parse every source first; normalize whitespace symmetrically for the finite
    # anchors. Literal header/URL bytes are separately checked at inert endpoints.
    code = {path: syntax.squash(syntax.compact(text)[0]) for path, text in sources.items()}
    rows = []
    for name, mapping in FIELDS.items():
        fields = {field for keys in mapping.values() for field in keys.split()}
        declared = manifests[name]['metadata']['settingsSchema']['fields']
        if fields != set(declared): raise ValueError(name + ': unreviewed declared leaves')
        operational = {key for key, value in declared.items() if value['editorUsage'] == 'operational'}
        if operational != ({'readMessageIds'} if name == 'ntfy-notifications' else {'_habiticaCache'} if name == 'habitica' else set()): raise ValueError(name + ': protected leaf reclassification')
        main = code[name + '/Main.qml']
        for anchor in ('property var _settingsConsumers: new Map()', 'if (!context || !context.current()) return null', 'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)', 'settingsContext: context', 'root._settingsConsumers.delete(context)', 'retired.destroy()', '_settingsConsumers.set(context, client)'):
            syntax.require(main, anchor, name + ': captured factory/cache/retirement: ' + anchor)
        client = code[name + '/' + CLIENTS[name]]
        for anchor in ('settingsContext.settingsView', 'settingsContext.current()', 'onCurrentChanged: if (!current && _constructed)', 'retire(client)'):
            syntax.require(client, anchor, name + ': selected lifetime: ' + anchor)
        for filename, keys in mapping.items():
            for key in keys.split():
                if not re.search(r'(?:cfg|pluginSettings)(?:\?|)\.' + re.escape(key) + r'\b', code[name + '/' + filename]): raise ValueError(name + ': selected field mapping missing: ' + key)
        entries = {value for key, value in manifests[name]['entryPoints'].items() if key in {'barWidget', 'panel', 'controlCenterWidget', 'desktopWidget', 'launcherProvider'}}
        for entry in entries:
            syntax.require(code[name + '/' + entry], 'settingsConsumerFor(pluginApi.settingsContext)', name + ': selected runtime entry: ' + entry)
        if name != 'news':
            for anchor in ('visible: root.pluginApi?.scopeKind === "instance"', 'root.pluginApi?.tr("settings.shared-effect")'):
                syntax.require(code[name + '/Settings.qml'], anchor, name + ': explicit shared-effect UI')
            for locale, dictionary in dictionaries[name].items():
                if not dictionary.get('settings', {}).get('shared-effect', '').strip(): raise ValueError(name + ': missing shared-effect locale: ' + locale)
        rows.append(dict(plugin=name, fields=sorted(fields), operational=sorted(operational), runtimeEntries=sorted(entries)))
    for path, anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(code[path], anchor, path + ': HTTP ownership contract: ' + anchor)
    for name, leaf in [('ntfy-notifications', 'readMessageIds'), ('habitica', '_habiticaCache')]:
        writers = []
        for path, text in sources.items():
            if not path.startswith(name + '/'): continue
            _, tree = syntax.compact(text); data = text.encode()
            for node in syntax.walk(tree.root_node):
                if node.type != 'assignment_expression': continue
                left = node.child_by_field_name('left')
                if left is None: continue
                target = syntax.squash(data[left.start_byte:left.end_byte].decode())
                if target.endswith('.pluginSettings.' + leaf): writers.append((path, target))
        if writers != [(name + '/Main.qml', 'pluginApi.pluginSettings.' + leaf)]:
            raise ValueError(name + ': original operational writer identity changed: ' + str(writers))
    for name in ('news', 'ntfy-notifications'):
        bar = code[name + '/BarWidget.qml']
        if 'newXMLHttpRequest(' in bar or 'Timer{' in bar: raise ValueError(name + ': duplicated view request producer')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'report'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true'); args = parser.parse_args()
    sources, manifests, dictionaries = {}, {}, {}
    for name in FIELDS:
        manifests[name] = json.loads((args.plugins / name / 'manifest.json').read_text())
        dictionaries[name] = {p.stem: json.loads(p.read_text()) for p in (args.plugins / name / 'i18n').glob('*.json')}
        sources.update({name + '/' + str(p.relative_to(args.plugins / name)): p.read_text() for p in (args.plugins / name).rglob('*.qml')})
    rows = check(sources, manifests, dictionaries); controls = []
    if args.selftest:
        mutations = [(name + '/Main.qml', 'root._settingsConsumers.delete(context)', 'context', 'retirement') for name in FIELDS]
        mutations += [(name + '/Panel.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.base.settingsContext)', 'shared-view') for name in FIELDS]
        mutations += [('news/NewsSettingsClient.qml', 'generation !== client._generation || client._request !== xhr', 'false', 'late-source'), ('news/NewsSettingsClient.qml', 'interval: client.refreshInterval * 60 * 1000', 'interval: 1000', 'typed-timer'), ('ntfy-notifications/Main.qml', 'root._notified.has(key)', 'false', 'duplicate-toast'), ('ntfy-notifications/Main.qml', 'pluginApi.pluginSettings.readMessageIds = merged', 'caller.pluginApi.pluginSettings.readMessageIds = merged', 'operational-writer'), ('habitica/Main.qml', 'caller === settingsConsumer', 'true', 'cache-owner'), ('habitica/Main.qml', 'cached.schema === 1 && cached.sourceUserId === worker.userId', 'true', 'unqualified-cache'), ('habitica/HabiticaQueryWorker.qml', 'nextRequestTimer.stop(); apiProcess.running = false; releaseScore()', 'releaseScore()', 'chain-retirement'), ('habitica/Main.qml', '(_scoreOwner && _scoreOwner !== worker)', 'false', 'common-score-admission')]
        mutations = [(p, o.replace('readMessageIds = merged', 'readMessageIds = Array.from(merged)'), n.replace('readMessageIds = merged', 'readMessageIds = Array.from(merged)'), label) if label == 'operational-writer' else (p, o, n, label) for p, o, n, label in mutations]
        mutations += [('ntfy-notifications/NtfySettingsClient.qml', '_request !== xhr', 'false', 'ntfy-stale-request'),
                      ('ntfy-notifications/NtfySettingsClient.qml', '!client.current || !client._releaseRequest(xhr)', '!client._releaseRequest(xhr)', 'ntfy-retired-response')]
        for path, old, new, label in mutations:
            if sources[path].count(old) != 1: raise RuntimeError('stale HTTP control: ' + path + '/' + old)
            changed = dict(sources); changed[path] = sources[path].replace(old, new)
            try: check(changed, manifests, dictionaries)
            except ValueError as error: controls.append(dict(path=path, control=label, rejectedAt=str(error)))
            else: raise RuntimeError('HTTP control escaped: ' + label)
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-http-contract', members=rows, controls=controls, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_HTTP_CHECK: PASS (%d members, %d controls)' % (len(rows), len(controls)))


if __name__ == '__main__': main()
