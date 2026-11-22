#!/usr/bin/env python3
"""Finite parsed Hermes session/field/terminal/writer/lifetime contract."""
import argparse
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('hermes_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
FIELDS = 'autoConnectOnStartup host panelHeight panelWidth port rememberLastTarget showBarText terminalCols terminalFontSize terminalRows toggleShortcutName user'.split()
ANCHORS = {
    'Main.qml': ['property var _settingsConsumers: new Map()', 'if (!context || !context.current()) return null', 'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)', 'settingsContext: context', 'root._settingsConsumers.delete(context)', 'retired.destroy()', '_settingsConsumers.set(context, client)', 'name: root.shortcutName', 'root.pluginApi.togglePanel(screen)', 'root.pluginApi.openPanel(screen)', 'root.pluginApi.closePanel()'],
    'HermesSession.qml': ['required property var settingsContext', 'settingsContext.current()', 'settingsContext.settingsView', 'api.settingsContext === settingsContext', 'if (!accepts(api)) return false', 'if (_autoConnectAttempted || !setting("autoConnectOnStartup", false)) return', 'var generation = _sourceGeneration', 'var lifetime = _lifetime', 'lifetime.alive && root.accepts(api) && generation === root._sourceGeneration && !root.sessionActive && !root._connection', 'root.connect(api, request.host, request.port, request.user, "", request.rows, request.cols)', '++_sourceGeneration', 'onAutoSourceChanged: ++_sourceGeneration', 'if (setting("rememberLastTarget", true))', 'api.pluginSettings.host = host', 'api.pluginSettings.port = port', 'api.pluginSettings.user = user', 'api.saveSettings()', '_connection = null', 'previous.stop()', 'previous.destroy()', 'current && _connection === connection', 'function handleMessage(connection, line) { if (!acceptsConnection(connection)) return', 'function exited(connection) { if (!acceptsConnection(connection)) return', 'function started(connection) { if (!acceptsConnection(connection)) return', 'terminalBuffer += text', 'terminalOutput(text)', 'disconnect(); retire(root)', '_lifetime.alive = false; stopConnection()'],
    'HermesConnection.qml': ['required property var session', 'required property string request', 'function stop() { bridge.running = false', 'root.session.handleMessage(root, data)', 'root.session.bridgeError(root, String(data || ""))', 'onStarted: root.session.started(root)', 'onExited: root.session.exited(root)', 'Component.onDestruction: stop()'],
    'BarWidget.qml': ['pluginApi?.settingsContext?.current() ? mainInstance?.settingsConsumerFor(pluginApi.settingsContext) : null', 'settingsConsumer?.activate(pluginApi)', 'settingsConsumer?.setting("showBarText", true)', 'visible: root.showBarText && !root.isVertical', 'root.settingsConsumer?.sessionActive', 'root.settingsConsumer?.statusText', 'pluginApi?.togglePanel(screen, root)'],
    'Panel.qml': ['pluginApi?.settingsContext?.current() ? mainInstance?.settingsConsumerFor(pluginApi.settingsContext) : null', 'settingsConsumer?.activate(pluginApi)', 'root.settingsConsumer?.connect(root.pluginApi, root.valueHost, root.valuePort, root.valueUser, root.valuePassword, root.terminalRows, root.terminalCols)', 'root.valuePassword = ""', 'root.settingsConsumer?.disconnect()', 'session: root.settingsConsumer', 'rawText: root.settingsConsumer?.terminalBuffer ?? ""', 'root.settingsConsumer?.send(text)', 'cfg.panelWidth', 'cfg.panelHeight', 'cfg.terminalRows', 'cfg.terminalCols', 'cfg.terminalFontSize'],
    'TerminalView.qml': ['property var session: null', 'target: root.session', '_processInput(rawText)', 'onSessionChanged: Qt.callLater(replayBuffer)', 'function onTerminalOutput(text)', 'function onTerminalReset()', 'terminalDisplay.text = lines.join("<br>")'],
    'Settings.qml': ['visible: root.pluginApi?.scopeKind === "instance"', 'text: root.pluginApi?.tr("settings.shared-effect") ?? ""', 'field: root.toggleShortcutNameField visible: root.pluginApi?.scopeKind !== "instance"']
}


def check(sources, manifest, dictionaries, qmldir):
    code = {name: syntax.compact(text)[0] for name, text in sources.items()}
    fields = manifest['metadata']['settingsSchema']['fields']
    if set(fields) != set(FIELDS) or any(row['editorUsage'] != 'configuration' for row in fields.values()): raise ValueError('unreviewed Hermes fields/classification')
    if manifest['entryPoints'] != dict(main='Main.qml', barWidget='BarWidget.qml', panel='Panel.qml', settings='Settings.qml'): raise ValueError('unreviewed Hermes entries')
    if qmldir.strip() != 'HermesSession 1.0 HermesSession.qml': raise ValueError('mutable module singleton')
    for name, anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(code[name], anchor, name + ': Hermes ownership: ' + anchor)
    for name in ('BarWidget.qml', 'Panel.qml', 'TerminalView.qml'):
        if 'Local.HermesSession' in code[name] or 'setPluginApi(' in code[name]: raise ValueError('last-renderer session identity')
    if 'maybeAutoConnect(' in code['Main.qml'] or 'activate(' in code['Main.qml']: raise ValueError('Main-only automatic connection')
    for key in FIELDS: syntax.require(code['Settings.qml'], 'pluginApi?.field("' + key + '")', 'missing Hermes field intent: ' + key)
    for key in ('host', 'port', 'user', 'terminalRows', 'terminalCols', 'autoConnectOnStartup', 'rememberLastTarget'):
        syntax.require(code['HermesSession.qml'], 'setting("' + key + '"', 'missing selected SSH input: ' + key)
    for locale, data in dictionaries.items():
        if not data.get('settings', {}).get('shared-effect', '').strip(): raise ValueError('missing shared shortcut explanation: ' + locale)
    return dict(fields=FIELDS, entries=manifest['entryPoints'], sessionOwner='Main/context', writer='originating runtime API', shortcutAndIpc='plugin-level', storedLeavesUnchanged=True, runtimeAcceptance=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'report'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true'); args = parser.parse_args()
    root = args.plugins / 'hermes-ssh-chat'; sources = {p.name: p.read_text() for p in root.glob('*.qml')}
    manifest = json.loads((root / 'manifest.json').read_text()); dictionaries = {p.stem: json.loads(p.read_text()) for p in (root / 'i18n').glob('*.json')}; qmldir = (root / 'qmldir').read_text()
    member = check(sources, manifest, dictionaries, qmldir); controls = []
    if args.selftest:
        changes = [('HermesSession.qml', 'setting("' + key + '"', 'other("' + key + '"', 'shared-' + key) for key in ('host', 'port', 'user', 'terminalRows', 'terminalCols', 'autoConnectOnStartup', 'rememberLastTarget')]
        changes += [('Main.qml', 'root._settingsConsumers.delete(context)', 'context', 'retirement'), ('HermesSession.qml', 'api.pluginSettings.host = host', 'api.base.pluginSettings.host = host', 'shared-writer'), ('HermesSession.qml', 'generation === root._sourceGeneration', 'true', 'queued-source'), ('HermesSession.qml', 'api.settingsContext === settingsContext', 'true', 'foreign-writer'), ('HermesSession.qml', '_lifetime.alive = false; stopConnection()', '_lifetime.alive = false', 'destruction'), ('HermesConnection.qml', 'bridge.running = false', 'bridge.running = true', 'bridge-stop'), ('TerminalView.qml', 'target: root.session', 'target: null', 'terminal-signal'), ('Panel.qml', 'session: root.settingsConsumer', 'session: null', 'terminal-input'), ('BarWidget.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(mainInstance.pluginApi.settingsContext)', 'shared-bar'), ('Settings.qml', 'visible: root.pluginApi?.scopeKind !== "instance"', 'visible: true', 'dead-instance-shortcut')]
        changes += [('TerminalView.qml', 'onSessionChanged: Qt.callLater(replayBuffer)', 'onSessionChanged: {}', 'stream-source-replay')]
        for path, old, new, label in changes:
            if old not in sources[path]: raise RuntimeError('stale Hermes control: ' + label)
            changed = dict(sources); changed[path] = sources[path].replace(old, new)
            try: check(changed, manifest, dictionaries, qmldir)
            except ValueError as error: controls.append(dict(control=label, rejectedAt=str(error)))
            else: raise RuntimeError('Hermes control escaped: ' + label)
    args.report.write_text(json.dumps(dict(status='PASS', member=member, controls=controls, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_HERMES_CHECK: PASS (12 leaves, %d controls)' % len(controls))


if __name__ == '__main__': main()
