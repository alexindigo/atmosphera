#!/usr/bin/env python3
"""Inert catalog/compiler contract on the installed library, inside the test VM.

Observe real namespace bindings, Source projections and separate cold restarts.
This does not activate plugin runtime ports or replace the old production owner.
"""
import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('plugin_schema', ROOT/'Scripts/dev/build-plugin-settings-schema.py')
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)


def controls(overlays):
    manifest = {'id':'control', 'version':'1', 'metadata':{'defaultSettings':{'text':'a'},
        'settingsSchema':{'version':1, 'fields':{'text':{'type':'String'}}}}}
    rejected = []
    def refuses(name, callback):
        try:
            callback()
        except (ValueError, KeyError, TypeError):
            rejected.append(name)
        else:
            raise AssertionError('accepted rejecting control: '+name)
    projection = {'version':1, 'projectionId':'control-source', 'transform':'function(input) { return input; }'}
    candidate = copy.deepcopy(manifest); candidate['metadata']['settingsSourceProjection'] = projection
    for name, value in [('empty', []), ('duplicate', ['x','x']), ('nonstring', [1]), ('bare-string', 'x')]:
        refuses('source-ids-'+name, lambda value=value: compiler.compile_projection(candidate, overlays, value))
    for name, delta in [('boolean-version', {'version':True}), ('unknown-field', {'phase':'Effective'}),
                        ('closure-not-source', {'transform':{}}), ('empty-id', {'projectionId':''})]:
        bad = copy.deepcopy(candidate); bad['metadata']['settingsSourceProjection'].update(delta)
        refuses('projection-'+name, lambda bad=bad: compiler.compile_projection(bad, overlays, ['x']))
    refuses('ids-without-projection', lambda: compiler.compile_projection(manifest, overlays, ['x']))
    refuses('config-default-inference', lambda: compiler.compile_schema(manifest, overlays, 'config'))
    bad = copy.deepcopy(manifest); bad['metadata']['configSchema'] = {'version':1, 'fields':{'a':{'type':'Group', 'optional':True}}}
    refuses('group-leaf-constraint', lambda: compiler.compile_schema(bad, overlays, 'config', {}))
    bad['metadata']['configSchema']['fields']['a'] = {'type':'Group', 'fields':{'required':{'type':'String'}}}
    refuses('absent-required-config-leaf', lambda: compiler.compile_schema(bad, overlays, 'config', {}))
    bad['metadata']['configSchema']['fields']['a']['fields']['required']['optional'] = True
    refuses('undeclared-config-default', lambda: compiler.compile_schema(bad, overlays, 'config', {'a':{'extra':1}}))
    for name, versions in overlays['incompatible'].items():
        for version in versions:
            result = compiler.runtime_compatibility({'id':name, 'version':version}, overlays)
            assert result['compatible'] is False and result['reason']
    assert compiler.runtime_compatibility(manifest, overlays) == {'compatible':True, 'reason':None}
    # Bad authored metadata never falls back to an otherwise valid exact overlay.
    old = {'version':1, 'plugins':{'control':{'1':manifest['metadata']['settingsSchema']}}}
    bad = copy.deepcopy(manifest); bad['metadata']['settingsSchema'] = {'version':9, 'fields':{}}
    refuses('authored-no-fallback', lambda: compiler.compile_schema(bad, old))
    return rejected


FIXTURE = '''import QtQuick
import Quickshell
import ConfigQml 1.0
Scope {
  id: root
  property bool started: false
  readonly property string mode: Quickshell.env("CONTRACT_MODE")
  readonly property string subject: Quickshell.env("CONTRACT_SUBJECT")
  readonly property string expected: Quickshell.env("CONTRACT_EXPECTED")
  readonly property string consumer: {
    if (!store.ready) return "waiting";
    if (subject === "screen-toolkit") return JSON.stringify(Array.from(store.values.settings.paletteColors));
    if (subject === "video-wallpaper") {
      // Read the actual leaf even while absent; info() is a diagnostic query,
      // not a reactive dependency on a later optional-leaf assignment.
      var monitors = store.values.settings.monitors;
      return !monitors ? "absent" : Object.keys(monitors).length === 0 ? "empty" : String(monitors["offline.雪"].volume);
    }
    return store.values.config.network.address + ":" + store.values.config.network.port;
  }
  function check(ok, name) { if (!ok) throw new Error("PLUGIN_CONTRACT_ASSERT: " + name); }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function begin() {
    if (started || !store.ready) return;
    started = true;
    try {
      check(consumer === expected, "bound initial consumer: " + consumer);
      if (subject === "config") check(!store.info(["config","network","optionalLabel"]).present, "optional stays absent");
      if (mode !== "save") { console.log("PLUGIN_CONTRACT: " + mode.toUpperCase() + "_PASS"); Qt.exit(0); return; }
      if (subject === "screen-toolkit") store.values.settings.paletteColors = ["#123456"];
      else if (subject === "video-wallpaper") {
        var map = Object.create(null); map["offline.雪"] = {volume:0.75, opaque:false};
        store.values.settings.monitors = map;
      } else store.values.config.network.port = 17;
      store.save(function(result) {
        Qt.callLater(function() {
          try {
            check(result.status === "saved", "acknowledged save");
            check(consumer === Quickshell.env("CONTRACT_AFTER"), "post-save consumer");
            console.log("PLUGIN_CONTRACT: SAVED_PASS"); Qt.exit(0);
          } catch(error) { root.fail(error); }
        });
      });
    } catch(error) { fail(error); }
  }
  ConfigStore {
    id: store
    autoSave: false
    schema: PluginSchema {}
    PROJECTIONS
    sources: [
      JsonFileSource { sourceId:"legacy.雪"; layerId:"legacy"; prefix:PREFIX
        path:Quickshell.env("CONTRACT_LEGACY"); writable:false; optional:true; FALLBACK },
      JsonFileSource { sourceId:"user:opaque"; layerId:"user"; prefix:PREFIX
        path:Quickshell.env("CONTRACT_USER"); writable:true; optional:true }
    ]
    onReadyChanged: if (ready) Qt.callLater(root.begin)
    onSourceError: function(error) { root.fail("source error " + error.code); }
  }
  Component.onCompleted: Qt.callLater(begin)
  Timer { interval:30000; running:true; onTriggered:root.fail("watchdog") }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugins', type=Path, required=True)
    parser.add_argument('--frozen-plugins', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--work-root', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False); args.work_root.mkdir(parents=True, exist_ok=False)
    overlays = compiler.shared.load(ROOT/'Configs/plugin-settings-overlays.json')
    rejected = controls(overlays)
    results = []
    def run(label, directory, extra, marker):
        runtime = args.work_root/('r'+str(len(results))); runtime.mkdir(mode=0o700)
        env = {**os.environ, 'QT_QPA_PLATFORM':'offscreen', 'XDG_RUNTIME_DIR':str(runtime), **extra}
        with (args.output/(label+'.log')).open('x') as log:
            p = subprocess.run(['timeout','45s','qs','-p',str(directory/'fixture.qml'),'--no-color'],
                cwd=directory,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=55)
        text = (args.output/(label+'.log')).read_text()
        assert p.returncode == 0 and marker in text, (label, p.returncode, text)
        assert not any(t in text for t in ('PLUGIN_CONTRACT_ASSERT','ReferenceError','TypeError','Failed to load configuration'))
        results.append({'id':label,'status':'PASS'})
    catalog_count = 0
    for path in sorted(args.plugins.glob('*/manifest.json')):
        manifest = compiler.shared.load(path); name = manifest['id']
        qml, origin = compiler.compile_schema(manifest, overlays); assert origin == 'manifest'
        versions = [('manifest', qml, manifest)]
        old = compiler.shared.load(args.frozen_plugins/name/'manifest.json')
        if name in overlays['plugins']:
            previous, origin = compiler.compile_schema(old, overlays); assert origin == 'compatibility'
            versions.append(('overlay', previous, old))
        else:
            assert not compiler.runtime_compatibility(old, overlays)['compatible']
        for kind, schema, selected in versions:
            directory = args.work_root/(name+'-'+kind); directory.mkdir()
            (directory/'PluginSchema.qml').write_text(schema)
            defaults, fields, _ = compiler.described(selected, overlays)
            keys = [k for k, n in fields.items() if k in defaults and n['type'] in ('String','Real','Integer','Boolean')]
            consumers = ','.join('store.values.settings['+json.dumps(k)+']' for k in keys)
            expected = json.dumps([defaults[k] for k in keys],ensure_ascii=False)
            (directory/'fixture.qml').write_text('''import QtQuick
import Quickshell
import ConfigQml 1.0
Scope {
 id: root
 readonly property var consumers: store.ready ? [CONSUMERS] : []
 ConfigStore { id:store; schema:PluginSchema {} autoSave:false
   sources:[MemorySource { sourceId:"catalog"; data:({}) }]
   onSourceError:function(error) { console.error(error.code); Qt.exit(2); }
 }
 Timer { interval:10; running:true; repeat:true; onTriggered: {
   if (!store.ready) return;
   if (JSON.stringify(root.consumers) !== JSON.stringify(JSON.parse(Quickshell.env("CATALOG_EXPECTED")))) Qt.exit(2);
   else { console.log("CATALOG_BINDINGS_PASS"); Qt.exit(0); }
 } }
 Timer { interval:30000; running:true; onTriggered:Qt.exit(2) }
}
'''.replace('CONSUMERS',consumers))
            run('catalog-'+name+'-'+kind, directory, {'CATALOG_EXPECTED':expected}, 'CATALOG_BINDINGS_PASS')
        catalog_count += 1
    assert catalog_count == 161 and len(overlays['plugins']) == 159
    for subject in ('screen-toolkit','video-wallpaper','config'):
        if subject == 'config':
            manifest = {'id':'config-contract','version':'1','metadata':{'configSchema':{'version':1,'fields':{
                'network':{'type':'Group','fields':{'address':{'type':'String'},'port':{'type':'Real'},
                    'optionalLabel':{'type':'String','optional':True}}},
                'items':{'type':'List','element':{'type':'String'}}}}}}
            defaults = {'network':{'address':'default','port':1},'items':['a','b']}
            schema, _ = compiler.compile_schema(manifest,overlays,'config',defaults)
            cases = [('deep-merge',{'network':{'address':'user'},'items':[],'opaque':{'keep':[False,0,'雪']}},'user:1')]
            legacy_data = defaults
            after = 'user:17'
        else:
            manifest = compiler.shared.load(args.plugins/subject/'manifest.json')
            schema, _ = compiler.compile_schema(manifest,overlays)
            legacy_data = {'paletteColors':''} if subject == 'screen-toolkit' else {'offline.雪':{'volume':0.5,'opaque':False}}
            cases = [('absent',None,'[]' if subject=='screen-toolkit' else '0.5'),
                     ('empty',{},'[]' if subject=='screen-toolkit' else '0.5'),
                     ('unknown',{'opaque':{'keep':[False,0,'雪']}} if subject=='screen-toolkit' else {'opaque':0},
                      '[]' if subject=='screen-toolkit' else 'absent')]
            if subject == 'video-wallpaper':cases.append(('present-map',{'monitors':{},'offline.雪':{'volume':0.5}},'empty'))
            after = '["#123456"]' if subject=='screen-toolkit' else '0.75'
        for case, raw, before in cases:
            directory=args.work_root/(subject+'-'+case);directory.mkdir()
            (directory/'PluginSchema.qml').write_text(schema)
            projection, _ = (None,None) if subject=='config' else compiler.compile_projection(manifest,overlays,['legacy.雪','user:opaque'])
            if projection:(directory/'PluginProjection.qml').write_text(projection)
            (directory/'fixture.qml').write_text(FIXTURE.replace('PROJECTIONS','projections:[PluginProjection {}]' if projection else '')
                .replace('PREFIX','["config"]' if subject=='config' else '["settings"]')
                .replace('FALLBACK','' if subject=='config' else 'fallbackFor:"user:opaque"'))
            legacy=directory/'legacy.json';legacy.write_text(json.dumps(legacy_data,ensure_ascii=False)+'\n');legacy.chmod(0o444)
            identity=(legacy.read_bytes(),legacy.stat().st_ino,legacy.stat().st_mtime_ns,legacy.stat().st_mode)
            user=directory/'user.json'
            if raw is not None:user.write_text(json.dumps(raw,ensure_ascii=False)+'\n')
            initial=user.read_bytes() if user.exists() else None
            for leg in ('load','save','restart'):
                run(subject+'-'+case+'-'+leg,directory,{'CONTRACT_MODE':leg,'CONTRACT_SUBJECT':subject,
                    'CONTRACT_EXPECTED':after if leg=='restart' else before,'CONTRACT_AFTER':after,
                    'CONTRACT_LEGACY':str(legacy),'CONTRACT_USER':str(user)},
                    'PLUGIN_CONTRACT: '+('SAVED' if leg=='save' else leg.upper())+'_PASS')
                assert identity==(legacy.read_bytes(),legacy.stat().st_ino,legacy.stat().st_mtime_ns,legacy.stat().st_mode)
                if leg=='load':assert (user.read_bytes() if user.exists() else None)==initial
                else:
                    saved=json.loads(user.read_text())
                    if subject=='config':assert saved=={**raw,'network':{'address':'user','port':17}}
                    elif subject=='screen-toolkit':assert saved=={**(raw or {}),'paletteColors':['#123456']}
                    else:assert saved=={**(raw or {}),'monitors':{'offline.雪':{'volume':0.75,'opaque':False}}}
    summary={'status':'INERT_METADATA_PASS','catalogManifests':catalog_count,'exactOldOverlays':159,
        'catalogConfigNamespaces':0,'cases':results,'rejectingControls':rejected,
        'legacyIdentityUnchanged':True,'noStartupWrite':True,'separateColdRestart':True,
        'scope':'Compiler/installed library only; production owner and plugin runtime ports unchanged'}
    (args.output/'result.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('PLUGIN_SETTINGS_CONTRACT: PASS ('+str(len(results))+' endpoints, '+str(len(rejected))+' rejecting controls; inert metadata)')


if __name__ == '__main__':
    main()
