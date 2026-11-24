#!/usr/bin/env python3
"""Finite parsed device policy, nested typed schedule, callers and sole-owner map."""
import argparse
from collections import Counter
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import re

spec=importlib.util.spec_from_file_location('device_syntax',Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
spec=importlib.util.spec_from_file_location('device_anchors',Path(__file__).with_name('plugin-settings-action-group-check.py'))
anchors=importlib.util.module_from_spec(spec);spec.loader.exec_module(anchors)
FIELDS={'usb-drive-manager':['autoMount','fileBrowser','hideWhenEmpty','iconColor','showBadge','showNotifications','terminalCommand'],
 'noctalia-supergfxctl':['debug','rogcc','supergfxctl']}
NESTED={'rogcc':{'listenToNotifications'},'supergfxctl':{'patchPending','polling','pollingInterval'}}
POLICY={
 'usb-drive-manager/Main.qml':[
  'context = context || pluginApi?.settingsContext','const values = context.settingsView',
  'autoMount: values.autoMount ?? false','fileBrowser: values.fileBrowser || "yazi"',
  'terminalCommand: values.terminalCommand || "kitty"','showNotifications: values.showNotifications ?? true',
  'selectedContext || pluginApi?.settingsContext','selectedContext = context',
  'root.scheduleRefresh(root.capturePolicy(root.policyContext))','_debouncePolicy = policy',
  'const policy = root._debouncePolicy','policy?.context?.current() && policy.autoMount',
  'autoMountNewDevices(policy.context, policy)','mountDevice(dev.path, dev.label, policy.context, policy)',
  'mountProc.policy = policy','unmountProc.policy = policy','ejectProc.policy = policy',
  'const admitted = mountProc.policy','const admitted = unmountProc.policy','const admitted = ejectProc.policy',
  'root._retired || !admitted?.context?.current()','admitted.showNotifications','root.scheduleRefresh(admitted)',
  'const browser = policy.fileBrowser','const term = policy.terminalCommand','if (policy.showNotifications)',
  'readonly property bool requestCurrent: !root._retired && (policy?.context?.current() ?? false)',
  'onRequestCurrentChanged: { if (!requestCurrent) running = false; }',
  'if (!root._retired && exitCode !== 0)','_retired = true',
  'deviceWatcher.running = false','mountProc.running = false','unmountProc.running = false','ejectProc.running = false',
  'JSON.parse(String(deviceQueryOutput.text))','internal.parseDfOutput(String(dfOutput.text))',
  'String(mountError.text).trim()','String(unmountError.text).trim()','String(ejectError.text).trim()'],
 'usb-drive-manager/Panel.qml':[
  'mountDevice(path, label, root.pluginApi?.settingsContext)',
  'unmountDevice(path, label, root.pluginApi?.settingsContext)',
  'ejectDevice(path, parentPath, label, root.pluginApi?.settingsContext)',
  'openInFileBrowser(mountpoint, root.pluginApi?.settingsContext)',
  'unmountAll(root.pluginApi?.settingsContext)','ejectAll(root.pluginApi?.settingsContext)'],
 'usb-drive-manager/BarWidget.qml':[
  'pluginApi?.pluginSettings?.hideWhenEmpty','pluginApi?.pluginSettings?.showBadge','cfg.iconColor',
  'unmountAll(pluginApi?.settingsContext)','ejectAll(pluginApi?.settingsContext)'],
 'usb-drive-manager/ControlCenterWidget.qml':['unmountAll(pluginApi?.settingsContext)','ejectAll(pluginApi?.settingsContext)'],
 'usb-drive-manager/Settings.qml':['result.refreshState === "current"','activatePolicy(pluginApi.runtimeContext)'],
 'noctalia-supergfxctl/src/Main.qml':[
  '_settingsConsumers.has(context)','settingsContext: context','root._settingsConsumers.delete(context)',
  'requestRefresh: function () { root.refresh(context); }','const client = settingsConsumerFor(context)',
  'debug: client.debug, patchPending: client.patchPending','_pendingRefreshPolicy = policy',
  'const policy = _pendingRefreshPolicy','_refreshPolicy = policy','sgfx.refresh(policy)',
  'Qt.callLater(root._pumpRefresh)','if (!policy || _modeOperation) return false; return sgfx.setMode(mode, policy)',
  'root._modeOperation = {policy: policy, baseMode: mode, targetMode: modeEnum}',
  '_modeCurrent: !root._retired && (root._modeOperation?.policy.context.current() ?? false)',
  'sgfx.parseOutput(text.trim(), root._refreshPolicy)','if (root._refreshCurrent)',
  'const operation = root._modeOperation; const current = root._modeCurrent',
  'if (current && operation.policy.patchPending && exitCode === 0) { const action = sgfx.requiredAction(operation.targetMode, operation.baseMode); sgfx.manualRequest = {baseMode: operation.baseMode, targetMode: operation.targetMode, action: action}',
  'root._modeOperation = null; if (!current) return; const policy = operation.policy','root._refreshWithPolicy(policy)',
  'if (!manualRequest)','mode = manualRequest.baseMode','pendingMode = manualRequest.targetMode','pendingAction = manualRequest.action',
  'if (!policy.patchPending) { manualRequest = null; mode = newMode; pendingMode = newPendingMode; pendingAction = newPendingAction; } else','root.logFor(policy,',
  'if (policy?.debug) Logger.i','if (policy?.debug) Logger.w','if (policy?.debug) Logger.e',
  'on_RefreshCurrentChanged: { if (!_refreshCurrent) refreshProc.running = false; }',
  'on_ModeCurrentChanged: { if (!_modeCurrent) setModeProc.running = false; }',
  'if (!root._retired) root.log(notification)','_retired = true'],
 'noctalia-supergfxctl/src/GpuSettingsClient.qml':[
  'readonly property var cfg: current ? settingsContext.settingsView : ({})',
  'readonly property var gpu: cfg.supergfxctl ?? ({})','readonly property bool debug: cfg.debug ?? defaults.debug ?? false',
  'readonly property bool patchPending: gpu.patchPending ?? defaults.supergfxctl?.patchPending ?? true',
  'readonly property bool polling: gpu.polling ?? defaults.supergfxctl?.polling ?? false',
  'readonly property int pollingInterval: gpu.pollingInterval ?? defaults.supergfxctl?.pollingInterval ?? 3000',
  'interval: root.pollingInterval','running: root.current && root.available && !root.busy && root.polling',
  'pollingTimer.stop(); retire(root)','if (current) requestRefresh()'],
 'noctalia-supergfxctl/src/Panel.qml':[
  'settingsConsumerFor(pluginApi?.settingsContext)','setMode(gpuButton.mode, root.pluginApi?.settingsContext)',
  'root.settingsConsumer?.refresh()'],
 'noctalia-supergfxctl/src/Bar.qml':['settingsConsumerFor(pluginApi?.settingsContext)','root.settingsConsumer?.refresh()'],
 'noctalia-supergfxctl/src/ControlCenter.qml':['settingsConsumerFor(pluginApi?.settingsContext)'],
 'noctalia-supergfxctl/src/Settings.qml':[
  'settingsConsumerFor(root.pluginApi.runtimeContext)?.refresh()',
  'result.refreshState === "current"','enabled: false label: root.pluginApi.tr("settings.rogcc.listenToNotifications.label")']}
EFFECTS={'usb-drive-manager/Main.qml':dict(IpcHandler=1,Process=6),
 'noctalia-supergfxctl/src/Main.qml':dict(Process=2,NotificationServer=1)}


def check(sources,manifests,dictionaries):
    codes={};trees={}
    for name,text in sources.items():codes[name],trees[name]=syntax.compact(text)
    for member,fields in FIELDS.items():
        metadata=manifests[member]['metadata']['settingsSchema']['fields']
        if set(metadata)!=set(fields) or any(row.get('editorUsage')!='configuration' for row in metadata.values()):raise ValueError(member+': changed field ownership')
        prefix='src/' if member=='noctalia-supergfxctl' else ''
        entries=dict(main=prefix+'Main.qml',settings=prefix+'Settings.qml',panel=prefix+'Panel.qml',barWidget=prefix+('Bar.qml' if prefix else 'BarWidget.qml'),controlCenterWidget=prefix+('ControlCenter.qml' if prefix else 'ControlCenterWidget.qml'))
        if manifests[member]['entryPoints']!=entries:raise ValueError(member+': unreviewed entry')
        page=codes[member+'/'+entries['settings']]
        for anchor in ('visible: root.pluginApi?.scopeKind === "instance"','root.pluginApi?.tr("settings.shared-effect")'):
            anchors.require(page,anchor,member+': shared effect')
        for locale,data in dictionaries[member].items():
            if not data.get('settings',{}).get('shared-effect','').strip():raise ValueError(member+': missing shared effect '+locale)
    metadata=manifests['noctalia-supergfxctl']['metadata']['settingsSchema']['fields']
    for field,keys in NESTED.items():
        if set(metadata[field]['fields'])!=keys or metadata[field]['type']!='Record':raise ValueError('changed GPU atomic record '+field)
    if metadata['supergfxctl']['fields']['pollingInterval']['type']!='Real':raise ValueError('changed admitted interval domain')
    for name,items in POLICY.items():
        for anchor in items:anchors.require(codes[name],anchor,name+': '+anchor)
    for name,code in codes.items():
        raw=sources[name].encode();effects=Counter()
        for node in syntax.walk(trees[name].root_node):
            if node.type!='ui_object_definition':continue
            match=re.match(rb'(Process|Socket|Loader|IpcHandler|NotificationServer|MediaPlayer|Video)\s*\{',raw[node.start_byte:node.end_byte].lstrip())
            if match:effects[match[1].decode()]+=1
        if dict(effects)!=EFFECTS.get(name,{}):raise ValueError(name+': changed physical ownership '+repr(dict(effects)))
        if 'pluginSettings[' in code or re.search(r'pluginSettings\s*=',code):raise ValueError(name+': new native writer')
        if name.endswith('GpuSettingsClient.qml') and 'pluginApi' in code:raise ValueError('GPU client acquired its consumer')
    return [dict(plugin=member,configuration=fields,physicalOwners=1) for member,fields in FIELDS.items()]


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--plugins',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);parser.add_argument('--selftest',action='store_true');args=parser.parse_args()
    sources={};manifests={};dictionaries={}
    for member in FIELDS:
        manifests[member]=json.loads((args.plugins/member/'manifest.json').read_text())
        dictionaries[member]={path.name:json.loads(path.read_text()) for path in (args.plugins/member/'i18n').glob('*.json')}
        sources.update({str(path.relative_to(args.plugins)):path.read_text() for path in (args.plugins/member).rglob('*.qml')})
    rows=check(sources,manifests,dictionaries);controls=[]
    if args.selftest:
        mutations=[
         ('usb-drive-manager/Main.qml','const values = context.settingsView','const values = pluginApi.pluginSettings','shared-device-policy'),
         ('usb-drive-manager/Panel.qml','openInFileBrowser(mountpoint, root.pluginApi?.settingsContext)','openInFileBrowser(mountpoint)','omitted-browser'),
         ('usb-drive-manager/BarWidget.qml','unmountAll(pluginApi?.settingsContext)','unmountAll()','omitted-bar'),
         ('usb-drive-manager/ControlCenterWidget.qml','ejectAll(pluginApi?.settingsContext)','ejectAll()','omitted-cc'),
         ('usb-drive-manager/Main.qml','if (admitted.showNotifications)','if (root.showNotifications)','recaptured-completion-policy'),
         ('usb-drive-manager/Main.qml','autoMountNewDevices(policy.context, policy)','autoMountNewDevices()','lost-automatic-origin'),
         ('usb-drive-manager/Main.qml','const term = policy.terminalCommand','const term = root.terminalCommand','shared-terminal'),
         ('usb-drive-manager/Main.qml','root._retired || !admitted?.context?.current()','root._retired','retired-device-completion'),
         ('usb-drive-manager/Main.qml','if (!requestCurrent) running = false','if (false) running = false','uncancelled-device-command'),
         ('usb-drive-manager/Main.qml','deviceQueryOutput.text','stdout.text','erased-concrete-stream-type'),
         ('noctalia-supergfxctl/src/Main.qml','sgfx.parseOutput(text.trim(), root._refreshPolicy)','sgfx.parseOutput(text.trim(), root.capturePolicy())','recaptured-parser'),
         ('noctalia-supergfxctl/src/Main.qml','if (!policy.patchPending)','if (!root.pluginSettings.supergfxctl.patchPending)','shared-parser-policy'),
         ('noctalia-supergfxctl/src/Main.qml','root._refreshWithPolicy(policy)','root.refresh()','shared-mode-followup'),
         ('noctalia-supergfxctl/src/Main.qml','_pendingRefreshPolicy = policy','_pendingRefreshPolicy = null','lost-pending-policy'),
         ('noctalia-supergfxctl/src/Main.qml','if (!manualRequest)','if (pendingMode === Main.SGFXMode.None)','observed-mode-as-manual-request'),
         ('noctalia-supergfxctl/src/Main.qml','if (!current) return','if (root._retired) return','retired-mode-completion'),
         ('noctalia-supergfxctl/src/Main.qml','current && operation.policy.patchPending && exitCode === 0','current && operation.policy.patchPending','failed-mode-published'),
         ('noctalia-supergfxctl/src/Main.qml','baseMode: mode, targetMode: modeEnum','baseMode: pendingMode, targetMode: modeEnum','observed-mode-as-operation-base'),
         ('noctalia-supergfxctl/src/GpuSettingsClient.qml','readonly property int pollingInterval','readonly property real pollingInterval','lost-typed-interval'),
         ('noctalia-supergfxctl/src/GpuSettingsClient.qml','root.current && root.available','root.available','retired-polling'),
         ('noctalia-supergfxctl/src/Panel.qml','setMode(gpuButton.mode, root.pluginApi?.settingsContext)','setMode(gpuButton.mode)','omitted-mode-origin'),
         ('noctalia-supergfxctl/src/Bar.qml','root.settingsConsumer?.refresh()','root.pluginCore?.refresh()','shared-bar-request'),
         ('noctalia-supergfxctl/src/Settings.qml','enabled: false','enabled: true','enabled-unimplemented-setting'),
         ('noctalia-supergfxctl/src/GpuSettingsClient.qml','id: root','id: root\n NotificationServer {}','duplicate-notification-owner')]
        for name,old,new,label in mutations:
            if old not in sources[name]:raise RuntimeError('stale device control '+label)
            changed=dict(sources);changed[name]=changed[name].replace(old,new)
            try:check(changed,manifests,dictionaries)
            except ValueError as error:controls.append(dict(control=label,rejectedAt=str(error)))
            else:raise RuntimeError('device control escaped '+label)
        altered=deepcopy(manifests);altered['noctalia-supergfxctl']['metadata']['settingsSchema']['fields']['rogcc']['editorUsage']='operational'
        try:check(sources,altered,dictionaries)
        except ValueError as error:controls.append(dict(control='reclassified-disabled-configuration',rejectedAt=str(error)))
        else:raise RuntimeError('reclassified retained configuration escaped')
    args.report.write_text(json.dumps(dict(status='PASS',kind='finite-parsed-contract',members=rows,controls=controls,disabledUnimplemented=['noctalia-supergfxctl.rogcc.listenToNotifications'],runtimeAcceptance=False,completeGroupAcceptance=False),indent=2)+'\n')
    print('DEVICE_GROUP_CHECK: PASS (%d members; %d controls)'%(len(rows),len(controls)))


if __name__=='__main__':main()
