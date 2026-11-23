#!/usr/bin/env python3
"""Finite Keybind field/entry/process/cache/writer/reset mappings and controls."""
import argparse
import importlib.util
import json
import re
from pathlib import Path
spec=importlib.util.spec_from_file_location('keybind_syntax',Path(__file__).with_name('plugin-settings-claude-check.py'))
syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
GENERAL=['windowWidth','windowHeight','autoHeight','columnCount','modKeyVariable','hyprlandConfigPath','hyprlandLuaConfigPath','hyprlandParserMode','niriConfigPath','mangoConfigPath','mergeSequentialBinds','showUndescribedBinds','splitLargeWorkspaceCategory','workspaceSplitThreshold']
COLORS=['keyColor'+s for s in ['Alt','Ctrl','Default','Mod2','Mod3','Mod5','Mouse','Numeric','Print','Shift','Super','XF86']]+['keyText'+s for s in ['Alt','Ctrl','Default','Mod2','Mod3','Mod5','Mouse','Numeric','Print','Shift','Super','XF86']]+['keyLabelColor','keyLabelMod2','keyLabelMod3','keyLabelMod5','descriptionTextColor']
CONFIG=GENERAL+COLORS+['bindOverrides']
STAGES=['niriGlobProcess','niriReadProcess','hyprGlobProcess','hyprReadProcess','mangoGlobProcess','mangoReadProcess','hyprDetectProcess','hyprLuaReadProcess','hyprctlBindsProcess']
ANCHORS={
 'Main.qml':['property var _settingsConsumers: new Map()', 'if (!context || !context.current()) return null', '_settingsConsumers.has(context)', 'settingsContext: context', '_settingsConsumers.set(context, client)', 'root._settingsConsumers.delete(context); retired.destroy()', 'context === pluginApi.settingsContext', 'pluginApi.state.cheatsheetSource = source', 'pluginApi.saveState()', 'const context = api?.settingsContext', 'if (!api?.settingsReady || !context?.current() || !bindId) return false', 'api.pluginSettings.bindOverrides = overrides', 'api.saveSettings(function(result)', 'if (!life.current || !context.current()) return', 'if (result.status === "saved" || result.status === "nothing_to_save") client?.refresh()', 'Component.onDestruction: _lifetime.current = false', 'function refresh() { root.refresh(); }'],
 'ParserClient.qml':['required property var settingsContext','readonly property bool current: settingsContext.current()', 'readonly property var cfg: current ? settingsContext.appliedSettings : ({})', 'releaseWorker(); categories = []', 'useCache && publishCache && pluginApi.state?.cheatsheetSource === sourceKey', 'categories = pluginApi.state.cheatsheetData ?? []', 'isCurrent: function() { return root.current && !root.retired && root.sourceKey === source; }', 'root.worker !== generation', 'if (root.publishCache) root.publishCache(source, data, root.compositor)', 'previous.active = false; previous.destroy()', 'onCurrentChanged: if (!current && constructed) retireClient()', 'if (!root.settingsContext.current()) root.retireClient()', 'Component.onDestruction: { retired = true; releaseWorker(); }'],
 'ParserGeneration.qml':['readonly property bool current: active && isCurrent()', 'if (current) finished(data)', 'Component.onDestruction: { active = false; clearParsingData(); cleanupProcesses(); }', 'property int maxParseDepth: 50', 'length < 100)', 'length < 10000)', 'length < 20000)', 'MangoParser.parseMangoConfig(text, pluginApi, findMangoUnquotedComment, extractMangoCategory, formatMangoKeyCombo, formatMangoAction, mangoAxisMap, mangoButtonMap, collectedBinds)', 'cfg.bindOverrides || ({})', 'cfg.showUndescribedBinds ?? true', 'cfg.showUndescribedBinds ?? false', '(b.dispatcher === "__lua") ? "__lua"', 'cfg.mergeSequentialBinds ?? true'],
 'ParserProcess.qml':['function start() { pending = true; running = true; }', 'if (!pending) return; pending = false; settled(code, status)', 'onExited: (code, status) => settle(code, status)', 'onRunningChanged: if (!running) settle(-1, 0)'],
 'Panel.qml':['pluginApi?.mainInstance?.clientFor(pluginApi)', 'return settingsConsumer?.categories ?? []', 'text: bindRow.itemData.desc', 'onSplitWorkspacesChanged: { categories = processCategories(rawCategories); }', 'onWorkspaceSplitThresholdChanged: { categories = processCategories(rawCategories); }', 'updateColumnItems()', 'updateBind(pluginApi, bindId, desc, false)', 'updateBind(pluginApi, bindId, "", true)', 'settingsConsumer?.refresh()', 'interval: 100', 'interval: 4000'],
 'BarWidget.qml':['BarService.openPluginSettings(root.screen, root.pluginApi.manifest)', 'root.pluginApi.openPanel(root.screen)', 'pluginApi.openPanel(screen)'],
 'Settings.qml':['settingsConsumerFor(pluginApi.runtimeContext)?.refresh()', 'settingsConsumerFor(root.pluginApi.runtimeContext)?.refresh()', 'pluginApi.resetFields(["descriptionTextColor"])']}
def check(sources,manifest):
    code={name:syntax.syntax.compact('import QtQuick\nItem {\n'+text+'\n}' if name.endswith('.js') else text)[0] for name,text in sources.items()}
    fields=manifest['metadata']['settingsSchema']['fields']; assert set(fields)==set(CONFIG+['cheatsheetData','detectedCompositor'])
    assert len(CONFIG)==44 and all(fields[key]['editorUsage']=='configuration' for key in CONFIG)
    assert all(fields[key]['editorUsage']=='operational' for key in ['cheatsheetData','detectedCompositor'])
    assert manifest['entryPoints']==dict(main='Main.qml',barWidget='BarWidget.qml',panel='Panel.qml',settings='Settings.qml')
    for key in CONFIG: syntax.require(code['Settings.qml'],'pluginApi?.field("'+key+'")',key+' field intent')
    for name,anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(code[name],anchor,name+': '+anchor)
    for key in GENERAL:
        target='Panel.qml' if key in ['windowWidth','windowHeight','autoHeight','columnCount','splitLargeWorkspaceCategory','workspaceSplitThreshold'] else 'ParserGeneration.qml'
        syntax.require(code[target],'cfg.'+key,key+' actual selected consumer')
    for key in COLORS: syntax.require(code['Panel.qml'],'cfg.'+key,key+' actual color/label consumer')
    for suffix in ['Super','Ctrl','Shift','Alt','Mod3','Mod2','Mod5','XF86','Print','Numeric','Mouse','Default']:
        keys=['keyColor'+suffix,'keyText'+suffix]+(['keyLabel'+suffix] if suffix.startswith('Mod') else [])
        syntax.require(code['Settings.qml'],'onResetRequested: pluginApi.resetFields('+json.dumps(keys)+')','row Reset '+suffix)
    for stage in STAGES:
        syntax.require(code['ParserGeneration.qml'],'id: '+stage,'stage '+stage)
        syntax.require(code['ParserGeneration.qml'],'if ('+stage+'.running) '+stage+'.running = false','stage retirement '+stage)
    assert code['ParserGeneration.qml'].count('onSettled:')==9
    assert code['ParserGeneration.qml'].count('if(!root.current)return')>=9
    assert 'pluginSettings' not in code['ParserClient.qml'] and 'pluginSettings' not in code['ParserGeneration.qml'],'read-only parser boundary'
    return dict(configuration=CONFIG,operational=['cheatsheetData','detectedCompositor'],stages=STAGES,hidden=['keyLabelColor'],modeSpecific='bindOverrides only hyprctl; Mango has no merge policy',runtimeAcceptance=False)
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['source','plugins','report']: p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--selftest',action='store_true');p.add_argument('--mango-baseline',type=Path);a=p.parse_args();root=a.plugins/'keybind-cheatsheet'
    sources={f.name:f.read_text() for f in root.glob('*.qml')}; sources['MangoParser.js']=(root/'MangoParser.js').read_text(); manifest=json.loads((root/'manifest.json').read_text())
    result=check(sources,manifest);controls=[]
    mutations=[('Main.qml','settingsContext: context','settingsContext: pluginApi.settingsContext','context'),('Main.qml','context === pluginApi.settingsContext','true','cache-writer'),('Main.qml','api.pluginSettings.bindOverrides = overrides','pluginApi.pluginSettings.bindOverrides = overrides','origin-writer'),('Main.qml','if (!life.current || !context.current()) return','if (false) return','writer-retirement'),('ParserClient.qml','pluginApi.state?.cheatsheetSource === sourceKey','true','cache-qualification'),('ParserClient.qml','root.worker !== generation','false','generation'),('ParserClient.qml','previous.active = false','previous.active = true','stage-retirement'),('ParserProcess.qml','onRunningChanged: if (!running) settle(-1, 0)','onRunningChanged: {}','failed-start'),('Panel.qml','pluginApi?.mainInstance?.clientFor(pluginApi)','pluginApi?.mainInstance?.settingsConsumer','panel'),('Panel.qml','text: bindRow.itemData.desc','text: "wrong"','child'),('Panel.qml','onSplitWorkspacesChanged: { categories = processCategories(rawCategories); }','onSplitWorkspacesChanged: {}','split-invalidation'),('Panel.qml','onWorkspaceSplitThresholdChanged: { categories = processCategories(rawCategories); }','onWorkspaceSplitThresholdChanged: {}','threshold-invalidation'),('Settings.qml','onResetRequested: pluginApi.resetFields(["keyColorSuper", "keyTextSuper"])','onResetRequested: {}','row-reset'),('Settings.qml','settingsConsumerFor(pluginApi.runtimeContext)?.refresh()','settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)?.refresh()','refresh-origin')]
    for stage in STAGES: mutations.append(('ParserGeneration.qml','if ('+stage+'.running) '+stage+'.running = false','if (false) '+stage+'.running = false','retire-'+stage))
    if a.selftest:
        for name,old,new,label in mutations:
            assert old in sources[name],label; changed=dict(sources); changed[name]=changed[name].replace(old,new)
            try: check(changed,manifest)
            except (AssertionError,ValueError) as error: controls.append(dict(control=label,rejectedAt=str(error)))
            else: raise RuntimeError('Keybind control escaped '+label)
    equality=False
    if a.mango_baseline:
        original=a.mango_baseline.read_text()
        body=re.search(r'function parseMangoConfig\(text\)\s*\{(.*?)\n  \}\n\n  function extractMangoCategory',original,re.S); assert body,'original Mango body'
        extracted=sources['MangoParser.js'].split('{',1)[1].rsplit('}',1)[0]
        def parsed_body(text): return syntax.syntax.compact('import QtQuick\nItem { function parseMangoConfig(text) {'+text+'\n} }')[0]
        assert parsed_body(body.group(1))==parsed_body(extracted),'original/extracted Mango parsed-body equality'
        equality=True
    a.report.write_text(json.dumps(dict(status='PASS',member=result,controls=controls,mangoOriginalBodyEqual=equality,runtimeAcceptance=False),indent=2)+'\n')
    print('KEYBIND_CHECK: PASS (44 fields, 9 stages, %d controls)'%len(controls))
if __name__=='__main__':main()
