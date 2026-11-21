#!/usr/bin/env python3
"""Finite parsed G2 originating-action contract; not general JavaScript proof."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('action_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)


def require(code, anchor, message):
    # Preserve literal spaces in argv/environment strings. The shared compact
    # parser already removes inter-token whitespace, not string contents.
    parts = re.findall(r'"(?:[^"\\]|\\.)*"|\x27(?:[^\x27\\]|\\.)*\x27|[^\s;]', anchor)
    if ''.join(parts) not in code:
        raise ValueError(message)

MEMBERS = {
    'screencast-gif': {'fps', 'maxRecordingSeconds', 'outputDir'},
    'network-manager-vpn': {'displayMode', 'connectedColor', 'disconnectedColor', 'disableToastNotifications'},
}
ANCHORS = {
    'screencast-gif/Main.qml': [
        'function trigger(context)', 'context = context || pluginApi?.settingsContext',
        'if (!scriptPath || !context?.current()) return', 'const cfg = context.settingsView',
        'const fps = cfg.fps ?? defaults.fps ?? 20',
        'const maxSecs = cfg.maxRecordingSeconds ?? defaults.maxRecordingSeconds ?? 120',
        'const outDir = cfg.outputDir ?? defaults.outputDir ?? "~/Screenshots"',
        'const env = "FPS=" + fps + " MAX_SECS=" + maxSecs + " OUTDIR=" + shellQuote(outDir)',
        'Quickshell.execDetached(["sh", "-c", env + " " + shellQuote(scriptPath)])',
        'function toggle() { root.trigger(root.pluginApi?.settingsContext) }',
        'onTriggered: checker.running = true',
    ],
    'screencast-gif/BarWidget.qml': ['onClicked: pluginApi?.mainInstance?.trigger(pluginApi.settingsContext)', 'readonly property bool recording: pluginApi?.mainInstance?.recordingActive ?? false'],
    'network-manager-vpn/Main.qml': [
        'function capturePolicy(context)', 'context = context || pluginApi?.settingsContext',
        'if (!context?.current()) return null',
        'return { toast: context.settingsView.disableToastNotifications ? null : ToastService }',
        'onTriggered: root.refresh()',
        'command: ["nmcli", "-t", "-f", "NAME,TYPE,STATE,UUID", "connection", "show"]',
    ],
    'network-manager-vpn/Panel.qml': ['main.disconnectFrom(modelData.uuid, pluginApi.settingsContext)', 'main.connectTo(modelData.uuid, pluginApi.settingsContext)'],
    'network-manager-vpn/Settings.qml': ['main.removeConnection(root.pendingDeleteUuid, pluginApi.runtimeContext)'],
    'network-manager-vpn/BarWidget.qml': ['root.pluginSettings.displayMode', 'root.pluginSettings.connectedColor', 'root.pluginSettings.disconnectedColor', 'pluginApi.openPanel(root.screen, root)'],
    'network-manager-vpn/ControlCenterWidget.qml': ['pluginSettings.connectedColor', 'pluginSettings.disconnectedColor', 'onClicked: pluginApi?.togglePanel(screen, this)'],
}


def check(sources, manifests, dictionaries):
    rows = []
    for name, fields in MEMBERS.items():
        if fields != set(manifests[name]['metadata']['settingsSchema']['fields']):
            raise ValueError(name + ': declared field set changed')
        entries = dict(main='Main.qml', barWidget='BarWidget.qml', settings='Settings.qml')
        if name == 'network-manager-vpn': entries.update(panel='Panel.qml', controlCenterWidget='ControlCenterWidget.qml')
        if manifests[name]['entryPoints'] != entries:
            raise ValueError(name + ': unreviewed runtime entry mapping')
        codes = {path: syntax.compact(text)[0] for path, text in sources.items() if path.startswith(name + '/')}
        main = codes[name + '/Main.qml']
        tree = syntax.compact(sources[name + '/Main.qml'])[1]
        # Exactly the reviewed singular owner: GIF checker, VPN list and five
        # public command processes. A per-view physical owner fails this bound.
        types = [sources[name + '/Main.qml'].encode()[node.start_byte:node.end_byte].decode() for node in syntax.walk(tree.root_node) if node.type == 'ui_object_definition']
        processes = sum(bool(re.match(r'Process\s*\{', value)) for value in types)
        expected_processes = 1 if name == 'screencast-gif' else 6
        if processes != expected_processes:
            raise ValueError(name + ': sole reviewed physical process owner changed')
        if 'pluginSettings' in main:
            raise ValueError(name + ': shared namespace reader/writer in selected action owner')
        settings = codes[name + '/Settings.qml']
        for anchor in ('visible: root.pluginApi?.scopeKind === "instance"', 'root.pluginApi?.tr("settings.shared-effect")'):
            require(settings, anchor, name + ': shared-effect instance explanation')
        for locale, dictionary in dictionaries[name].items():
            if not dictionary.get('settings', {}).get('shared-effect', '').strip():
                raise ValueError(name + ': shared-effect dictionary missing: ' + locale)
        # Public action callers are a closed finite set, not a fingerprint-only
        # claim. Added/omitted call sites or shared-context injections reject.
        for method in (('trigger',) if name == 'screencast-gif' else ('connectTo', 'disconnectFrom', 'removeConnection')):
            calls = []
            for path, code in codes.items():
                for match in re.finditer(r'(?:\?\.|\.)' + method + r'\(([^()]*)\)', code):
                    calls.append((path, match.group(1)))
            expected = [('screencast-gif/Main.qml', 'root.pluginApi?.settingsContext'), ('screencast-gif/BarWidget.qml', 'pluginApi.settingsContext')] if name == 'screencast-gif' else [('network-manager-vpn/' + ('Settings.qml' if method == 'removeConnection' else 'Panel.qml'), 'root.pendingDeleteUuid,pluginApi.runtimeContext' if method == 'removeConnection' else 'modelData.uuid,pluginApi.settingsContext')]
            if sorted(calls) != sorted(expected):
                raise ValueError(name + ': unreviewed/missing originating caller: ' + method)
        if name == 'network-manager-vpn':
            for method, proc in [('connectTo', '_connectProc'), ('disconnectFrom', '_disconnectProc'), ('removeConnection', '_removeProc')]:
                require(main, 'function ' + method + '(uuid, context) { const policy = capturePolicy(context); if (!policy || ' + proc + '.running) return false; ' + proc + '.actionPolicy = policy;', name + ': captured policy admission: ' + method)
            if main.count('propertyvaractionPolicy:null') != 3 or main.count('actionPolicy?.toast?.') != 6:
                raise ValueError(name + ': every completion uses its admitted action policy')
        rows.append(dict(plugin=name, fields=sorted(fields), processOwners=processes, entries=manifests[name]['entryPoints']))
    for path, anchors in ANCHORS.items():
        code = syntax.compact(sources[path])[0]
        for anchor in anchors: require(code, anchor, path + ': selected action mapping: ' + anchor)
    return rows


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('source','plugins','report'):parser.add_argument('--'+key,type=Path,required=True)
    parser.add_argument('--selftest',action='store_true');args=parser.parse_args()
    sources={};manifests={};dictionaries={}
    for name in MEMBERS:
        manifests[name]=json.loads((args.plugins/name/'manifest.json').read_text())
        dictionaries[name]={p.name:json.loads(p.read_text()) for p in (args.plugins/name/'i18n').glob('*.json')}
        sources.update({name+'/'+p.name:p.read_text() for p in (args.plugins/name).glob('*.qml')})
    rows=check(sources,manifests,dictionaries);controls=[]
    if args.selftest:
        mutations=[('screencast-gif/BarWidget.qml','trigger(pluginApi.settingsContext)','trigger()','omitted-capture-caller'),
                   ('screencast-gif/Main.qml','const cfg = context.settingsView','const cfg = pluginApi.settingsView','shared-capture-input'),
                   ('screencast-gif/Main.qml','!context?.current()','!context','retired-capture-admission'),
                   ('network-manager-vpn/Panel.qml','connectTo(modelData.uuid, pluginApi.settingsContext)','connectTo(modelData.uuid)','omitted-vpn-caller'),
                   ('network-manager-vpn/Settings.qml','removeConnection(root.pendingDeleteUuid, pluginApi.runtimeContext)','removeConnection(root.pendingDeleteUuid)','omitted-page-action'),
                   ('network-manager-vpn/Main.qml','context.settingsView.disableToastNotifications','pluginApi.settingsView.disableToastNotifications','shared-vpn-policy'),
                   ('network-manager-vpn/Main.qml','_connectProc.actionPolicy = policy','_connectProc.actionPolicy = null','uncaptured-vpn-completion'),
                   ('network-manager-vpn/Main.qml','!context?.current()','!context','retired-vpn-admission'),
                   ('screencast-gif/Main.qml','const cfg = context.settingsView','pluginApi.pluginSettings.fps = 99; const cfg = context.settingsView','shared-capture-writer'),
                   ('network-manager-vpn/Main.qml','const policy = capturePolicy(context);','pluginApi.pluginSettings.disableToastNotifications = false; const policy = capturePolicy(context);','shared-vpn-writer')]
        for path,old,new,label in mutations:
            # Admission appears in three VPN actions; change the first one for
            # the added shared-writer control, not a suppressing source baseline.
            if sources[path].count(old)!=1 and label!='shared-vpn-writer':raise RuntimeError('stale G2 control: '+label)
            changed=dict(sources);changed[path]=sources[path].replace(old,new,1)
            try:check(changed,manifests,dictionaries)
            except ValueError as error:controls.append(dict(control=label,rejectedAt=str(error)))
            else:raise RuntimeError('G2 control escaped: '+label)
        for name in MEMBERS:
            changed=json.loads(json.dumps(manifests));changed[name]['entryPoints']['barWidget']='Unreviewed.qml'
            try:check(sources,changed,dictionaries)
            except ValueError as error:controls.append(dict(control='unreviewed-runtime-entry',plugin=name,rejectedAt=str(error)))
            else:raise RuntimeError('G2 runtime entry control escaped: '+name)
    args.report.write_text(json.dumps(dict(status='PASS',kind='finite-parsed-contract',members=rows,controls=controls,runtimeAcceptance=False,completeGroupAcceptance=False),indent=2)+'\n')
    print('PLUGIN_SETTINGS_ACTION_GROUP_CHECK: PASS (%d members, %d controls)'%(len(rows),len(controls)))


if __name__=='__main__':main()
