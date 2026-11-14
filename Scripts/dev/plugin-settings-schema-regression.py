#!/usr/bin/env python3
"""Inert first catalog slice: actual ConfigQml file/save/restart consumers.

Run inside the assigned VM, with disk TMPDIR. Production plugin owners stay old.
This proves hello-world's reviewed descriptor and exact older-version overlay,
not coverage of the rest of the catalog or production owner integration.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('plugin_schema', ROOT/'Scripts/dev/build-plugin-settings-schema.py')
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)

FIXTURE = '''import QtQuick
import Quickshell
import ConfigQml 1.0
Scope {
  id: root
  property bool started: false
  readonly property string mode: Quickshell.env("SCHEMA_MODE")
  readonly property string expectedMessage: Quickshell.env("SCHEMA_MESSAGE")
  readonly property string expectedColor: Quickshell.env("SCHEMA_COLOR")
  readonly property string messageConsumer: store.ready ? store.values.settings.message : ""
  readonly property string colorConsumer: store.ready ? store.values.settings.iconColor : ""
  function check(ok, name) {
    if (!ok) throw new Error("PLUGIN_SCHEMA_ASSERT: " + name);
  }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function begin() {
    if (started || !store.ready) return;
    started = true;
    try {
      check(root.messageConsumer === expectedMessage && root.colorConsumer === expectedColor, "bound input consumer");
      if (mode === "load" || mode === "restart") {
        console.log("PLUGIN_SCHEMA: " + mode.toUpperCase() + "_PASS");
        Qt.exit(0);
        return;
      }
      check(mode === "save", "explicit mode");
      var rejected = false;
      try { store.values.settings.message = 17; } catch (error) { rejected = true; }
      check(rejected && root.messageConsumer === expectedMessage, "typed setter refuses invalid message");
      store.values.settings.message = "descriptor-saved";
      store.save(function(result) {
        Qt.callLater(function() {
          try {
            check(result.status === "saved", "actual saved receipt");
            check(root.messageConsumer === "descriptor-saved" && root.colorConsumer === "primary", "post-save bound consumer and whole-source fallback");
            console.log("PLUGIN_SCHEMA: SAVED_PASS");
            Qt.exit(0);
          } catch (error) { root.fail(error); }
        });
      });
    } catch (error) { fail(error); }
  }
  ConfigStore {
    id: store
    schema: PluginSchema {}
    autoSave: false
    sources: [
      JsonFileSource {
        sourceId: "legacy"; layerId: "legacy"; prefix: ["settings"]
        path: Quickshell.env("SCHEMA_LEGACY")
        writable: false; optional: true; fallbackFor: "user"
      },
      JsonFileSource {
        sourceId: "user"; layerId: "user"; prefix: ["settings"]
        path: Quickshell.env("SCHEMA_USER")
        writable: true; optional: true
      }
    ]
    onReadyChanged: if (ready) Qt.callLater(root.begin)
    onSourceError: function(error) { root.fail("source error " + error.code); }
  }
  Component.onCompleted: Qt.callLater(begin)
  Timer { interval:30000; running:true; onTriggered:root.fail("watchdog") }
}
'''


def selftest(manifest, old, overlays):
    first, origin = compiler.compile_schema(manifest, overlays)
    previous, old_origin = compiler.compile_schema(old, overlays)
    assert first == previous and origin == 'manifest' and old_origin == 'compatibility'
    controls = []
    def reject(name, value, catalog=overlays):
        try:
            compiler.compile_schema(value, catalog)
        except (ValueError, TypeError, KeyError):
            controls.append(name)
        else:
            raise AssertionError('accepted rejecting control: '+name)
    missing = copy.deepcopy(manifest); del missing['metadata']['settingsSchema']
    reject('no-default-inference', missing)
    unknown = copy.deepcopy(old); unknown['version'] = '99.0.0'
    reject('unknown-version', unknown)
    bad = copy.deepcopy(manifest); bad['metadata']['settingsSchema']['fields']['message']['type'] = 'Group'
    reject('shallow-settings-not-groups', bad)
    bad = copy.deepcopy(manifest); bad['metadata']['settingsSchema']['fields']['message']['type'] = 'Boolean'
    reject('default-type', bad)
    bad = copy.deepcopy(manifest); del bad['metadata']['settingsSchema']['fields']['message']
    reject('undeclared-default', bad)
    bad = copy.deepcopy(manifest); bad['metadata']['settingsSchema']['fields']['extra'] = {'type':'String'}
    reject('absent-required-choice', bad)
    bad = copy.deepcopy(manifest); bad['metadata']['settingsSchema']['fields']['extra'] = {'type':'List','optional':True}
    reject('untyped-empty-list', bad)
    bad = copy.deepcopy(old); bad['metadata']['settingsSchema'] = {'version':9,'fields':{}}
    reject('invalid-authored-no-fallback', bad)
    bad = copy.deepcopy(manifest); bad['metadata']['settingsSchema']['version'] = True
    reject('boolean-format-version', bad)
    optional = copy.deepcopy(manifest)
    optional['metadata']['settingsSchema']['fields']['extra'] = {'type':'String','optional':True}
    compiled, _ = compiler.compile_schema(optional, overlays)
    assert compiled.count('defaultValue:') == first.count('defaultValue:') == 2
    assert 'key: "extra"' in compiled and 'optional: true' in compiled
    return controls


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--old-manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--work-root', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    args.work_root.mkdir(parents=True, exist_ok=False)
    manifest = compiler.shared.load(args.manifest)
    old = compiler.shared.load(args.old_manifest)
    assert manifest['id'] == old['id'] == 'hello-world'
    # The authored descriptor remains identical across the later editor/API
    # preparation bumps; selftest below compares the actual compiled contracts.
    assert manifest['version'] != old['version'] and old['version'] == '1.2.5'
    overlays = compiler.shared.load(ROOT/'Configs/plugin-settings-overlays.json')
    controls = selftest(manifest, old, overlays)
    results = []
    for number, (name, selected) in enumerate([('manifest', manifest), ('compatibility', old)]):
        qml, origin = compiler.compile_schema(selected, overlays)
        for presence in ('absent', 'unknown-only'):
            work = args.work_root/(str(number)+'-'+presence); work.mkdir()
            (work/'PluginSchema.qml').write_text(qml)
            fixture = work/'fixture.qml'; fixture.write_text(FIXTURE)
            legacy = work/'legacy.json'
            legacy.write_text('{"message":"legacy-message","iconColor":"legacy-color","legacyOpaque":{"keep":true}}\n')
            before = (legacy.read_bytes(), legacy.stat().st_ino, legacy.stat().st_mtime_ns, legacy.stat().st_mode)
            user = work/'user.json'
            if presence == 'unknown-only':
                user.write_text('{"opaque":{"keep":[false,0,"雪"]}}\n')
            initial = user.read_bytes() if user.exists() else None
            for leg in ('load', 'save', 'restart'):
                runtime = work/('r-'+leg); runtime.mkdir(mode=0o700)
                message = 'descriptor-saved' if leg == 'restart' else 'legacy-message' if presence == 'absent' else 'Hello World'
                color = 'legacy-color' if presence == 'absent' and leg != 'restart' else 'primary'
                env = {**os.environ, 'XDG_RUNTIME_DIR':str(runtime), 'WAYLAND_DISPLAY':'/run/user/1000/wayland-1',
                    'QT_QPA_PLATFORM':'wayland','SCHEMA_MODE':leg,'SCHEMA_MESSAGE':message,'SCHEMA_COLOR':color,
                    'SCHEMA_LEGACY':str(legacy),'SCHEMA_USER':str(user)}
                label = name+'-'+presence+'-'+leg
                with (args.output/(label+'.log')).open('x') as log:
                    p = subprocess.run(['timeout','45','qs','-p',str(fixture),'--no-color'],cwd=work,env=env,
                        stdout=log,stderr=subprocess.STDOUT,timeout=55)
                text = (args.output/(label+'.log')).read_text()
                marker = 'SAVED' if leg == 'save' else leg.upper()
                assert p.returncode == 0 and 'PLUGIN_SCHEMA: '+marker+'_PASS' in text, (label, p.returncode, text)
                assert not any(token in text for token in ('PLUGIN_SCHEMA_ASSERT','ReferenceError','TypeError','Failed to load configuration'))
                assert before == (legacy.read_bytes(), legacy.stat().st_ino, legacy.stat().st_mtime_ns, legacy.stat().st_mode)
                if leg == 'load':
                    assert (user.read_bytes() if user.exists() else None) == initial
                else:
                    expected = {'message':'descriptor-saved'}
                    if presence == 'unknown-only':
                        expected['opaque'] = {'keep':[False,0,'雪']}
                    assert json.loads(user.read_text()) == expected
                results.append({'id':label,'status':'PASS','origin':origin})
    summary = {'status':'PASS','plugin':'hello-world','cases':results,'rejectingControls':controls,
        'manifestSha256':hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
        'oldManifestSha256':hashlib.sha256(args.old_manifest.read_bytes()).hexdigest(),
        'legacyUnchanged':True,'noStartupWrite':True,'unknownRawPreserved':True,'coldRestart':True}
    (args.output/'result.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('PLUGIN_SETTINGS_SCHEMA_REGRESSION: PASS (hello-world; 12 installed-module endpoints, 9 rejecting controls)')


if __name__ == '__main__':
    main()
