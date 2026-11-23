#!/usr/bin/env python3
"""Parsed completion-entry inventory plus finite shared host admission contract."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('completion_boundary', Path(__file__).with_name('plugin-settings-boundary-check.py'))
boundary = importlib.util.module_from_spec(spec)
import sys
sys.modules[spec.name] = boundary
spec.loader.exec_module(boundary)
spec = importlib.util.spec_from_file_location('completion_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec)
spec.loader.exec_module(syntax)

def require(code, anchor, message):
    # Same literal-preserving matcher as the originating track's action checker;
    # this isolated import does not depend on unrelated G2 implementation files.
    parts = re.findall(r'"(?:[^"\\]|\\.)*"|\x27(?:[^\x27\\]|\\.)*\x27|[^\s;]', anchor)
    if ''.join(parts) not in code:
        raise ValueError(message)

ANCHORS = {
    'PluginSettingsSession.qml': [
        'root._observe(result, reset)',
        '["saved", "nothing_to_save"].indexOf(write.status) === -1 || write.refreshState !== "current"',
        '_preview.acknowledge(_previewFence)',
        'if (!_preview.pending() && _preview.close()) _preview = null',
        'reader: _runtimeReadOwner',
        'if (_preview && _preview.pending())',
        'pending.reader.readProjection.synchronize(receipt.write.observation, function (read)',
        'if (!lifetime.alive || root._observation !== pending) return',
        'root._runtimeReadOwner !== pending.reader || read.status !== "observed"',
        'root._finish(receipt.write, receipt.reset, read, checking)',
        'pageApi.retryObservation()',
        '_synchronizeObservation(retained, true)',
        'if (checking && !_sameDraft(receipt))',
        'error: {code: code, phase: "observation"}, write: pending.receipt.write',
        'function applySettings() { if (!editor || editor.writable === false || !page || busy) return false; _beginSubmission(); commitInputs()',
        'checking && (inputDirty || page?.settingsDirty !== false) ? {status: "observed", refreshState: "current", write: result, runtimeRead: read}',
        'settingsCompleted(result); pageApi.complete(result); pageApi.busy = false; busy = false',
        '_observationFailed(_observation, "settings-runtime-owner")',
    ],
    'PluginSettingsPageApi.qml': [
        'if (result?.error?.phase === "observation") _observationCallbacks = callbacks',
        '_callbacks = _observationCallbacks.concat(_callbacks)',
        'settingsCompleted(result); for (var callback of callbacks)',
    ],
    'PluginSettingsPreview.qml': [
        'readonly property var readOwner: _token && _editor && !_editor.closed && currentOwner() === _owner ? _baseScope : sourceReadOwner',
        'root._revisions[key] !== captured.revisions[key]',
        'if (owned && root._editor && !root._editor.closed && !editor.discard()) return false',
    ],
    'PluginInstanceApi.qml': [
        'readonly property var settingsReadOwner: settingsPreviewOwner.readOwner',
        'sourceReadOwner: root._inheritedPreview && root._inheritedPreview.ready ? root._inheritedPreview : root.runtime',
    ],
    'Service.qml': ['sourceReadOwner: Qt.binding(function () { return api.settingsHandle; })'],
}


def host(sources):
    for name, anchors in ANCHORS.items():
        code = syntax.compact(sources[name])[0]
        for anchor in anchors:
            require(code, anchor, name + ': ' + anchor)


def inventory(plugins):
    rows = []
    entries = []
    for path in sorted(plugins.glob('*/manifest.json')):
        manifest = json.loads(path.read_text())
        entry = manifest.get('entryPoints', {}).get('settings')
        if not entry:
            continue
        pages = boundary.Pages(path.parent, {})
        pages.load(path.parent / entry.split('?', 1)[0])
        pages.solve()
        entries.append(dict(plugin=path.parent.name, version=manifest['version'], entry=entry))
        for file, unit in pages.units.items():
            for node in boundary.walk(unit.tree.root_node):
                kind = None
                if node.type == 'function_declaration' and unit.text(boundary.child(node, 'name')) == 'onSettingsCompleted':
                    kind = 'settingsCompleted-signal'
                elif node.type == 'call_expression':
                    function = boundary.child(node, 'function')
                    if function and function.type in ('member_expression', 'subscript_expression'):
                        members = pages.property(function)
                        api = ('api',) in pages.value(boundary.child(function, 'object'))
                        if api and members & {'complete', 'settingsCompleted'}:
                            raise ValueError(str(file) + ': page-side completion publisher')
                        arguments = boundary.child(node, 'arguments')
                        if api and 'saveSettings' in members and arguments and arguments.named_children:
                            kind = 'saveSettings-callback'
                if kind:
                    rows.append(dict(plugin=path.parent.name, file=str(file.relative_to(plugins)), line=node.start_point.row + 1 - unit.offset, kind=kind))
    return dict(version=1, contract='Every generic page completion signal and callback is delivered by PluginSettingsSession after selected native runtime observation; this inventories transport, not acceptance of each domain port.', entries=entries, observers=sorted(rows, key=lambda row: (row['file'], row['line'], row['kind'])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'plugins', 'report'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--inventory-output', type=Path)
    parser.add_argument('--selftest', action='store_true')
    args = parser.parse_args()
    sources = {name: (args.source / 'Services/Plugins' / name).read_text() for name in ANCHORS}
    host(sources)
    actual = inventory(args.plugins)
    controls = []
    if args.selftest:
        mutations = [
            ('PluginSettingsSession.qml', 'root._observe(result, reset)', 'root._finish(result, reset)', 'writer-only-completion'),
            ('PluginSettingsSession.qml', 'synchronize(receipt.write.observation,', 'synchronize(undefined,', 'tokenless-refresh'),
            ('PluginSettingsSession.qml', '!_preview.pending() && _preview.close()', '_preview.close()', 'discard-newer-preview'),
            ('PluginSettingsSession.qml', '_preview.acknowledge(_previewFence)', '_preview.acknowledge(null)', 'wrong-preview-fence'),
            ('PluginSettingsSession.qml', '!lifetime.alive || root._observation !== pending', 'root._observation !== pending', 'dead-session-callback'),
            ('PluginSettingsSession.qml', 'read.status !== "observed"', 'false', 'failed-read-success'),
            ('PluginSettingsSession.qml', '_synchronizeObservation(retained, true)', '_submit(false)', 'retry-writes-again'),
            ('PluginSettingsSession.qml', 'if (checking && !_sameDraft(receipt))', 'if (false)', 'retry-changed-draft'),
            ('PluginSettingsSession.qml', '_beginSubmission();\n    commitInputs();', '_beginSubmission();', 'apply-skips-current-input'),
            ('PluginSettingsSession.qml', 'checking && (inputDirty || page?.settingsDirty !== false)', 'false', 'retry-acknowledges-new-input'),
            ('PluginSettingsPageApi.qml', '_observationCallbacks = callbacks', '_observationCallbacks = []', 'retry-loses-observers'),
            ('PluginSettingsPreview.qml', '? _baseScope : sourceReadOwner', '? sourceReadOwner : sourceReadOwner', 'certify-wrong-reader'),
            ('PluginInstanceApi.qml', '? root._inheritedPreview : root.runtime', '? root.runtime : root.runtime', 'ignore-inherited-reader'),
        ]
        for name, old, new, label in mutations:
            assert sources[name].count(old) == 1, label
            changed = dict(sources)
            changed[name] = sources[name].replace(old, new, 1)
            try:
                host(changed)
            except (ValueError, RuntimeError):
                controls.append(dict(file=name, control=label, rejected=True))
            else:
                raise ValueError('completion control escaped: ' + label)
    if args.inventory_output:
        args.inventory_output.write_text('{"version": 1, "contract": ' + json.dumps(actual['contract']) + ',\n"entries": [\n' + ',\n'.join(json.dumps(row, sort_keys=True) for row in actual['entries']) + '\n],\n"observers": [\n' + ',\n'.join(json.dumps(row, sort_keys=True) for row in actual['observers']) + '\n]}\n')
    inputs = {str(path.relative_to(args.source)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__), *(args.source / 'Services/Plugins' / name for name in ANCHORS)]}
    args.report.write_text(json.dumps(dict(status='PASS', catalogEntries=len(actual['entries']), completionObservers=len(actual['observers']), controls=controls, inventory=actual, inputs=inputs, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_COMPLETION_CHECK: PASS (%d entries, %d observers, %d controls)' % (len(actual['entries']), len(actual['observers']), len(controls)))


if __name__ == '__main__':
    main()
