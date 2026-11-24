#!/usr/bin/env python3
"""Finite parsed shared notes/Gist ownership and operation contract."""
import argparse
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('sticky_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
ANCHORS = {
    'Settings.qml': [
        'readonly property bool sharedScope: pluginApi?.scopeKind === "plugin"',
        'visible: !root.sharedScope', 'root.pluginApi?.tr("settings.sharedEffect")',
        'field: root.syncEnabledField enabled: root.sharedScope',
        'field: root.githubTokenField enabled: root.sharedScope',
        'if (root.sharedScope) root.syncEnabledField.set(checked)',
        'if (root.sharedScope) root.githubTokenField.set(text.trim())',
        'root.mainInstance?.manualSync()', 'result.refreshState !== "current"',
    ],
    'Main.qml': [
        'var stored = pluginApi.pluginSettings.notes',
        'pluginApi.pluginSettings.notes = JSON.stringify(notes)',
        'syncNotesToGist(notes, true)', 'syncNotesToGist(loadStoredNotes(), false)',
        'var syncEnabled = pluginApi.pluginSettings.syncEnabled === true',
        'if (syncInProgress)', 'if (!syncEnabled && silent !== false)',
        'const context = pluginApi.settingsContext', 'const alive = lifetime',
        'alive.alive && !operation.cancelled && context.current()',
        'String(api.pluginSettings.githubToken ?? "").trim() === operation.token',
        'String(api.pluginSettings.githubGistId ?? "").trim() === operation.gistId',
        'if (!operation.current() || !gistId) return false',
        'operation.gistId = gistId', 'api.pluginSettings.githubGistId = gistId',
        'api.saveSettings()', 'GistSync.syncNotes(operation, JSON.parse(JSON.stringify(syncNotes))',
        'if (!operation.current() || root.syncOperation !== operation) return',
        'operation.cancelled = true', 'for (const request of requests) request.abort()',
        'lifetime.alive = false', 'root.retireSync()',
    ],
    'Panel.qml': ['root.pluginApi.mainInstance.getDisplayNotes()', 'root.pluginApi.mainInstance.saveNote(noteId, content, saveColor)', 'root.pluginApi.mainInstance.deleteNote(noteId)'],
    'BarWidget.qml': ['pluginApi.togglePanel(root.screen, this)', 'BarService.openPluginSettings(root.screen, pluginApi.manifest)'],
    'ExpandedPanelWindow.qml': ['root.saveRequested(noteId, content, noteColor)', 'screen: null'],
    'utils/gistSync.js': [
        'if (!operation.current()) return', 'var token = operation.token', 'var gistId = operation.gistId',
        'getGistById(operation, token, gistId', 'findManagedGist(operation, token',
        'upsertGist(operation, token, gist', 'createOrFindGist(operation, token',
        'requestJson(operation, "POST"', 'requestJson(operation, "PATCH"', 'requestJson(operation, "GET"',
        'operation.requests.push(xhr)', 'operation.requests = operation.requests.filter',
        'operation.publishGistId(response.id)', 'operation.publishGistId(response.id || gist.id)',
    ],
}


def code_for(name, source):
    if name.endswith('.js'):
        # Same JS-in-QML parser envelope as the shared boundary checker.
        source = re.sub(r'^\s*\.(?:pragma|import)\b[^\n]*', lambda match: ' ' * len(match[0]), source, flags=re.M)
        source = 'import QtQml\nQtObject { function __script() {\n' + source + '\n} }\n'
    return syntax.compact(source)[0]


def check(sources, manifest, dictionaries):
    fields = manifest['metadata']['settingsSchema']['fields']
    assert set(fields) == {'githubToken', 'syncEnabled', 'notes', 'githubGistId'}
    assert fields['notes']['editorUsage'] == 'content' and fields['githubGistId']['editorUsage'] == 'operational'
    assert all(fields[key]['editorUsage'] == 'configuration' for key in ('githubToken', 'syncEnabled'))
    assert manifest['entryPoints'] == dict(main='Main.qml', barWidget='BarWidget.qml', panel='Panel.qml', settings='Settings.qml')
    for name, anchors in ANCHORS.items():
        code = code_for(name, sources[name])
        for anchor in anchors:
            syntax.require(code, anchor, name+': '+anchor)
        if name not in ('Main.qml',):
            assert not re.search(r'pluginSettings\.(notes|githubGistId)\s*=', code), name+': shared native writer escaped Main'
    for key in ('githubToken', 'syncEnabled'):
        syntax.require(syntax.compact(sources['Settings.qml'])[0], 'pluginApi?.field("'+key+'")', key+': configuration handle')
    utility = code_for('utils/gistSync.js', sources['utils/gistSync.js'])
    assert 'pluginSettings' not in utility, 'utility does not retain a live native writer'
    assert utility.count(syntax.squash('if (!operation.current()) return')) == 3, 'admission, request and response retirement'
    for words in dictionaries.values():
        assert words['settings']['sharedEffect'] and words['sync']['errors']['configuration-changed']
    return dict(configuration=['githubToken', 'syncEnabled'], protected=['notes', 'githubGistId'], sharedNativeWriter='Main.qml')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugins', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--selftest', action='store_true')
    args = parser.parse_args(); root = args.plugins/'sticky-notes'
    sources = {name: (root/name).read_text() for name in ANCHORS}
    manifest = json.loads((root/'manifest.json').read_text())
    dictionaries = {p.stem: json.loads(p.read_text()) for p in (root/'i18n').glob('*.json')}
    member = check(sources, manifest, dictionaries); controls = []
    if args.selftest:
        mutations = [
            ('Settings.qml', 'scopeKind === "plugin"', 'scopeKind === "instance"', 'scope'),
            ('Settings.qml', 'enabled: root.sharedScope', 'enabled: true', 'ineffective-control'),
            ('Settings.qml', 'if (root.sharedScope) root.githubTokenField', 'if (true) root.githubTokenField', 'token-intent'),
            ('Main.qml', 'context.current()', 'true', 'owner-loss'),
            ('Main.qml', '=== operation.token', '=== "foreign"', 'credential-replacement'),
            ('Main.qml', '=== operation.gistId', '=== "foreign"', 'target-replacement'),
            ('Main.qml', 'request.abort()', 'request.open("GET", "invalid")', 'abort-retirement'),
            ('Main.qml', 'JSON.parse(JSON.stringify(syncNotes))', 'syncNotes', 'admitted-notes'),
            ('utils/gistSync.js', 'if (!operation.current()) return;', 'if (false) return;', 'request-retirement'),
            ('utils/gistSync.js', 'operation.publishGistId(response.id)', 'true', 'native-id-owner'),
        ]
        for name, old, new, label in mutations:
            candidate = deepcopy(sources)
            tokens = re.findall(r'"(?:[^"\\]|\\.)*"|\x27(?:[^\x27\\]|\\.)*\x27|[^\s]', old)
            pattern = r'\s*'.join(re.escape(token) for token in tokens)
            candidate[name], count = re.subn(pattern, lambda _: new, candidate[name], count=1)
            assert count == 1, label
            try:
                check(candidate, manifest, dictionaries)
            except (ValueError, AssertionError):
                controls.append(label)
            else:
                raise AssertionError('sticky control escaped '+label)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(dict(status='PASS', member=member, controls=controls, generalJavaScriptProof=False), indent=2)+'\n')
    print('STICKY_GROUP: PASS '+str(len(controls))+' controls')


if __name__ == '__main__':
    main()
