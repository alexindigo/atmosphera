#!/usr/bin/env python3
"""Finite parsed G3a service/inhibitor mapping; not general JavaScript proof."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('resource_syntax', Path(__file__).with_name('plugin-settings-action-group-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
MEMBERS = {
    'agent-session-status': {'bindAddress', 'port', 'token', 'pollIntervalSec', 'hideWhenEmpty'},
    'clamshell': {'enabled', 'alwaysShowBarWidget', 'notify', 'internalConnectorRegex', 'inhibitorWho'},
}
ANCHORS = {
    'agent-session-status/Main.qml': [
        'property int admittedPort: 0', 'admittedPort = Number(values.port ?? defaults.port ?? 55854)',
        'context = context || pluginApi?.settingsContext', 'if (retired || !context?.current()) return null',
        'const values = context.settingsView', 'port: admittedPort', 'token: String(values.token ?? defaults.token ?? "")',
        'host: String(values.bindAddress ?? defaults.bindAddress ?? "127.0.0.1")',
        'new Map()', '_settingsConsumers.has(context)', '_settingsConsumers.get(context)', '_settingsConsumers.set(context, client)',
        'Math.max(1, Number(context.settingsView.pollIntervalSec ?? defaults.pollIntervalSec ?? 2))',
        'intervalScale: 1000', 'root.serviceRunning || root.serviceStarting', 'root.refresh(context)',
        'root._settingsConsumers.delete(context)', 'value.destroy()',
        'readonly property bool serviceCurrent: !retired && (servicePolicy?.context?.current() ?? false)',
        'readonly property bool pendingCurrent: !retired && (pendingPolicy?.context?.current() ?? false)',
        'if (root.servicePolicy === policy && !root.policyCurrent(policy)) root.stopService()',
        'if (root.pendingPolicy === policy && !policy.context.current())',
        'interval: 300', 'onTriggered: root.startService()', 'if (!pendingCurrent) return',
        'if (serviceProcess.running) { restartDelay.restart(); return; }',
        'servicePolicy = pendingPolicy', 'pendingPolicy = null', 'if (!root.token || root.token.trim() === "")',
        '"--host", root.bindAddress, "--port", root.port.toString(), "--token", root.token',
        'function restartService(context) { const policy = capturePolicy(context); if (!policy) return false; stopService(); pendingPolicy = policy',
        'for (const request of old) request.abort()', 'serviceProcess.signal(15)',
        'return !retired && policy && policy === servicePolicy && policy.context.current()',
        'const policy = servicePolicy', 'if (!context?.current() || !policyCurrent(policy)) return false',
        'requests = requests.concat([xhr])', 'if (!context.current() || !policyCurrent(policy)) return',
        'const url = "http://" + policy.host + ":" + policy.port',
        'if (prune) xhr.setRequestHeader("Authorization", "Bearer " + policy.token)',
        'root.applySnapshot(prune ? (payload.snapshot ?? payload) : payload)',
        'Qt.callLater(function() { if (root && root.policyCurrent(admitted)) root.refresh(); })',
        'Component.onCompleted: { Logger.i("AgentSessionStatus", "Plugin loaded"); restartService(); }',
        'retired = true; stopService()',
    ],
    'agent-session-status/BarWidget.qml': ['mainInstance?.settingsConsumerFor(pluginApi.settingsContext)', 'pluginApi?.pluginSettings?.hideWhenEmpty'],
    'agent-session-status/Panel.qml': ['mainInstance?.settingsConsumerFor(pluginApi.settingsContext)', 'root.mainInstance?.serverUrl', 'root.mainInstance?.agents'],
    'clamshell/Main.qml': [
        'readonly property var policyContext: selectedContext || pluginApi?.settingsContext',
        'readonly property bool policyCurrent: !retired && (policyContext?.current() ?? false)',
        'readonly property var cfg: policyCurrent ? policyContext.settingsView : ({})',
        'readonly property bool enabled: policyCurrent &&', 'cfg.enabled', 'cfg.notify', 'cfg.inhibitorWho', 'cfg.internalConnectorRegex',
        'function applySettings(context)', 'if (retired || !context?.current()) return false', 'selectedContext = context',
        'classifyOutputs(root.lastOutputsPayload)', 'const context = runtimeApi?.settingsContext',
        'runtimeApi.pluginSettings.enabled = value', 'runtimeApi.saveSettings()', 'return applySettings(context)',
        'root.disable(runtimeApi)', 'root.enable(runtimeApi)', 'new RegExp(root.internalConnectorRegex)',
        'if (componentReady && lastOutputsPayload) classifyOutputs(lastOutputsPayload)',
        'if (!root.selectedContext) root.setEnabled(false, root.pluginApi)',
        'command: ["niri", "msg", "--json", "outputs"]', 'command: ["niri", "msg", "--json", "event-stream"]',
        'property var policy: null', 'root.notifyInhibitorChange(true, inhibitorProc.policy)',
        'root.notifyInhibitorChange(false, inhibitorProc.policy)', 'Qt.callLater(root.reconcileInhibitor)',
        'const wanted = policyCurrent && enabled && externalPresent && inhibitorAvailable',
        'if (inhibitorProc.running)', 'previous.context !== policyContext', 'previous.who !== inhibitorWho', 'previous.notify !== notifyEnabled',
        'const policy = {context: policyContext, who: inhibitorWho, notify: notifyEnabled}',
        '"systemd-inhibit", "--what=handle-lid-switch", "--who=" + policy.who',
        'if (!root.componentReady || retired || !policy?.context?.current() || !policy.notify) return',
        'root.retired = true', 'backoffTimer.stop()', 'eventStreamProc.running = false', 'inhibitorProc.running = false',
    ],
    'clamshell/BarWidget.qml': ['cfg.alwaysShowBarWidget', 'root.main.toggle(pluginApi)'],
    'clamshell/ControlCenterWidget.qml': ['root.main.toggle(pluginApi)'],
}


def check(sources, manifests, dictionaries):
    codes = {path: syntax.syntax.compact(text)[0] for path, text in sources.items()}
    rows = []
    for name, fields in MEMBERS.items():
        descriptor = manifests[name]
        if set(descriptor['metadata']['settingsSchema']['fields']) != fields:
            raise ValueError(name+': unreviewed declared fields')
        entries = dict(main='Main.qml', settings='Settings.qml', barWidget='BarWidget.qml')
        entries.update({'panel': 'Panel.qml'} if name == 'agent-session-status' else {'controlCenterWidget': 'ControlCenterWidget.qml'})
        if descriptor['entryPoints'] != entries:
            raise ValueError(name+': unreviewed runtime entry')
        if set(path for path in sources if path.startswith(name+'/')) != set(name+'/'+value for value in entries.values()):
            raise ValueError(name+': unreviewed loaded QML component')
        for path, code in codes.items():
            if not path.startswith(name+'/'): continue
            text = sources[path]; raw = text.encode(); tree = syntax.syntax.compact(text)[1]
            processes = sum(node.type == 'ui_object_definition' and bool(re.match(rb'Process\s*\{', raw[node.start_byte:node.end_byte])) for node in syntax.syntax.walk(tree.root_node))
            if processes != ({'agent-session-status': 1, 'clamshell': 4}[name] if path.endswith('/Main.qml') else 0) or 'execDetached(' in code:
                raise ValueError(name+': singular resource owner '+path)
        main = codes[name+'/Main.qml']
        if name == 'agent-session-status' and 'pluginSettings' in main:
            raise ValueError(name+': shared preference reader/writer')
        if name == 'agent-session-status' and main.count('if(!root)return') != 2:
            raise ValueError(name+': destroyed delayed owner guards')
        if name == 'clamshell' and 'pluginSettings' in main.replace('runtimeApi.pluginSettings.enabled=value', ''):
            raise ValueError(name+': unreviewed native writer')
        page = codes[name+'/Settings.qml']
        syntax.require(page, 'visible: root.pluginApi?.scopeKind === "instance"', name+': shared-effect visibility')
        syntax.require(page, 'root.pluginApi?.tr("settings.shared-effect")', name+': shared-effect copy')
        syntax.require(page, 'result.refreshState !== "current"', name+': truthful page completion')
        method = 'restartService' if name == 'agent-session-status' else 'applySettings'
        syntax.require(page, method+'(root.pluginApi.runtimeContext)', name+': selected page admission')
        for locale, dictionary in dictionaries[name].items():
            if not dictionary.get('settings', {}).get('shared-effect', '').strip():
                raise ValueError(name+': missing explanation '+locale)
        # Every public originating action edge is a finite parsed call set.
        for method in (('restartService', 'refreshAndPrune') if name == 'agent-session-status' else ('toggle',)):
            actual = sorted((path, match[1]) for path, code in codes.items() if path.startswith(name+'/') for match in re.finditer(r'(?:\?\.|\.)'+method+r'\(([^()]*)\)', code))
            if name == 'agent-session-status':
                expected = [(name+'/Main.qml', '')]
                expected += [(name+'/BarWidget.qml', 'pluginApi.settingsContext')] * (1 if method == 'restartService' else 2)
                expected += [(name+'/Panel.qml', 'pluginApi.settingsContext')]
                if method == 'restartService': expected += [(name+'/Settings.qml', 'root.pluginApi.runtimeContext')]
            else:
                expected = [(name+'/Main.qml', ''), (name+'/BarWidget.qml', 'pluginApi'), (name+'/ControlCenterWidget.qml', 'pluginApi')]
            if actual != sorted(expected):
                raise ValueError(name+': originating callers '+method)
        rows.append(dict(plugin=name, fields=sorted(fields), entries=entries, resourceOwner='Main'))
    for path, anchors in ANCHORS.items():
        for anchor in anchors:
            syntax.require(codes[path], anchor, path+': '+anchor)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('plugins', 'report'): parser.add_argument('--'+key, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true'); args = parser.parse_args()
    sources = {name+'/'+path.name: path.read_text() for name in MEMBERS for path in (args.plugins/name).glob('*.qml')}
    manifests = {name: json.loads((args.plugins/name/'manifest.json').read_text()) for name in MEMBERS}
    dictionaries = {name: {path.name: json.loads(path.read_text()) for path in (args.plugins/name/'i18n').glob('*.json')} for name in MEMBERS}
    rows = check(sources, manifests, dictionaries); controls = []
    if args.selftest:
        mutations = [
            ('agent-session-status/Settings.qml', 'restartService(root.pluginApi.runtimeContext)', 'restartService()', 'omitted-page-origin'),
            ('agent-session-status/BarWidget.qml', 'restartService(pluginApi.settingsContext)', 'restartService()', 'omitted-bar-origin'),
            ('agent-session-status/Main.qml', 'const values = context.settingsView', 'const values = pluginApi.settingsView', 'shared-service-policy'),
            ('agent-session-status/Main.qml', 'property int admittedPort', 'property real admittedPort', 'port-type-domain'),
            ('agent-session-status/Main.qml', 'intervalScale: 1000', 'intervalScale: 1', 'polling-units'),
            ('agent-session-status/Main.qml', 'policy.token)', 'root.token)', 'mutable-prune-token'),
            ('agent-session-status/Main.qml', '!context.current() || !policyCurrent(policy)', '!context.current()', 'stale-http-generation'),
            ('agent-session-status/Main.qml', 'pendingPolicy = policy', 'pendingPolicy = capturePolicy()', 'mutable-queued-restart'),
            ('agent-session-status/Main.qml', 'if (!pendingCurrent) return', 'if (!pendingPolicy) return', 'retired-restart-admission'),
            ('clamshell/Settings.qml', 'applySettings(root.pluginApi.runtimeContext)', 'applySettings()', 'shared-inhibitor-page'),
            ('clamshell/BarWidget.qml', 'toggle(pluginApi)', 'toggle()', 'shared-toggle-writer'),
            ('clamshell/Main.qml', 'policyContext.settingsView', 'pluginApi.settingsView', 'shared-inhibitor-policy'),
            ('clamshell/Main.qml', 'runtimeApi.saveSettings()', 'pluginApi.saveSettings()', 'shared-native-writer'),
            ('clamshell/Main.qml', '"--who=" + policy.who', '"--who=" + inhibitorWho', 'mutable-inhibitor-argv'),
            ('clamshell/Main.qml', '!policy?.context?.current() || !policy.notify', '!policy.notify', 'retired-notification'),
            ('clamshell/BarWidget.qml', 'property var pluginApi: null', 'property var pluginApi: null\nProcess { command: ["true"] }', 'duplicate-inhibitor-owner'),
        ]
        for path, old, new, label in mutations:
            assert sources[path].count(old) == 1, label
            changed = dict(sources); changed[path] = changed[path].replace(old, new)
            try: check(changed, manifests, dictionaries)
            except ValueError as error: controls.append(dict(control=label, rejectedAt=str(error)))
            else: raise RuntimeError('resource control escaped '+label)
        for name in MEMBERS:
            changed = json.loads(json.dumps(manifests)); changed[name]['entryPoints']['barWidget'] = 'Unknown.qml'
            try: check(sources, changed, dictionaries)
            except ValueError as error: controls.append(dict(control='unreviewed-entry', plugin=name, rejectedAt=str(error)))
            else: raise RuntimeError('unreviewed resource entry escaped')
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-contract', members=rows, controls=controls, runtimeAcceptance=False, completeGroupAcceptance=False), indent=2)+'\n')
    print('PLUGIN_SETTINGS_RESOURCE_GROUP_CHECK: PASS (%d members, %d controls)' % (len(rows), len(controls)))


if __name__ == '__main__': main()
