#!/usr/bin/env python3
"""Compile authored/compat credentials and observe actual native profile exclusion.

Run only in the assigned VM with disk TMPDIR and synthetic credential values.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FIELDS = {'github-contributions': 'token', 'github-feed': 'token',
          'habitica': 'habiticaApiToken', 'kagi-quick-search': 'kagiSessionToken',
          'sticky-notes': 'githubToken'}

FIXTURE = '''import QtQuick
import Quickshell
import ConfigQml 1.0
Scope {
  id: root
  property bool started: false
  function begin() {
    if (started || !store.ready) return;
    started = true;
    if (store.values.settings[Quickshell.env("CREDENTIAL_FIELD")] !== Quickshell.env("CREDENTIAL_CANARY")) {
      console.error("CREDENTIAL_ASSERT: canary not loaded"); Qt.exit(2); return;
    }
    store.exportProfile("Credential witness", Quickshell.env("CREDENTIAL_PROFILE"), [], function (result) {
      if (result.status !== "exported") { console.error("CREDENTIAL_ASSERT: " + JSON.stringify(result)); Qt.exit(2); return; }
      console.log("CREDENTIAL_PROFILE: EXPORTED"); Qt.exit(0);
    });
  }
  ConfigStore {
    id: store
    schema: PluginSchema {}
    autoSave: false
    sources: [JsonFileSource { sourceId: "user"; layerId: "user"; prefix: ["settings"]
      path: Quickshell.env("CREDENTIAL_INPUT"); writable: true; optional: true }]
    onReadyChanged: if (ready) Qt.callLater(root.begin)
  }
  Component.onCompleted: Qt.callLater(begin)
  Timer { interval: 10000; running: true; onTriggered: { console.error("CREDENTIAL_ASSERT: watchdog"); Qt.exit(2); } }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugins', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.plugins = args.plugins.resolve()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location('credential_compiler', ROOT / 'Scripts/dev/build-plugin-settings-schema.py')
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    overlays = json.loads((ROOT / 'Configs/plugin-settings-overlays.json').read_text())
    results = []
    for name, field in FIELDS.items():
        authored = json.loads((args.plugins / name / 'manifest.json').read_text())
        versions = overlays['plugins'][name]
        for origin, manifest in [('manifest', authored), *[('compatibility', dict(authored, version=version, metadata=dict(defaultSettings=authored['metadata']['defaultSettings']))) for version in versions]]:
            work = args.output / (name + '-' + origin)
            work.mkdir()
            defaults, fields, selected = compiler.described(manifest, overlays)
            assert selected == origin
            qml, selected = compiler.compile_schema(manifest, overlays)
            (work / 'PluginSchema.qml').write_text(qml)
            (work / 'probe.qml').write_text(FIXTURE)
            portable = next(key for key in defaults if key != field and fields[key]['type'] in ('String', 'Boolean', 'Integer', 'Real') and not fields[key].get('sensitive') and not fields[key].get('machineLocal'))
            canary = 'synthetic-private-' + name
            raw = {field: canary, portable: defaults[portable]}
            input_file = work / 'input.json'
            input_file.write_text(json.dumps(raw))
            before = input_file.read_bytes()
            runtime = work / 'runtime'
            runtime.mkdir(mode=0o700)
            profile = work / 'profile.json'
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', XDG_RUNTIME_DIR=str(runtime),
                       TMPDIR=str(work), CREDENTIAL_INPUT=str(input_file), CREDENTIAL_PROFILE=str(profile),
                       CREDENTIAL_FIELD=field, CREDENTIAL_CANARY=canary)
            run = subprocess.run(['timeout', '15', 'qs', '-p', str(work / 'probe.qml'), '--no-color'], env=env,
                                 cwd=work, capture_output=True, text=True, timeout=20)
            text = run.stdout + run.stderr
            (work / 'run.log').write_text(text)
            assert run.returncode == 0 and 'CREDENTIAL_PROFILE: EXPORTED' in text, text
            exported = json.loads(profile.read_text())
            assert canary not in profile.read_text(), (name, origin, 'credential leaked into profile')
            assert not any(entry['path'] == ['settings', field] for entry in exported['entries'])
            assert any(entry['path'] == ['settings', portable] and entry['value'] == defaults[portable] for entry in exported['entries'])
            assert input_file.read_bytes() == before, 'export modified raw user input'
            assert all(fields[field].get(flag) is True for flag in ('sensitive', 'machineLocal'))
            block = qml.split('key: ' + json.dumps(field), 1)[1].split('\n    }', 1)[0]
            assert 'sensitive: true' in block and 'machineLocal: true' in block
            results.append(dict(plugin=name, origin=origin, portable=portable, credentialExcluded=True))
        assert all(versions[version]['fields'][field] == authored['metadata']['settingsSchema']['fields'][field] for version in versions)
    (args.output / 'result.json').write_text(json.dumps(dict(status='PASS', cases=results), indent=2) + '\n')
    print('CREDENTIAL_FLAGS: PASS ' + str(len(results)) + ' authored/compatibility native profile exports')


if __name__ == '__main__':
    main()
