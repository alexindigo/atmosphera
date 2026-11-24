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
    'ds4-colors': {'color', 'colorIcon', 'hideOnEmpty', 'recentColors'},
    'nvibrant': {'displayIndex', 'enabled', 'vibranceValue'},
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
    'network-manager-vpn/Panel.qml': ['function requestConnection(uuid, connect) { const context = pluginApi?.settingsContext; const result = connect ? main?.connectTo(uuid, context) : main?.disconnectFrom(uuid, context)', 'onButtonClicked: root.requestConnection(modelData.uuid, false)', 'onButtonClicked: root.requestConnection(modelData.uuid, true)'],
    'network-manager-vpn/Settings.qml': ['main?.removeConnection(pendingDeleteUuid, pluginApi?.runtimeContext)'],
    'network-manager-vpn/BarWidget.qml': ['root.pluginSettings.displayMode', 'root.pluginSettings.connectedColor', 'root.pluginSettings.disconnectedColor', 'pluginApi.openPanel(root.screen, root)'],
    'network-manager-vpn/ControlCenterWidget.qml': ['pluginSettings.connectedColor', 'pluginSettings.disconnectedColor', 'onClicked: pluginApi?.togglePanel(screen, this)'],
}


def hardware(name, codes):
    main = codes[name + '/Main.qml']
    bar = codes[name + '/BarWidget.qml']
    calls = {}
    for path,code in codes.items():
        for match in re.finditer(r'(?:\?\.|\.)(applyColors|setColor|applyVibrance|toggle)\(([^()]*)\)',code):
            calls.setdefault(match[1],[]).append((path,match[2]))
    if name == 'ds4-colors':
        expected = {'applyColors':[(name+'/Main.qml',''),(name+'/Settings.qml','root.pluginApi.runtimeContext,root.valueColor')],
                    'setColor':[(name+'/Main.qml','r,g,b'),(name+'/Main.qml','r,g,b'),(name+'/Main.qml','0,0,0')]}
        anchors = [
            'function setColor(r, g, b, runtimeApi, context)',
            'if (!context?.current() || isApplying) return false',
            'if (runtimeApi && runtimeApi.settingsContext !== context) return false',
            'context: context, writer: runtimeApi || null',
            'rgb: [currentR, currentG, currentB]',
            'targets.push({path: path, red: controller.red, green: controller.green, blue: controller.blue, separator: controller.separator})',
            'controllers: targets', 'const controller = target',
            'target.path, target.separator, String(admitted.rgb[0])',
            'if (success && operation.context.current() && operation.writer)',
            'operation.writer.pluginSettings.color = "#" + operation.rgb.map(value => value.toString(16).padStart(2, "0")).join("")',
            'operation.writer.saveSettings()',
            'if (!operation.context.current()) { finishColor(operation, false); return }',
            'colorWriter.operation = operation', 'pkexecRunner.operation = admitted',
            'String(operation.rgb[0]), String(operation.rgb[1]), String(operation.rgb[2])',
            'String(admitted.rgb[0]), String(admitted.rgb[1]), String(admitted.rgb[2])',
            'root.applyNextController(admitted)',
            'function applyColors(context, acceptedColor)', 'const cfg = context.settingsView',
            'const selectedColor = acceptedColor ?? cfg?.color', 'const color = Qt.color(selectedColor)',
            'Math.round(color.b * 255), null, context',
            'root.applyColors()', 'root.setColor(r, g, b)', 'root.setColor(0, 0, 0)',
        ]
        require(codes[name+'/Settings.qml'], 'root.pluginApi.mainInstance?.applyColors(root.pluginApi.runtimeContext, root.valueColor)', name+': selected page completion')
        for anchor in ('cfg.color', 'cfg.colorIcon', 'cfg.hideOnEmpty', 'charged: false'):
            require(bar, anchor, name+': selected Bar '+anchor)
        if 'pluginSettings' in main.replace('operation.writer.pluginSettings.color', ''):
            raise ValueError(name+': unreviewed shared writer')
        if 'Qt.callLater' in main or 'saveCurrentColor' in main:
            raise ValueError(name+': mutable deferred color boundary')
        if main.count('propertyvaroperation:null') != 2:
            raise ValueError(name+': every process owns its admitted operation')
    else:
        expected = {'toggle':[(name+'/Main.qml',''),(name+'/BarWidget.qml','pluginApi'),(name+'/BarWidget.qml',''),(name+'/BarWidget.qml','')]}
        anchors = [
            'property int admittedDisplayIndex: 0', 'property int admittedVibranceValue: 0',
            'function buildCmd(value, display)', 'for (var i = 0; i < display; i++)',
            'parts.push(value.toString())', 'return parts',
            'function applyVibrance(value, context)', 'context = context || pluginApi?.settingsContext',
            'if (!context?.current()) return false',
            'admittedDisplayIndex = (context.settingsView.displayIndex ?? defaults.displayIndex ?? 1) - 1',
            'admittedVibranceValue = value',
            'Quickshell.execDetached(buildCmd(admittedVibranceValue, admittedDisplayIndex))',
            'function toggle(runtimeApi)', 'runtimeApi = runtimeApi || pluginApi',
            'const context = runtimeApi?.settingsContext', 'const selected = context.settingsView',
            'const newEnabled = !(selected.enabled ?? defaults.enabled ?? false)',
            'const value = selected.vibranceValue ?? defaults.vibranceValue ?? 512',
            'runtimeApi.pluginSettings.enabled = newEnabled', 'runtimeApi.saveSettings()',
            'return applyVibrance(newEnabled ? value : 0, context)', 'function toggle() { root.toggle() }',
        ]
        require(bar, 'return pluginApi?.mainInstance?.toggle(pluginApi) ?? false', name+': originating runtime writer')
        if 'execDetached' in bar or 'buildCmd' in bar or 'saveSettings' in bar:
            raise ValueError(name+': duplicate physical command/writer in view')
        if 'pluginApi.pluginSettings.' in main:
            raise ValueError(name+': shared native writer')
    for anchor in anchors:require(main,anchor,name+': admitted hardware mapping: '+anchor)
    if {key:sorted(value) for key,value in calls.items()} != {key:sorted(value) for key,value in expected.items()}:
        raise ValueError(name+': unreviewed originating hardware callers')


def check(sources, manifests, dictionaries):
    rows = []
    for name, fields in MEMBERS.items():
        if fields != set(manifests[name]['metadata']['settingsSchema']['fields']):
            raise ValueError(name + ': declared field set changed')
        entries = dict(main='Main.qml', barWidget='BarWidget.qml', settings='Settings.qml')
        if name == 'network-manager-vpn': entries.update(panel='Panel.qml', controlCenterWidget='ControlCenterWidget.qml')
        if manifests[name]['entryPoints'] != entries:
            raise ValueError(name + ': unreviewed runtime entry mapping')
        parsed = {path: syntax.compact(text) for path, text in sources.items() if path.startswith(name + '/')}
        codes = {path: unit[0] for path, unit in parsed.items()}
        main = codes[name + '/Main.qml']
        owner = name + '/Main.qml'
        # Exactly the reviewed singular owner: GIF checker, VPN list and five
        # public command processes. A per-view physical owner fails this bound.
        processes = syntax.object_types(sources[owner], parsed[owner][1]).count('Process')
        expected_processes = {'screencast-gif':1,'network-manager-vpn':6,'ds4-colors':4,'nvibrant':0}[name]
        if processes != expected_processes:
            raise ValueError(name + ': sole reviewed physical process owner changed')
        # Count every reviewed plugin component, not only Main. A second
        # physical owner in a Bar/page/helper cannot hide behind Main's count.
        for path, (_, tree) in parsed.items():
            detached = sum(1 for _ in syntax.member_calls(sources[path], tree, {'execDetached'}))
            if path == owner:
                if detached != int(name in ('screencast-gif', 'nvibrant')):
                    raise ValueError(name+': unreviewed detached effect owner')
            elif 'Process' in syntax.object_types(sources[path], tree) or detached:
                raise ValueError(name+': physical effect outside Main: '+path)
        if name in ('screencast-gif','network-manager-vpn') and 'pluginSettings' in main:
            raise ValueError(name + ': shared namespace reader/writer in selected action owner')
        settings = codes[name + '/Settings.qml']
        for anchor in ('visible: root.pluginApi?.scopeKind === "instance"', 'root.pluginApi?.tr("settings.shared-effect")'):
            require(settings, anchor, name + ': shared-effect instance explanation')
        for locale, dictionary in dictionaries[name].items():
            if not dictionary.get('settings', {}).get('shared-effect', '').strip():
                raise ValueError(name + ': shared-effect dictionary missing: ' + locale)
        if name in ('ds4-colors','nvibrant'):
            hardware(name,codes)
            rows.append(dict(plugin=name,fields=sorted(fields),processOwners=processes,entries=manifests[name]['entryPoints']))
            continue
        # Public action callers are a closed finite set, not a fingerprint-only
        # claim. Added/omitted call sites or shared-context injections reject.
        for method in (('trigger',) if name == 'screencast-gif' else ('connectTo', 'disconnectFrom', 'removeConnection')):
            calls = []
            for path, (_, tree) in parsed.items():
                for _, _, args in syntax.member_calls(sources[path], tree, {method}):
                    calls.append((path, args))
            expected = [('screencast-gif/Main.qml', 'root.pluginApi?.settingsContext'), ('screencast-gif/BarWidget.qml', 'pluginApi.settingsContext')] if name == 'screencast-gif' else [('network-manager-vpn/' + ('Settings.qml' if method == 'removeConnection' else 'Panel.qml'), 'pendingDeleteUuid,pluginApi?.runtimeContext' if method == 'removeConnection' else 'uuid,context')]
            if sorted(calls) != sorted((path, tuple(args.split(','))) for path, args in expected):
                raise ValueError(name + ': unreviewed/missing originating caller: ' + method)
        if name == 'network-manager-vpn':
            for method, proc in [('connectTo', '_connectProc'), ('disconnectFrom', '_disconnectProc'), ('removeConnection', '_removeProc')]:
                require(main, 'function ' + method + '(uuid, context) { const policy = capturePolicy(context); if (!policy) return "stale"; if (' + proc + '.running) return "busy"; ' + proc + '.actionPolicy = policy;', name + ': captured policy admission: ' + method)
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
        sources.update(syntax.qml_sources(args.plugins, name))
    rows=check(sources,manifests,dictionaries);controls=[]
    if args.selftest:
        mutations=[('screencast-gif/BarWidget.qml','trigger(pluginApi.settingsContext)','trigger()','omitted-capture-caller'),
                   ('screencast-gif/BarWidget.qml','trigger(pluginApi.settingsContext)','trigger(pluginApi.settingsContext); mainInstance?.trigger(wrongContext())','nested-argument-caller'),
                   ('screencast-gif/Main.qml','const cfg = context.settingsView','const cfg = pluginApi.settingsView','shared-capture-input'),
                   ('screencast-gif/Main.qml','!context?.current()','!context','retired-capture-admission'),
                   ('network-manager-vpn/Panel.qml','connectTo(uuid, context)','connectTo(uuid)','omitted-vpn-caller'),
                   ('network-manager-vpn/Settings.qml','removeConnection(pendingDeleteUuid, pluginApi?.runtimeContext)','removeConnection(pendingDeleteUuid)','omitted-page-action'),
                   ('network-manager-vpn/Main.qml','context.settingsView.disableToastNotifications','pluginApi.settingsView.disableToastNotifications','shared-vpn-policy'),
                   ('network-manager-vpn/Main.qml','_connectProc.actionPolicy = policy','_connectProc.actionPolicy = null','uncaptured-vpn-completion'),
                   ('network-manager-vpn/Main.qml','!context?.current()','!context','retired-vpn-admission'),
                   ('screencast-gif/Main.qml','const cfg = context.settingsView','pluginApi.pluginSettings.fps = 99; const cfg = context.settingsView','shared-capture-writer'),
                    ('network-manager-vpn/Main.qml','const policy = capturePolicy(context);','pluginApi.pluginSettings.disableToastNotifications = false; const policy = capturePolicy(context);','shared-vpn-writer')]
        mutations += [
            ('ds4-colors/Settings.qml','applyColors(root.pluginApi.runtimeContext, root.valueColor)','applyColors()','omitted-ds4-page-context'),
            ('ds4-colors/Main.qml','String(operation.rgb[0])','String(root.currentR)','mutable-ds4-direct'),
            ('ds4-colors/Main.qml','String(admitted.rgb[0])','String(root.currentR)','mutable-ds4-elevation'),
            ('ds4-colors/Main.qml','controllers: targets','controllers: Object.values(controllers)','mutable-ds4-controller-alias'),
            ('ds4-colors/Main.qml','operation.writer.saveSettings()','pluginApi.saveSettings()','shared-ds4-writer'),
            ('ds4-colors/Main.qml','success && operation.context.current() && operation.writer','success && operation.writer','retired-ds4-publication'),
            ('nvibrant/BarWidget.qml','toggle(pluginApi)','toggle()','omitted-nvibrant-writer'),
            ('nvibrant/Main.qml','context.settingsView.displayIndex','cfg.displayIndex','shared-nvibrant-display'),
            ('nvibrant/Main.qml','runtimeApi.pluginSettings.enabled','pluginApi.pluginSettings.enabled','shared-nvibrant-writer'),
            ('nvibrant/Main.qml','property int admittedVibranceValue','property real admittedVibranceValue','untyped-nvibrant-command'),
            ('ds4-colors/BarWidget.qml','property var pluginApi: null','property var pluginApi: null\n Process { command: ["true"] }','second-physical-view-owner'),
            ('nvibrant/Main.qml','Quickshell.execDetached(buildCmd(admittedVibranceValue, admittedDisplayIndex));','Quickshell.execDetached(buildCmd(admittedVibranceValue, admittedDisplayIndex)); Quickshell.execDetached(["true"]);','unreviewed-detached-effect'),
        ]
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
