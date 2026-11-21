#!/usr/bin/env python3
"""Finite parsed output field/caller/request/physical-owner contract."""
import argparse
from collections import Counter
import importlib.util
import json
from pathlib import Path
import re

spec=importlib.util.spec_from_file_location('output_syntax',Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
spec=importlib.util.spec_from_file_location('output_anchors',Path(__file__).with_name('plugin-settings-action-group-check.py'))
anchors=importlib.util.module_from_spec(spec);spec.loader.exec_module(anchors)
FIELDS={'display-settings':['iconColor','niriConfigPath'],'monitor-layout':['backend','gridSize','hyprctlCommand','iconColor','snapToGrid','swayCommand']}
READS={
 'display-settings/BarWidget.qml':['cfg.iconColor'],
 'display-settings/DisplayConfigClient.qml':['cfg.niriConfigPath'],
 'monitor-layout/BarWidget.qml':['cfg.iconColor'],
 'monitor-layout/Main.qml':['settings.backend','policy.settings.gridSize','policy.settings.snapToGrid'],
 'monitor-layout/backends/HyprlandBackend.js':['cfg.hyprctlCommand'],
 'monitor-layout/backends/SwayBackend.js':['cfg.swayCommand']}
POLICY={
 'display-settings/Main.qml':['property var configClients: new Map()','configClients.has(context)','configClients.set(context, client)','settingsContext: context','function refresh(context)','refreshConfig(context)','function refreshConfig(context)','settingsConsumerFor(context)?.refresh()'],
 'display-settings/DisplayConfigClient.qml':['readonly property bool current: settingsContext.current()','readonly property var cfg: settingsContext.settingsView','previous.cancel(); previous.destroy()','parser = parserComponent.createObject(root, {configPath: configPath})','parser.start()','if (constructed) refresh(true)','if (!current && constructed) { cancel(); retire(root); }'],
 'display-settings/NiriConfigParser.qml':['property bool cancelled: false','cancelled = true','readProcess.running = false','globProcess.running = false','if (cancelled) return','if (root.cancelled) return'],
 'display-settings/Panel.qml':['mainInst?.settingsConsumerFor(pluginApi?.settingsContext)','configClient?.outputs','configClient?.loading','mainInst.refresh(root.pluginApi?.settingsContext)'],
 'display-settings/Settings.qml':['mainInstance?.refreshConfig(root.pluginApi.runtimeContext)'],
 'monitor-layout/Main.qml':['readonly property var cfg: policyContext?.settingsView','function capturePolicy(context)','const settings = context.settingsView','backend: resolveBackendId(settings)','property var fetchPolicy: null','property var applyPolicy: null','readonly property bool fetchCurrent: fetchPolicy?.context?.current()','if (fetchPolicy && !fetchCurrent) fetchProcess.running = false','const policy = fetchPolicy','backendParseOutputs(rawText, policy)','policy.backend === "sway"','policy.backend === "hyprland"','if (!policy?.context?.current()) return','const policy = root.applyPolicy','root.refreshOutputs(policy.context, policy)','fetchPolicy = policy','applyPolicy = policy','retainedPolicy || capturePolicy(context)','roundCoordinate(x, snap, policy)','roundCoordinate(y, snap, policy)','if (!policy || !activatePolicy(policy.context)) return','backendBuildApplyCommand(policy)','backendBuildFetchCommand(policy)','backendBuildConfigFileContent(policy)','"backend": policy.backend'],
 'monitor-layout/Panel.qml':['setOutputPosition(selectedOutput.outputId, nextX, nextY, true, root.pluginApi?.settingsContext)','setOutputPosition(outputData.outputId, outputTile.pressOutputX + deltaX, outputTile.pressOutputY + deltaY, true, root.pluginApi?.settingsContext)','setOutputScale(selectedOutput.outputId, nextScale, root.pluginApi?.settingsContext)','selectOutput(outputData.outputId, root.pluginApi?.settingsContext)','setOutputResolution(selectedOutput.outputId, key, root.pluginApi?.settingsContext)','refreshOutputs(root.pluginApi?.settingsContext)','resetDraftOutputs(root.pluginApi?.settingsContext)','applyLayout(root.pluginApi?.settingsContext)','getConfigurationScript(root.pluginApi?.settingsContext)','noteConfigurationCopied(root.pluginApi?.settingsContext)'],
 'monitor-layout/Settings.qml':['mainInstance?.activatePolicy(root.pluginApi.runtimeContext)']}
EFFECTS={
 'display-settings/Main.qml':dict(IpcHandler=1),
 'display-settings/DisplayConfigClient.qml':{},
 'display-settings/NiriConfigParser.qml':dict(Process=2),
 'display-settings/NiriOutputProvider.qml':dict(Process=2),
 'display-settings/WlrOutputProvider.qml':dict(Process=1),
 'display-settings/UdevMonitor.qml':dict(Process=1),
 'monitor-layout/Main.qml':dict(Process=2,IpcHandler=1)}
CALLS={
 'display-settings/Panel.qml':dict(settingsConsumerFor=1,refresh=2,startMonitor=1,stopMonitor=1,setMode=1,setScale=2,setTransform=1,setVrr=1,setPower=1),
 'display-settings/Settings.qml':dict(refreshConfig=1),
 'monitor-layout/Panel.qml':dict(getSelectedOutput=1,setOutputPosition=2,setOutputScale=1,selectOutput=1,setOutputResolution=1,refreshOutputs=2,resetDraftOutputs=1,applyLayout=1,getConfigurationScript=3,noteConfigurationCopied=1),
 'monitor-layout/Settings.qml':dict(activatePolicy=1)}


def check(sources,manifests,dictionaries):
    codes={};trees={}
    for name,text in sources.items():
        if name.endswith('.js'):text='QtObject { function script() {\n'+re.sub(r'^\.pragma library\s*$','',text,flags=re.M)+'\n} }'
        codes[name],trees[name]=syntax.compact(text)
    rows=[]
    for member,fields in FIELDS.items():
        metadata=manifests[member]['metadata']['settingsSchema']['fields']
        if set(metadata)!=set(fields) or any(value.get('editorUsage')!='configuration' for value in metadata.values()):raise ValueError(member+': reviewed leaf mapping changed')
        entries=dict(main='Main.qml',barWidget='BarWidget.qml',panel='Panel.qml',settings='Settings.qml')
        if member=='monitor-layout':entries['controlCenterWidget']='ControlCenterWidget.qml'
        if manifests[member]['entryPoints']!=entries:raise ValueError(member+': reviewed runtime entries changed')
        settings=codes[member+'/Settings.qml']
        for anchor in ('visible: root.pluginApi?.scopeKind === "instance"','root.pluginApi?.tr("settings.shared-effect")'):anchors.require(settings,anchor,member+': shared-effect UI')
        for locale,data in dictionaries[member].items():
            if not data.get('settings',{}).get('shared-effect','').strip():raise ValueError(member+': missing explanation '+locale)
        rows.append(dict(plugin=member,configuration=fields,protected=[]))
    for mapping in (READS,POLICY):
        for name,items in mapping.items():
            for anchor in items:anchors.require(codes[name],anchor,name+': '+anchor)
    for name,code in codes.items():
        raw=sources[name].encode();effects=Counter()
        for node in syntax.walk(trees[name].root_node):
            if node.type!='ui_object_definition':continue
            match=re.match(rb'(Process|Socket|IpcHandler|MediaPlayer|Video)\s*\{',raw[node.start_byte:node.end_byte].lstrip())
            if match:effects[match.group(1).decode()]+=1
        if dict(effects)!=EFFECTS.get(name,{}):raise ValueError(name+': unreviewed effect owner '+repr(dict(effects)))
        callers=dict(Counter(re.findall(r'(?:mainInst|mainInstance)\??\.(\w+)\(',code)))
        if callers!=CALLS.get(name,{}):raise ValueError(name+': unreviewed caller '+repr(callers))
        if 'execDetached(' in code and name!='monitor-layout/Panel.qml':raise ValueError(name+': unreviewed detached effect')
    for name in ('display-settings/DisplayConfigClient.qml','display-settings/NiriConfigParser.qml'):
        if 'saveSettings(' in codes[name] or 'pluginSettings.' in codes[name]:raise ValueError(name+': query gained a native writer')
    parser=codes['display-settings/NiriConfigParser.qml']
    if parser.count('if(cancelled)return')!=5 or parser.count('if(root.cancelled)return')!=4:raise ValueError('every parser queue/read/glob/completion stage must fence cancellation')
    if codes['display-settings/Main.qml'].count('NiriOutputProvider{')!=1 or codes['display-settings/Main.qml'].count('WlrOutputProvider{')!=1 or codes['display-settings/Main.qml'].count('UdevMonitor{')!=1:raise ValueError('physical providers must stay singular')
    if 'propertyvarliveOutputs:[]' not in codes['monitor-layout/Main.qml'] or 'propertyvardraftOutputs:[]' not in codes['monitor-layout/Main.qml']:raise ValueError('shared output layout owner changed')
    return rows


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--plugins',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);parser.add_argument('--selftest',action='store_true');args=parser.parse_args()
    sources={};manifests={};dictionaries={}
    for member in FIELDS:
        manifests[member]=json.loads((args.plugins/member/'manifest.json').read_text())
        dictionaries[member]={path.name:json.loads(path.read_text()) for path in (args.plugins/member/'i18n').glob('*.json')}
        sources.update({str(path.relative_to(args.plugins)):path.read_text() for path in (args.plugins/member).rglob('*') if path.suffix in ('.qml','.js')})
    rows=check(sources,manifests,dictionaries);controls=[]
    if args.selftest:
        mutations=[
          ('display-settings/DisplayConfigClient.qml','settingsContext.settingsView','pluginApi.pluginSettings','shared-parser-policy'),
          ('display-settings/DisplayConfigClient.qml','previous.cancel(); previous.destroy()','previous.destroy()','uncancelled-parser-generation'),
          ('display-settings/Panel.qml','mainInst?.settingsConsumerFor(pluginApi?.settingsContext)','mainInst?.settingsConsumerFor()','shared-panel-parser'),
          ('display-settings/NiriConfigParser.qml','cancelled = true','cancelled = false','unfenced-parser-stages'),
          ('display-settings/Main.qml','WlrOutputProvider { id: wlrProvider }','WlrOutputProvider { id: wlrProvider } WlrOutputProvider {}','duplicate-physical-provider'),
          ('monitor-layout/Main.qml','const settings = context.settingsView','const settings = pluginApi.pluginSettings','shared-action-policy'),
          ('monitor-layout/Main.qml','backendParseOutputs(rawText, policy)','backendParseOutputs(rawText, capturePolicy())','mutable-fetch-parser'),
          ('monitor-layout/Main.qml','root.refreshOutputs(policy.context, policy)','root.refreshOutputs()','lost-apply-origin'),
          ('monitor-layout/Main.qml','roundCoordinate(x, snap, policy)','roundCoordinate(x, snap, capturePolicy())','shared-grid-policy'),
          ('monitor-layout/Panel.qml','applyLayout(root.pluginApi?.settingsContext)','applyLayout()','omitted-apply-origin'),
          ('monitor-layout/Panel.qml','getConfigurationScript(root.pluginApi?.settingsContext)','getConfigurationScript()','shared-script-policy'),
          ('monitor-layout/Main.qml','fetchProcess.running = false','fetchProcess.running = true','retired-fetch-not-stopped')]
        for name,old,new,label in mutations:
            count=sources[name].count(old)
            if count<1:raise RuntimeError('stale output control '+label)
            changed=dict(sources);changed[name]=changed[name].replace(old,new)
            try:check(changed,manifests,dictionaries)
            except ValueError as error:controls.append(dict(control=label,rejectedAt=str(error)))
            else:raise RuntimeError('output control escaped '+label)
        for member in FIELDS:
            changed=json.loads(json.dumps(manifests));changed[member]['entryPoints']['panel']='Unreviewed.qml'
            try:check(sources,changed,dictionaries)
            except ValueError as error:controls.append(dict(control='unreviewed-entry',plugin=member,rejectedAt=str(error)))
            else:raise RuntimeError('output entry escaped')
    args.report.write_text(json.dumps(dict(status='PASS',kind='finite-parsed-contract',members=rows,controls=controls,runtimeAcceptance=False,completeGroupAcceptance=False),indent=2)+'\n');print('OUTPUT_GROUP_CHECK: PASS (%d members; %d controls)'%(len(rows),len(controls)))


if __name__=='__main__':main()
