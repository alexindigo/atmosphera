#!/usr/bin/env python3
"""Finite parsed Clipboard field, caller, shared-owner and retirement contract."""
import argparse
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import re

spec=importlib.util.spec_from_file_location('actions',Path(__file__).with_name('plugin-settings-action-group-check.py'))
actions=importlib.util.module_from_spec(spec);spec.loader.exec_module(actions)
ANCHORS={
 'Main.qml':[
  'property var _settingsConsumers: new Map()', 'if (!context || !context.current()) return null',
  'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)',
  'settingsContext: context, owner: root', 'root._settingsConsumers.delete(context)',
  'listProc.command = ["cliphist", "list"]', 'root.rawHistory = raw',
  'const parsed = root.parseItems(raw)', 'root.copiedAt = nextCopiedAt',
  'nextCopiedAt[id] = prior[id] || now', 'root.saveCopiedAt()',
  'root.pinnedItems = [...root.pinnedItems, record]', 'pinnedFile.setText(body)',
  'function getImage(id, context)', 'context = context || pluginApi?.settingsContext',
  'if (!root.imageOwnerCurrent(context)) return',
  'return !!context && context.current() && (context.settingsView.showImagePreviews ?? true)',
  'readonly property bool decodingCurrent: decodingOwners.some(context => root.imageOwnerCurrent(context))',
  'if (!decodingCurrent && decodingId)', 'decodeProc.running = false',
  'if (exitCode === 0 && id && admitted.some(context => root.imageOwnerCurrent(context)))',
  'if (!owners.some(context => root.imageOwnerCurrent(context)))',
  'root.decodingOwners = owners', 'root.decodingOwners = [...root.decodingOwners, context]',
  'root.decodeOwners = Object.assign({}, root.decodeOwners, {[sid]: [...owners, context]})',
 ],
 'HistoryClient.qml':[
  'readonly property bool current: settingsContext.current()',
  'readonly property var limit: settingsContext.settingsView.maxHistorySize ?? 100',
  'readonly property string source: owner.rawHistory', 'command: ["head", "-n", count]',
  'if (client.current && client.request === projection)',
  'client.items = code === 0 ? client.owner.parseItems(stdout.text) : []',
  'old.running = false', 'old.destroy()',
  'onSourceChanged: if (constructed) refresh()', 'onLimitChanged: if (constructed) refresh()',
  'retire(client)', 'Component.onDestruction: cancel()', 'count: String(limit)',
  'projection.write(projection.payload)', 'projection.stdinEnabled = false',
 ],
 'Panel.qml':[
  'settingsConsumerFor(pluginApi.settingsContext)', 'const all = root.settingsConsumer?.items ?? []',
  'const pinned = pluginApi?.mainInstance?.pinnedItems ?? []',
  'const _rev = root.settingsConsumer?.itemsRevision ?? 0',
  'readonly property bool showImagePreviews: pluginApi?.pluginSettings?.showImagePreviews ?? true',
  'const d = pluginApi?.pluginSettings?.density ?? "comfortable"', 'spacing: root.densitySpacing',
 ],
 'ClipboardItem.qml':[
  'getImage(card.entryId, card.pluginApi.settingsContext)',
  'onPluginApiChanged: _requestDecode()', 'Component.onCompleted: _requestDecode()',
  '(card.pluginApi?.pluginSettings?.showImagePreviews ?? true)',
  'const iso = main.copiedAt?.[card.entryId]',
 ],
 'Settings.qml':[
  'visible: root.pluginApi?.scopeKind === "instance"', 'root.pluginApi?.tr("settings.shared-effect")',
  'root.maxHistorySizeField.set(value)', 'root.showImagePreviewsField.set(checked)',
  'root.densityField.set(key)',
 ]}

def check(sources,manifest,dictionaries):
    fields={'maxHistorySize','showImagePreviews','density'}
    assert set(manifest['metadata']['settingsSchema']['fields'])==fields,'declared fields'
    assert manifest['entryPoints']==dict(main='Main.qml',panel='Panel.qml',barWidget='BarWidget.qml',settings='Settings.qml'),'entry mapping'
    assert set(sources)=={'Main.qml','HistoryClient.qml','Panel.qml','ClipboardItem.qml','Settings.qml','BarWidget.qml'},'reviewed component set'
    codes={name:actions.syntax.compact(text)[0] for name,text in sources.items()}
    for name,anchors in ANCHORS.items():
        for anchor in anchors:actions.require(codes[name],anchor,name+': '+anchor)
    for name,text in sources.items():
        raw=text.encode();tree=actions.syntax.compact(text)[1]
        processes=sum(node.type=='ui_object_definition' and bool(re.match(rb'Process\s*\{',raw[node.start_byte:node.end_byte])) for node in actions.syntax.walk(tree.root_node))
        assert processes==({'Main.qml':8,'HistoryClient.qml':1}.get(name,0)),name+': sole effect/projection owners'
        assert 'execDetached(' not in codes[name],name+': detached effect'
    assert 'pluginSettings' not in codes['Main.qml'], 'shared preference gate in content owner'
    assert codes['Panel.qml'].count('constall=root.settingsConsumer?.items??[]')==2,'selected count and filtered rows'
    assert codes['Panel.qml'].count('mainInstance?.items??')==1,'only shared wipe availability reads full content'
    assert 'Math.floor(' not in codes['HistoryClient.qml'] and '.slice(' not in codes['HistoryClient.qml'],'native head domain changed'
    callers=[(name,m[1]) for name,code in codes.items() for m in re.finditer(r'(?:\?\.|\.)getImage\(([^()]*)\)',code)]
    assert callers==[('ClipboardItem.qml','card.entryId,card.pluginApi.settingsContext')],'originating decode callers'
    for locale,words in dictionaries.items():assert words['settings']['shared-effect'].strip(),locale
    return dict(plugin='clipboard',fields=sorted(fields),protectedContent=['pins','timestamps','full-history','image-cache'],processOwners=8,projectionOwners=1)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--plugins',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);parser.add_argument('--selftest',action='store_true');args=parser.parse_args()
    root=args.plugins/'clipboard';sources={p.name:p.read_text() for p in root.glob('*.qml')};manifest=json.loads((root/'manifest.json').read_text());words={p.stem:json.loads(p.read_text()) for p in (root/'i18n').glob('*.json')}
    member=check(sources,manifest,words);controls=[]
    if args.selftest:
        mutations=[
          ('Main.qml','["cliphist", "list"]','["cliphist", "list", "limited"]','full-content-owner'),
          ('Main.qml','context.current() && (context.settingsView.showImagePreviews ?? true)','true','decode-policy'),
          ('Main.qml','admitted.some(context => root.imageOwnerCurrent(context))','true','decode-retirement'),
          ('HistoryClient.qml','settingsContext.settingsView.maxHistorySize','owner.pluginApi.pluginSettings.maxHistorySize','selected-limit'),
          ('HistoryClient.qml','client.current && client.request === projection','true','projection-generation'),
          ('HistoryClient.qml','String(limit)','String(Math.floor(limit))','real-head-domain'),
          ('HistoryClient.qml','old.running = false','old.running = true','projection-retirement'),
          ('Panel.qml','settingsConsumerFor(pluginApi.settingsContext)','settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)','panel-context'),
          ('Panel.qml','root.settingsConsumer?.items ?? []','pluginApi?.mainInstance?.items ?? []','panel-rows'),
          ('ClipboardItem.qml','getImage(card.entryId, card.pluginApi.settingsContext)','getImage(card.entryId)','decode-origin'),
          ('ClipboardItem.qml','card.pluginApi?.pluginSettings?.showImagePreviews','card.pluginApi?.mainInstance?.pluginApi?.pluginSettings?.showImagePreviews','selected-preview'),
          ('Settings.qml','scopeKind === "instance"','scopeKind === "plugin"','shared-explanation'),
        ]
        for name,old,new,label in mutations:
            candidate=deepcopy(sources)
            # Token-aware regex tolerates the normal hook's QML formatting.
            tokens=re.findall(r'"(?:[^"\\]|\\.)*"|\x27(?:[^\x27\\]|\\.)*\x27|[^\s]',old)
            pattern=r'\s*'.join(re.escape(t) for t in tokens)
            candidate[name],count=re.subn(pattern,lambda _:new,candidate[name],count=1);assert count==1,label
            actions.syntax.compact(candidate[name]) # Every control is valid parsed QML.
            try:check(candidate,manifest,words)
            except (ValueError,AssertionError):controls.append(label)
            else:raise AssertionError('contract mutation escaped '+label)
    result=dict(status='PASS',members=[member],controls=controls,generalJavaScriptProof=False)
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(result,indent=2)+'\n');print('CLIPBOARD_GROUP: PASS '+str(len(controls))+' controls')

if __name__=='__main__':main()
