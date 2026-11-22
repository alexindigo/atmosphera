#!/usr/bin/env python3
"""Finite parsed OBS policy, caller, physical-owner and continuation contract."""
import argparse
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import re

spec=importlib.util.spec_from_file_location('actions',Path(__file__).with_name('plugin-settings-action-group-check.py'))
actions=importlib.util.module_from_spec(spec);spec.loader.exec_module(actions)
FIELDS={'autoCloseManagedObs','barLabelMode','launchBehavior','leftClickAction','openVideosAfterStop','pollIntervalMs','showBarWhenReady','showBarWhenRecording','showBarWhenReplay','showBarWhenStreaming','showControlCenterWhenReady','showControlCenterWhenRecording','showControlCenterWhenReplay','showControlCenterWhenStreaming','showElapsedInBar','videosOpener','videosPath'}
ANCHORS={
 'Main.qml':[
  'property var _settingsConsumers: new Map()', 'if (retired || !context?.current()) return null',
  'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)',
  'settingsContext:context', 'root._settingsConsumers.delete(context)', '_settingsConsumers.set(context,client)',
  'context = context || pluginApi?.settingsContext', 'const client = settingsConsumerFor(context)',
  'launchBehavior:client.launchBehavior', 'autoCloseManagedObs:client.autoCloseManagedObs',
  'openVideosAfterStop:client.openVideosAfterStop', 'videosPath:client.videosPath', 'videosOpener:client.videosOpener',
  'activeAction = policy', 'if (actionBusy) return null',
  'if (!lifetime.alive || root.activeAction !== policy) return',
  'if (!policy.context.current()) { root.finishAction(false); return; }',
  'if (policy && !actionCurrent) Qt.callLater(function()',
  'if (lifetime.alive && root.activeAction === policy && !policy.context.current()) root.finishAction(false)',
  'policy.launchBehavior === "minimized-to-tray"', 'managedObsLaunch = policy.autoCloseManagedObs',
  'probeObsRunning(actionCallback(policy, function(running)',
  'requestObs(statusRequestType, {}, actionCallback(policy, function(status)',
  'requestObs(requestType, {}, actionCallback(policy, function()',
  'fetchAutoCloseState(actionCallback(policy, function(state)',
  'terminateObsAndConfirm(actionCallback(policy, function(closed)',
  'terminateObs(actionCallback(policy, function()',
  'shutdownConfirmCallback = callback', 'shutdownConfirmPolicy = policy',
  'root.activeAction === policy && policy.context.current()',
  'root.probeObsRunning(root.actionCallback(policy, function(running) { callback(!running); }))',
  'shutdownConfirmTimer.stop()', 'shutdownConfirmCallback = null', 'shutdownConfirmPolicy = null',
  'requestObs("SaveReplayBuffer", {}, actionCallback(policy, function()',
  'payload.openVideos && policy.openVideosAfterStop', 'if (lifetime.alive) root.openVideosForPolicy(policy)',
  'if (retired || !policy?.context.current() || policy.videosPath === "" || policy.videosOpener === "") return',
  'Quickshell.execDetached([policy.videosOpener, policy.videosPath])',
  'context === pluginApi.settingsContext || runtimeApi?.settingsContext === context',
  'runtimeApi.togglePanel(screen, anchorItem)', 'BarService.openPluginSettings(screen, pluginApi.manifest)',
  'managedStateFile.setText(JSON.stringify', 'managedObsLaunch: managedObsLaunch',
  'const hasActiveOutputs = state.recordActive || state.replayActive || state.streamActive || state.virtualCamActive',
  'command: ["pidof", "obs"]', 'command: ["pkill", "-x", "obs"]',
  'source: "lib/ObsWebSocketTransport.qml"', 'watchChanges: true', 'root.loadWebsocketConfig()',
  '_lifetime.alive = false', 'retired = true',
 ],
 'ObsClient.qml':[
  'readonly property var settings: settingsContext.settingsView',
  'readonly property bool current: !owner.retired && settingsContext.current()',
  'Math.max(owner.minimumPollIntervalMs, Number(settings.pollIntervalMs ?? defaults.pollIntervalMs ?? owner.defaultPollIntervalMs))',
  'readonly property int pollIntervalMs:', 'interval: client.pollIntervalMs', 'running: client.current',
  'if (!client.owner.actionBusy) client.owner.refresh()',
  'client.retire(client)', 'owner.outputState', 'Ui.shouldShowInBar(owner.outputState, visibilitySettings)',
  'Ui.shouldShowInControlCenter(owner.outputState, visibilitySettings, connected)',
  'configuredVideosPath === "" ? owner.defaultVideosPath', 'configuredVideosPath === "~" ? owner.homeDir',
  'configuredVideosPath.startsWith("~/")',
 ],
 'Settings.qml':['visible: root.pluginApi?.scopeKind === "instance"','root.pluginApi.tr("settings.shared-effect")'],
}
for name in ('BarWidget.qml','Panel.qml','ControlCenterWidget.qml','components/ObsButton.qml'):
    ANCHORS[name]=['root.pluginApi?.mainInstance?.settingsConsumerFor(root.pluginApi.settingsContext)']
for name in ('BarWidget.qml','components/ObsButton.qml'):
    ANCHORS[name].append('root.service.runPrimaryAction(root.screen, root, root.pluginApi)')
for method in ('launchObs','toggleRecord','toggleReplay','toggleStream','saveReplay','openVideos','runSecondaryAction','runMiddleAction'):
    ANCHORS['ObsClient.qml'].append('owner.'+method+'(settingsContext)')
ANCHORS['ObsClient.qml'].append('owner.runPrimaryAction(screen, anchorItem, settingsContext, runtimeApi)')

def check(sources,manifest,dictionaries):
    fields=manifest['metadata']['settingsSchema']['fields'];assert set(fields)==FIELDS,'all17 declared configuration fields'
    assert all(value['editorUsage']=='configuration' for value in fields.values())
    assert fields['pollIntervalMs']['type']=='Real','native interval domain'
    assert manifest['entryPoints']==dict(main='Main.qml',settings='Settings.qml',panel='Panel.qml',barWidget='BarWidget.qml',controlCenterWidget='ControlCenterWidget.qml')
    assert set(sources)==set(ANCHORS)|{'lib/ObsWebSocketTransport.qml'},'reviewed component closure'
    codes={name:actions.syntax.compact(text)[0] for name,text in sources.items()}
    for name,anchors in ANCHORS.items():
        for anchor in anchors:actions.require(codes[name],anchor,name+': '+anchor)
    for field in FIELDS:
        actions.require(codes['ObsClient.qml'],'settings.'+field,field+': selected read')
        actions.require(codes['Settings.qml'],'pluginApi?.field("'+field+'")',field+': declared handle')
        assert re.search(r'root\.'+re.escape(field)+r'Field\.set\(',codes['Settings.qml']),field+': explicit intent'
    assert 'pluginSettings' not in codes['ObsClient.qml'] and 'pluginSettings' not in codes['Main.qml'],'no shared preference reads'
    for name,text in sources.items():
        raw=text.encode();tree=actions.syntax.compact(text)[1]
        for kind,expected in [('Process',2 if name=='Main.qml' else 0),('WebSocket',1 if name=='lib/ObsWebSocketTransport.qml' else 0),('FileView',2 if name=='Main.qml' else 0)]:
            count=sum(node.type=='ui_object_definition' and bool(re.match((kind+r'\s*\{').encode(),raw[node.start_byte:node.end_byte])) for node in actions.syntax.walk(tree.root_node))
            assert count==expected,name+': singular '+kind+' owner'
        if name!='Main.qml':assert 'execDetached(' not in codes[name],name+': physical dispatch leaked'
    for method in ('launchObs','toggleRecord','toggleReplay','toggleStream','saveReplay','openVideos'):
        actions.require(codes['Main.qml'],'root.'+method+'()',method+': explicitly shared IPC remains')
    for locale,words in dictionaries.items():assert words['settings']['shared-effect'].strip(),locale
    return dict(plugin='obs-control',fields=sorted(FIELDS),physicalProcessOwners=2,websocketOwners=1,credentialAndManagedStateFileOwners=2)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--plugins',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);parser.add_argument('--selftest',action='store_true');args=parser.parse_args()
    root=args.plugins/'obs-control';sources={str(p.relative_to(root)):p.read_text() for p in root.rglob('*.qml')};manifest=json.loads((root/'manifest.json').read_text());words={p.stem:json.loads(p.read_text()) for p in (root/'i18n').glob('*.json')}
    member=check(sources,manifest,words);controls=[]
    if args.selftest:
        mutations=[
          ('ObsClient.qml','settingsContext.settingsView','owner.pluginApi.pluginSettings','selected-policy'),
          ('ObsClient.qml','Number(settings.pollIntervalMs','Math.floor(settings.pollIntervalMs','typed-domain'),
          ('ObsClient.qml','running: client.current','running: true','poll-retirement'),
          ('ObsClient.qml','owner.toggleRecord(settingsContext)','owner.toggleRecord()','action-origin'),
          ('ObsClient.qml','client.retire(client)','client.refresh()','client-lifetime'),
          ('Main.qml','policy.launchBehavior ===','launchBehavior ===','admitted-launch'),
          ('Main.qml','managedObsLaunch = policy.autoCloseManagedObs','managedObsLaunch = autoCloseManagedObs','managed-admission'),
          ('Main.qml','root.activeAction !== policy','false','operation-identity'),
          ('Main.qml','if (!policy.context.current())','if (false)','callback-retirement'),
          ('Main.qml','policy.videosOpener, policy.videosPath','videosOpener, videosPath','captured-opener'),
          ('Main.qml','root.openVideosForPolicy(policy)','root.openVideos()','delayed-toast'),
          ('Main.qml','terminateObs(actionCallback(policy,','terminateObs(actionCallback(null,','terminate-retirement'),
          ('Main.qml','root.activeAction === policy && policy.context.current()','true','confirmation-admission'),
          ('Main.qml','runtimeApi.togglePanel(screen, anchorItem)','pluginApi.togglePanel(screen, anchorItem)','panel-origin'),
          ('Main.qml','state.streamActive || state.virtualCamActive','state.streamActive || false','four-output-autoclose'),
          ('Main.qml','["pidof", "obs"]','["pidof", "other"]','physical-observer'),
          ('BarWidget.qml','root.pluginApi.settingsContext','root.pluginApi.mainInstance.pluginApi.settingsContext','bar-origin'),
          ('Panel.qml','root.pluginApi.settingsContext','root.pluginApi.mainInstance.pluginApi.settingsContext','panel-client'),
          ('ControlCenterWidget.qml','root.pluginApi.settingsContext','root.pluginApi.mainInstance.pluginApi.settingsContext','cc-client'),
          ('components/ObsButton.qml','root.screen, root, root.pluginApi','root.screen, root','cc-panel-origin'),
          ('Settings.qml','scopeKind === "instance"','scopeKind === "plugin"','shared-effect-copy'),
        ]
        for name,old,new,label in mutations:
            candidate=deepcopy(sources);tokens=re.findall(r'"(?:[^"\\]|\\.)*"|\x27(?:[^\x27\\]|\\.)*\x27|[^\s]',old);pattern=r'\s*'.join(re.escape(t) for t in tokens)
            candidate[name],count=re.subn(pattern,lambda _:new,candidate[name],count=1);assert count==1,label
            try:actions.syntax.compact(candidate[name])
            except ValueError as error:raise ValueError('invalid control '+label) from error
            try:check(candidate,manifest,words)
            except (ValueError,AssertionError):controls.append(label)
            else:raise AssertionError('OBS parsed control escaped '+label)
    result=dict(status='PASS',members=[member],controls=controls,generalJavaScriptProof=False)
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(result,indent=2)+'\n');print('OBS_GROUP: PASS '+str(len(controls))+' controls')

if __name__=='__main__':main()
