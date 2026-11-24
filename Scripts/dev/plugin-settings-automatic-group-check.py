#!/usr/bin/env python3
"""Finite parsed automatic-session/keyboard policy, caller and sole-owner contract."""
import argparse
from collections import Counter
import importlib.util
import json
from pathlib import Path

spec=importlib.util.spec_from_file_location('automatic_syntax',Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
spec=importlib.util.spec_from_file_location('automatic_anchors',Path(__file__).with_name('plugin-settings-action-group-check.py'))
anchors=importlib.util.module_from_spec(spec);spec.loader.exec_module(anchors)
FIELDS={
 '2-in-1-tools':['autoRotateInTabletMode','autoRotateOutsideTabletMode','autoTabletBarDensity','buttonBehavior','exclusiveDockInTabletMode','flipVerticalSensorOrientation','iconName','showSuccessToast','showTransformInTooltip','syncHyprTouchTransform','tabletBarDensity','tabletModeStateFile'],
 'osk-toggle':['backend','disableHoverIcon','hideWhenUnavailable','wvkbdBin']}
PROTECTED={'2-in-1-tools':['lastNonTabletBarDensity','lastNonTabletDockEnabled','lastNonTabletDockType'],'osk-toggle':[]}
READS={
 '2-in-1-tools/Main.qml':['cfg.'+key for key in FIELDS['2-in-1-tools'] if key not in ('iconName','showTransformInTooltip')]+['sharedCfg.'+key for key in PROTECTED['2-in-1-tools']],
 '2-in-1-tools/BarWidget.qml':['cfg.iconName','cfg.showTransformInTooltip'],
 'osk-toggle/OskSettingsClient.qml':['cfg.backend','cfg.wvkbdBin'],
 'osk-toggle/BarWidget.qml':['pluginSettings?.hideWhenUnavailable','pluginSettings?.disableHoverIcon']}
POLICY={
 '2-in-1-tools/Main.qml':[
 'readonly property var cfg: policyCurrent ? policyContext.settingsView : ({})',
 'const values = context.settingsView','if (!context?.current() || _destroying) return null',
 'root._queryPolicy = policy','root._buildQueryCommand(policy)','policy.backend === "niri"',
 'root._beginAutoRotateSession(root._internalDisplayFromOutputs(outputs), policy)',
 'root._applyPolicy = policy','root._buildApplyCommand(outputName, root._applyTarget, policy)',
 'root._requestHyprTouchTransformSync(outputName, root._applyTarget, policy)',
 'root._hyprTouchQueuedPolicy = policy','root._hyprTouchActivePolicy = root._hyprTouchQueuedPolicy',
 '!root._hyprTouchActivePolicy?.context?.current()',
 'policy.flipVerticalSensorOrientation ? "270" : "90"',
 'root._autoRotateSessionPolicy = policy','root._autoRotateRestorePolicy = root._autoRotateSessionPolicy',
 'root._autoRotateSessionPolicy?.autoRotateOutsideTabletMode',
 'root._autoRotateRestorePolicy = policy',
 'root._tabletModePolicy = root.capturePolicy(root.policyContext)',
 'policy.stateFile !== root.tabletModeStateFile','root._restartStateWatcher = true',
 'niriStateWatchProc.running = false','root._destroying = true',
 'if (!pluginApi || !root.policyCurrent || root._destroying) return',
 'pluginApi.pluginSettings[key] = value','pluginApi.saveSettings()'],
 'osk-toggle/Main.qml':[
 'readonly property var policyContext: selectedContext || pluginApi?.settingsContext',
 'readonly property var cfg: policyCurrent ? policyContext.settingsView : ({})',
 'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)',
 'settingsContext: context','root._settingsConsumers.delete(context)',
 'requestToggle: function () { root.toggleKeyboard(context); }',
 'requestRecheck: function () { root.recheckState(context); }',
 'keyboardActive: Qt.binding(function () { return root.keyboardActive; })',
 'activePolicy: Qt.binding(function () { return root._loadedRequest === root._request && root._request?.context === context; })',
 'physicalAvailable: Qt.binding(function () { return root.available; })',
 '_request = {context: context, backend: backend, binary: binary}',
 'request === root._request && request?.context?.current()',
 '_backend.retire()','if (!_backend.quiescent) return',
 'backendLoader.setSource(source, {settingsContext: request.context, wvkbdBin: request.binary})',
 '_pendingToggle === _request && _request?.context?.current() && _loadedRequest === _request',
 'autoDetect.running = false','_backend?.retire()',
 'passiveBus.running = false', 'passiveGsettings.running = false',
 'busOk: Qt.binding(function () { return root._squeekboardBusOk; })',
 'gsettingsOk: Qt.binding(function () { return root._squeekboardGsettingsOk; })'],
 'osk-toggle/OskSettingsClient.qml':[
 'readonly property bool current: settingsContext.current()',
 'readonly property var cfg: current ? settingsContext.settingsView : ({})',
 'activePolicy ? physicalAvailable',
 'binaryCheck.command = ["which", binary.trim().split(/\\s+/)[0]]',
 'root._binaryTarget !== root.binary','if (!root.current) return',
 'if (current && available) requestToggle()','if (current) requestRecheck()',
 'binaryCheck.running = false','retire(root)'],
 'osk-toggle/WvkbdBackend.qml':[
 'property string wvkbdBin: "wvkbd-mobintl"','property var settingsContext: null',
 'readonly property bool current: !root._retired && (settingsContext?.current() ?? false)',
 'readonly property bool quiescent: !availabilityChecker.running && !preemptChecker.running && !preemptKill.running && !wvkbd.running',
 'command: [...wvkbdBinParts, "--hidden"]','if (!root.current) return',
 'if (!root._constructed || !root.current) return',
 'root._pendingShow = root._pendingShow || exitCode === 0',
 '!wvkbd.running && !preemptChecker.running && !preemptKill.running',
 'root._retired = true','showTimer.stop()','availabilityChecker.running = false',
 'preemptChecker.running = false','preemptKill.running = false','wvkbd.running = false',
  'if (root._starting)','root._pendingShow = !root._pendingShow','interval: 300'],
 'osk-toggle/SqueekboardBackend.qml':[
 'property var settingsContext: null','root._retired = true',
 'readonly property bool quiescent: !stateChecker.running && !squeekboardChecker.running && !squeekboardMonitor.running && !stateMonitor.running && !toggleProcess.running',
 'if (root.current) squeekboardMonitor.running = true','if (!root.current) return',
 'stateMonitor.running = false','squeekboardMonitor.running = false','toggleProcess.running = false'],
 'osk-toggle/BarWidget.qml':[
 'mainInstance?.settingsConsumerFor(pluginApi?.settingsContext)',
 'property bool available: settingsConsumer?.available ?? false',
 'if (available) settingsConsumer?.toggleKeyboard()'],
 'osk-toggle/Settings.qml':['recheckState(pluginApi.runtimeContext)']}
EFFECTS={'2-in-1-tools/Main.qml':dict(Process=11),'2-in-1-tools/Settings.qml':dict(Process=1),
 'osk-toggle/Main.qml':dict(Process=3,Loader=1),'osk-toggle/OskSettingsClient.qml':dict(Process=1),
 'osk-toggle/WvkbdBackend.qml':dict(Process=4),'osk-toggle/SqueekboardBackend.qml':dict(Process=5)}


def check(sources,manifests,dictionaries):
    codes={};trees={}
    for name,text in sources.items(): codes[name],trees[name]=syntax.compact(text)
    rows=[]
    for member,fields in FIELDS.items():
        metadata=manifests[member]['metadata']['settingsSchema']['fields']
        if set(metadata)!=set(fields+PROTECTED[member]): raise ValueError(member+': reviewed fields changed')
        for key in metadata:
            if metadata[key].get('editorUsage')!=('configuration' if key in fields else 'operational'): raise ValueError(member+': changed field ownership '+key)
        entries=dict(main='Main.qml',barWidget='BarWidget.qml',settings='Settings.qml')
        if member=='2-in-1-tools': entries['controlCenterWidget']='ControlCenterWidget.qml'
        if manifests[member]['entryPoints']!=entries: raise ValueError(member+': unreviewed entry')
        for anchor in ('visible: root.pluginApi?.scopeKind === "instance"','root.pluginApi?.tr("settings.shared-effect")','result.refreshState === "current"','activatePolicy(pluginApi.runtimeContext)'):
            anchors.require(codes[member+'/Settings.qml'],anchor,member+': accepted policy/shared effect')
        for locale,data in dictionaries[member].items():
            if not data.get('settings',{}).get('shared-effect','').strip(): raise ValueError(member+': missing shared effect '+locale)
        rows.append(dict(plugin=member,configuration=fields,protected=PROTECTED[member],physicalOwners=1))
    for mapping in (READS,POLICY):
        for name,items in mapping.items():
            for anchor in items: anchors.require(codes[name],anchor,name+': '+anchor)
    wanted={'BarWidget.qml':dict(buttonUsesManualRotate=4,buttonIconName=2,buttonVisible=1,buttonEnabled=1,buttonTooltip=1,activatePrimaryButton=2,cycleTransform=1,refreshTransform=3),
            'ControlCenterWidget.qml':dict(buttonIconName=1,buttonVisible=1,buttonEnabled=1,buttonTooltip=1,activatePrimaryButton=1,refreshTransform=2)}
    for name,counts in wanted.items():
        path = '2-in-1-tools/' + name
        calls = [(method, args) for receiver, method, args in syntax.member_calls(sources[path], trees[path], counts) if receiver == 'backend']
        if dict(Counter(method for method, _ in calls)) != counts or any(args.count('pluginApi?.settingsContext') != 1 for _, args in calls): raise ValueError(name+': omitted or unreviewed origin')
    for name,code in codes.items():
        effects = Counter(kind for kind in syntax.object_types(sources[name], trees[name])
                          if kind in {'Process', 'Socket', 'Loader', 'IpcHandler', 'MediaPlayer', 'Video'})
        effects.update('execDetached' for _ in syntax.member_calls(sources[name], trees[name], {'execDetached'}))
        if dict(effects)!=EFFECTS.get(name,{}): raise ValueError(name+': unreviewed physical owner '+repr(dict(effects)))
        if name.startswith('osk-toggle/') and 'pluginSettings[' in code: raise ValueError(name+': new native writer')
        if name.endswith('Backend.qml') and 'pluginApi' in code: raise ValueError(name+': backend acquired implicit shared API')
    return rows


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--plugins',type=Path,required=True); parser.add_argument('--report',type=Path,required=True); parser.add_argument('--selftest',action='store_true'); args=parser.parse_args()
    sources={};manifests={};dictionaries={}
    for member in FIELDS:
        manifests[member]=json.loads((args.plugins/member/'manifest.json').read_text())
        dictionaries[member]={p.name:json.loads(p.read_text()) for p in (args.plugins/member/'i18n').glob('*.json')}
        sources.update(syntax.qml_sources(args.plugins, member))
    rows=check(sources,manifests,dictionaries);controls=[]
    if args.selftest:
        mutations=[
         ('2-in-1-tools/Main.qml','policyCurrent ? policyContext.settingsView : ({})','pluginApi.pluginSettings','shared-policy'),
         ('2-in-1-tools/Main.qml','sharedCfg.lastNonTabletBarDensity','cfg.lastNonTabletBarDensity','selected-restore-state'),
         ('2-in-1-tools/BarWidget.qml','activatePrimaryButton(outputName, pluginApi?.settingsContext)','activatePrimaryButton(outputName)','omitted-bar'),
         ('2-in-1-tools/ControlCenterWidget.qml','activatePrimaryButton(outputName, pluginApi?.settingsContext)','activatePrimaryButton(outputName)','omitted-cc'),
         ('2-in-1-tools/Main.qml','policy.flipVerticalSensorOrientation','root.flipVerticalSensorOrientation','recaptured-sensor-policy'),
         ('2-in-1-tools/Main.qml','root._autoRotateSessionPolicy?.autoRotateOutsideTabletMode','root.autoRotateOutsideTabletMode','mutable-exit-restore'),
         ('2-in-1-tools/Main.qml','root._queryPolicy = policy','root._queryPolicy = null','lost-query-policy'),
         ('2-in-1-tools/Main.qml','root._applyPolicy = policy','root._applyPolicy = null','lost-apply-policy'),
         ('2-in-1-tools/Main.qml','root._hyprTouchQueuedPolicy = policy','root._hyprTouchQueuedPolicy = null','lost-touch-policy'),
         ('2-in-1-tools/Main.qml','policy.stateFile !== root.tabletModeStateFile','false','old-state-file-result'),
         ('osk-toggle/Main.qml','_backend.retire()','_backend.recheckState()','unretired-backend'),
         ('osk-toggle/Main.qml','if (!_backend.quiescent)','if (false)','overlapping-backend'),
         ('osk-toggle/Main.qml','settingsContext: request.context','settingsContext: pluginApi.settingsContext','shared-backend'),
         ('osk-toggle/BarWidget.qml','settingsConsumer?.available','mainInstance?.available','shared-availability'),
         ('osk-toggle/OskSettingsClient.qml','current ? settingsContext.settingsView : ({})','({})','dead-selected-availability'),
         ('osk-toggle/WvkbdBackend.qml','showTimer.stop()','showTimer.restart()','retired-delayed-show'),
          ('osk-toggle/WvkbdBackend.qml','root._pendingShow || exitCode === 0','exitCode === 0','lost-admitted-show'),
          ('osk-toggle/WvkbdBackend.qml','interval: 300','interval: 30','changed-startup-show-boundary'),
         ('osk-toggle/SqueekboardBackend.qml','if (root.current) squeekboardMonitor.running = true','squeekboardMonitor.running = true','retired-monitor-restart'),
         ('osk-toggle/Main.qml','_pendingToggle === _request && _request?.context?.current()','_pendingToggle !== null','retired-toggle'),
         ('osk-toggle/Settings.qml','recheckState(pluginApi.runtimeContext)','recheckState()','shared-settings-recheck'),
         ('osk-toggle/Main.qml','property var pluginApi: null','property var pluginApi: null\n Loader {}','duplicate-backend-owner'),
         ('osk-toggle/Main.qml','passiveBus.running = false','passiveBus.running = false; Quickshell.execDetached(["true"])','detached-process-owner')]
        for name,old,new,label in mutations:
            if old not in sources[name]: raise RuntimeError('stale automatic control '+label)
            changed=dict(sources);changed[name]=changed[name].replace(old,new)
            try: check(changed,manifests,dictionaries)
            except ValueError as error: controls.append(dict(control=label,rejectedAt=str(error)))
            else: raise RuntimeError('automatic control escaped '+label)
    args.report.write_text(json.dumps(dict(status='PASS',kind='finite-parsed-contract',members=rows,controls=controls,runtimeAcceptance=False,completeGroupAcceptance=False),indent=2)+'\n')
    print('AUTOMATIC_GROUP_CHECK: PASS (%d members; %d controls)'%(len(rows),len(controls)))


if __name__=='__main__': main()
