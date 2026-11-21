#!/usr/bin/env python3
"""Finite parsed G1a consumer contract, not a general JavaScript semantic proof.

Check the reviewed factory, all manifest runtime entry bindings, exact domain
interval/default/guard/refresh mapping and singular process owners. Runtime
representatives separately prove native files, actual schedules and observations.
"""
import argparse
import json
from pathlib import Path
import re

from tree_sitter import Language, Parser
import tree_sitter_qmljs

PARSER = Parser(Language(tree_sitter_qmljs.language()))
MEMBERS = {
    'cloudflare-warp': dict(interval='context.settingsView.refreshInterval ?? 5000', guard='root.warpInstalled', refresh='root.refresh()', processes=4, timers=1,
                           fields={'refreshInterval', 'connectedColor', 'disconnectedColor'}),
    'monique': dict(interval='context.settingsView.refreshInterval ?? 5000', guard='root.moniqueInstalled', refresh='root.refresh()', processes=4, timers=0,
                    fields={'refreshInterval', 'activeColor', 'showProfileLabel'}),
    'ip-monitor': dict(interval='context.settingsView.refreshInterval ?? root.pluginApi?.manifest?.metadata?.defaultSettings?.refreshInterval ?? 300', guard=None, refresh='service.fetchIp()', processes=1, timers=0,
                       fields={'refreshInterval', 'iconColor', 'successIcon', 'errorIcon', 'loadingIcon'}),
    'battery-wireless-devices': dict(interval='var s = context.settingsView.refreshInterval; return (typeof s === "number" && s > 0) ? s : 60;', guard=None, refresh='root.refresh()', processes=1, timers=0,
                                    fields={'refreshInterval', 'showPercentage', 'showCharging', 'devices', 'deviceOrder'})
}


def walk(node):
    yield node
    for child in node.named_children:
        yield from walk(child)


def compact(source):
    data = source.encode(); tree = PARSER.parse(data)
    if tree.root_node.has_error:
        raise ValueError('unparsed QML consumer')
    def leaves(node):
        if 'comment' in node.type: return []
        if not node.children: return [data[node.start_byte:node.end_byte].decode()]
        return [value for child in node.children for value in leaves(child)]
    # qmlformat removes optional QML-binding semicolons. Parsing establishes
    # statement structure first; the finite expression contract ignores them.
    return ''.join(value for value in leaves(tree.root_node) if value != ';'), tree


def squash(source):
    return re.sub(r'[\s;]+', '', source)


def require(source, wanted, message):
    if squash(wanted) not in source:
        raise ValueError(message)


def check(sources, manifests):
    poll, _ = compact(sources['shell/PluginSettingsPoller.qml'])
    for wanted in ('required property var settingsContext', 'readonly property bool current: settingsContext.current()',
                   'required property int sourceInterval', 'property int intervalScale: 1',
                   'readonly property int interval: sourceInterval * intervalScale', 'property bool requirePositiveInterval: false',
                   'running: root.current && root.pollingEnabled && (!root.requirePositiveInterval || interval > 0)', 'interval: root.interval',
                   'onTriggered: root.refresh()', 'if (current) requestRefresh();',
                   'if (!current && _constructed) { poll.stop(); retire(root); }',
                   'Component.onDestruction: poll.stop()'):
        require(poll, wanted, 'poller context/lifetime/dispatch contract: ' + wanted)
    observed = []
    for name, spec in MEMBERS.items():
        manifest = manifests[name]
        if set(manifest['metadata']['settingsSchema']['fields']) != spec['fields']:
            raise ValueError(name + ': unreviewed declared configuration fields')
        source, tree = compact(sources[name + '/Main.qml'])
        for wanted in ('property var _settingsConsumers: new Map()', 'Component { id: pollFactory; PluginSettingsPoller {} }',
                       'if (!context || !context.current()) return null;', 'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context);',
                       'var client = pollFactory.createObject(root, {', 'settingsContext: context,',
                       'retire: function (retired) { root._settingsConsumers.delete(context); retired.destroy(); }',
                       '_settingsConsumers.set(context, client); return client;',
                       'readonly property var settingsConsumer: pluginApi ? settingsConsumerFor(pluginApi.settingsContext) : null'):
            require(source, wanted, name + ': selected Main factory/cache/retirement: ' + wanted)
        interval = spec['interval']
        body = interval if interval.startswith('var ') else 'return ' + interval + ';'
        require(source, 'sourceInterval: Qt.binding(function () { ' + body + ' }),', name + ': selected typed source interval/default mapping')
        if name in {'ip-monitor', 'battery-wireless-devices'}:
            require(source, 'intervalScale: 1000,', name + ': seconds convert after QML int coercion')
        elif 'intervalScale:' in source:
            raise ValueError(name + ': unreviewed millisecond scaling')
        if name == 'ip-monitor':
            require(source, 'requirePositiveInterval: true,', name + ': nonpositive disable policy')
        elif 'requirePositiveInterval:' in source:
            raise ValueError(name + ': new nonpositive disable policy')
        receiver = 'root.settingsConsumer' if name == 'ip-monitor' else 'settingsConsumer'
        fallback = 300 if name == 'ip-monitor' else 60 if name == 'battery-wireless-devices' else 5000
        require(source, 'readonly property int refreshInterval: ' + receiver + '?.sourceInterval ?? ' + str(fallback),
                name + ': compatibility projection must read typed source units, not reverse scaled milliseconds')
        require(source, 'requestRefresh: function () { ' + spec['refresh'] + '; },', name + ': existing shared observation callback')
        if spec['guard']:
            require(source, 'pollingEnabled: Qt.binding(function () { return ' + spec['guard'] + '; }),', name + ': existing installed guard')
            require(source, 'if (root.isRefreshing) return', name + ': existing busy guard')
        if 'pluginSettings' in source or '.settingsView.refreshInterval' in source.replace('context.settingsView.refreshInterval', ''):
            raise ValueError(name + ': shared Main interval reader remains')
        counts = {kind: sum(1 for node in walk(tree.root_node) if node.type == 'ui_object_definition' and sources[name + '/Main.qml'].encode()[node.start_byte:node.end_byte].lstrip().startswith((kind + ' {').encode())) for kind in ('Process', 'Timer')}
        if counts != dict(Process=spec['processes'], Timer=spec['timers']):
            raise ValueError(name + ': observation process or non-client Timer ownership changed: ' + str(counts))
        entries = {value for key, value in manifest['entryPoints'].items() if key in {'barWidget', 'panel', 'controlCenterWidget', 'desktopWidget', 'launcherProvider'}}
        for entry in entries:
            code, _ = compact(sources[name + '/' + entry])
            receiver = 'mainInstance' if name in {'cloudflare-warp', 'monique'} else 'pluginApi?.mainInstance'
            require(code, 'readonly property var settingsConsumer: ' + receiver + '?.settingsConsumerFor(pluginApi.settingsContext) ?? null', name + ': missing selected runtime entry: ' + entry)
        settings, _ = compact(sources[name + '/Settings.qml'])
        require(settings, 'visible: root.pluginApi?.scopeKind === "instance"', name + ': missing scoped shared-observation explanation')
        require(settings, 'text: root.pluginApi?.tr("settings.shared-observation") ?? ""', name + ': missing shared-observation text')
        for key in spec['fields']:
            require(settings, 'pluginApi?.field("' + key + '")', name + ': undeclared/unmapped page field ' + key)
        observed.append(dict(plugin=name, fields=sorted(spec['fields']), runtimeEntries=sorted(entries), interval=interval, installedGuard=spec['guard'], observationProcesses=counts['Process']))
    return observed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True); parser.add_argument('--plugins', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True); parser.add_argument('--selftest', action='store_true')
    args = parser.parse_args()
    sources = {'shell/PluginSettingsPoller.qml': (args.source / 'Services/Plugins/PluginSettingsPoller.qml').read_text()}
    manifests = {}
    for name in MEMBERS:
        manifests[name] = json.loads((args.plugins / name / 'manifest.json').read_text())
        sources.update({name + '/' + path.name: path.read_text() for path in (args.plugins / name).glob('*.qml')})
    results = check(sources, manifests)
    controls = []
    if args.selftest:
        for name, _, path, old, new in [
            ('shared-reader', '', plugin + '/Main.qml', 'context.settingsView.refreshInterval', 'root.pluginApi.settingsView.refreshInterval') for plugin in MEMBERS
        ] + [('missing-view', '', plugin + '/BarWidget.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.base.settingsContext)') for plugin in MEMBERS] + [
            ('retirement', '', 'shell/PluginSettingsPoller.qml', 'retire(root);', '/* missing retirement */'),
            ('source-coercion', '', 'shell/PluginSettingsPoller.qml', 'required property int sourceInterval', 'required property real sourceInterval'),
            ('running-policy', '', 'shell/PluginSettingsPoller.qml', 'property bool requirePositiveInterval: false', 'property bool requirePositiveInterval: true'),
            ('interval-unit', '', 'battery-wireless-devices/Main.qml', 'intervalScale: 1000,', 'intervalScale: 1,')]:
            mutated = dict(sources)
            if old not in mutated[path]: raise RuntimeError('stale polling control anchor ' + path)
            mutated[path] = mutated[path].replace(old, new, 1)
            try: check(mutated, manifests)
            except ValueError as error: controls.append(dict(control=name, path=path, rejectedAt=str(error)))
            else: raise RuntimeError('polling semantic control escaped: ' + path + '/' + name)
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-consumer-contract', members=results, controls=controls, runtimeProof=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_POLLING_CHECK: PASS (' + str(len(results)) + ' members, ' + str(len(controls)) + ' rejecting controls)')


if __name__ == '__main__': main()
