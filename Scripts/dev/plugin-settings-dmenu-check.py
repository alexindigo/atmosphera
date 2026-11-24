#!/usr/bin/env python3
"""Finite parsed Dmenu fields, IPC admission and session-lifetime contract."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('dmenu_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
FIELDS = 'customInputPrefix maxResults panelPosition resultFile showFooter showMatchCount showToastOnSelect'.split()
ANCHORS = {
    'Main.qml': ['readonly property bool ownerCurrent: pluginApi?.settingsContext?.current() ?? false', 'onOwnerCurrentChanged: if (!ownerCurrent) endSession(false)', 'onPluginApiChanged: endSession(false)', 'request.generation === requestGeneration', 'request.api === pluginApi && ownerCurrent', 'if (!requestCurrent(request) || !state.active) return', 'if (root.requestCurrent(request) && state.active)', 'launcherOpenTimer.request = request', 'launcherOpenTimer.stop()', 'requestGeneration++', 'currentRequest = null', 'generation === root.requestGeneration', 'var defaults = pluginApi.pluginSettings', 'var request = { api: pluginApi, generation: requestGeneration, defaults: captured }', 'var defaults = request.defaults', 'state.showToastOnSelect = config.showToastOnSelect ?? false', 'state.customInputPrefix = config.customInputPrefix ?? ""', 'var showToast = state.showToastOnSelect', 'handleSelection(state.customInputPrefix + text, -1, "")', 'endSession(shouldClose)', 'required property var request', 'required property var options', 'onLoaded: Qt.callLater(root.finishFileRequest, fileLoader)', 'Qt.callLater(root.failFileRequest, request)', 'if (requestCurrent(request)) endSession()', 'if (!loader || pendingFileLoader !== loader || !requestCurrent(loader.request)) return', 'var opts = Object.assign({}, loader.options)', 'if (key !== "items" && opts[key] === undefined)', 'root.buildConfig(opts, request)', 'root.beginSession(merged, request)', 'root.openPanelSmart(request)'],
    'Panel.qml': ['pluginApi?.pluginSettings?.panelPosition', 'pluginApi?.pluginSettings?.showMatchCount', 'pluginApi?.pluginSettings?.showFooter', 'var max = st.maxResults || 200', 'main.handleCustomInput(item.value)', 'main.handleSelection(item.value, item.originalIndex, "")', 'function onSessionEnded(sid) { root.updateFilter() }'],
    'Settings.qml': ['root.panelPositionField.set(key)', 'root.showMatchCountField.set(v)', 'root.showFooterField.set(v)', 'root.showToastOnSelectField.set(v)', 'root.resultFileField.set(text)', 'root.maxResultsField.set(value)']
}


def check(sources, manifest):
    code = {name: syntax.compact(text)[0] for name, text in sources.items()}
    if set(manifest['metadata']['settingsSchema']['fields']) != set(FIELDS): raise ValueError('unreviewed Dmenu field')
    if set(manifest['entryPoints']) != {'main', 'panel', 'settings'}: raise ValueError('no-instance Dmenu gained an entry')
    for name, anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(code[name], anchor, name + ': Dmenu ownership: ' + anchor)
    syntax.require(code['Main.qml'], 'root.ownerCurrent && capturedApi === root.pluginApi && generation === root.requestGeneration', 'late close keeps its admission generation')
    syntax.require(code['Main.qml'], 'root.ownerCurrent && capturedApi === pluginApi && generation === root.requestGeneration', 'toggle keeps its admission generation')
    for key in ('resultFile', 'maxResults', 'showToastOnSelect', 'customInputPrefix'):
        syntax.require(code['Main.qml'], 'defaults.' + key, 'captured admission leaf ' + key)
    if code['Main.qml'].count('root.beginRequest()') != 3: raise ValueError('every IPC starter must capture admission')
    if 'pluginApi.closePanel(' in code['Panel.qml']: raise ValueError('Panel acquired session-close policy')
    if '.saveSettings(' in code['Main.qml'] or re.search(r'pluginSettings\s*\.[\w]+\s*=', code['Main.qml']): raise ValueError('Dmenu session acquired preference writer')
    if any(manifest['metadata']['settingsSchema']['fields'][key]['editorUsage'] != 'configuration' for key in FIELDS): raise ValueError('Dmenu field classification changed')
    return dict(plugin='dmenu', fields=FIELDS, entries=manifest['entryPoints'], runtimeOrigin='plugin-level IPC', owner='Main', noPlacedRuntimeProof=True)


def replace_code(text, old, new):
    pattern = r'\s*'.join(re.escape(token) for token in re.findall(r'[A-Za-z_$][\w$]*|\d+|[^\s]', old))
    changed, count = re.subn(pattern, lambda _: new, text)
    if count != 1: raise RuntimeError('stale Dmenu mutation: ' + old)
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'report'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true'); args = parser.parse_args()
    root = args.plugins / 'dmenu'; sources = {p.name: p.read_text() for p in root.glob('*.qml')}
    manifest = json.loads((root / 'manifest.json').read_text()); row = check(sources, manifest); controls = []
    if args.selftest:
        changes = [('Main.qml', 'var defaults = request.defaults;', 'var defaults = pluginApi.pluginSettings;', 'late-defaults'), ('Main.qml', 'var showToast = state.showToastOnSelect;', 'var showToast = pluginApi.pluginSettings.showToastOnSelect;', 'late-toast'), ('Main.qml', 'handleSelection(state.customInputPrefix + text', 'handleSelection(pluginApi.pluginSettings.customInputPrefix + text', 'late-prefix'), ('Main.qml', 'request.generation === requestGeneration', 'true', 'request-generation'), ('Main.qml', 'generation === root.requestGeneration', 'true', 'late-close'), ('Main.qml', 'launcherOpenTimer.stop();', 'launcherOpenTimer.interval = 1;', 'chain-retirement'), ('Main.qml', 'pendingFileLoader !== loader', 'false', 'file-identity'), ('Main.qml', 'opts[key] === undefined', 'true', 'file-options-authority'), ('Main.qml', 'onOwnerCurrentChanged: if (!ownerCurrent) endSession(false)', 'onOwnerCurrentChanged: {}', 'API-retirement'), ('Panel.qml', 'function onSessionEnded(sid) { root.updateFilter(); }', 'function onSessionEnded(sid) { pluginApi.closePanel(pluginApi.panelOpenScreen); }', 'presentation-closes')]
        changes.append(('Main.qml', 'root.ownerCurrent && capturedApi === pluginApi && generation === root.requestGeneration', 'root.ownerCurrent && capturedApi === pluginApi', 'late-toggle'))
        for path, old, new, label in changes:
            if label == 'late-close':
                old = 'root.ownerCurrent && capturedApi === root.pluginApi && generation === root.requestGeneration'
                new = 'root.ownerCurrent && capturedApi === root.pluginApi'
            changed = dict(sources); changed[path] = replace_code(sources[path], old, new)
            try: check(changed, manifest)
            except ValueError as error: controls.append(dict(control=label, rejectedAt=str(error)))
            else: raise RuntimeError('Dmenu control escaped: ' + label)
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-Dmenu-contract', member=row, controls=controls, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_DMENU_CHECK: PASS (7 fields, %d controls)' % len(controls))


if __name__ == '__main__': main()
