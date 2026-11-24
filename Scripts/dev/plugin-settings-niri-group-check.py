#!/usr/bin/env python3
"""Finite parsed Niri automation field/caller/owner contract, not general JS proof."""
import argparse
import ast
import importlib.util
import json
from pathlib import Path
import re
spec=importlib.util.spec_from_file_location('niri_syntax',Path(__file__).with_name('plugin-settings-action-group-check.py'))
syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
FIELDS={
 'niri-auto-tile':set('debounceMs enabled language maxEventsPerSecond maxVisible onlyAtMax perWorkspace workspaceMaxVisible'.split()),
 'niri-screensaver':set('batteryMinPercent clockDuration clockFont clockFormat cursorHide cursorWarp dismissOnKey enabled excludeEffects fadeInEffect fadeOutEffect frameRate idleSeconds includeEffects killCommand launcherCommand logoDir logoPath multiMonitorMode nowPlayingDuration randomLogo showClock showNowPlaying'.split()),
}
ANCHORS={
 'niri-auto-tile/Main.qml':[
  'selectedContext || pluginApi?.settingsContext','!retired && (policyContext?.current() ?? false)','policyCurrent ? policyContext.settingsView : ({})',
  'readonly property int maxVisible: cfg.maxVisible ?? 4','readonly property int debounceMs: cfg.debounceMs ?? 300','readonly property int maxEventsPerSecond: cfg.maxEventsPerSecond ?? 20',
  'cfg.enabled ?? true','cfg.onlyAtMax ?? true','cfg.perWorkspace ?? false','cfg.workspaceMaxVisible ?? ({})',
  'context = context || pluginApi?.settingsContext','if (retired || !context?.current()) return false','selectedContext = context',
  'context = context || selectedContext || pluginApi?.settingsContext','admittedMaxVisible = values.maxVisible ?? 4','admittedDebounceMs = values.debounceMs ?? 300','admittedMaxEvents = values.maxEventsPerSecond ?? 20',
  'policy.generation === generation && policy.context === policyContext && policy.context.current()',
  'const policy = pendingLaunch || capturePolicy()','pendingLaunch = capturePolicy()','activePolicy = policy',
  '"--max-visible", String(policy.maxVisible)','String(policy.debounceMs / 1000.0)','String(policy.maxEventsPerSecond)',
  'policy.onlyAtMax ? "--only-at-max" : "--no-only-at-max"','policy.workspaceConfig',
  'generation++','queuedConfig = null','configWriter.running = false','daemonProcess.signal(15)',
  'queuedConfig = capturePolicy()','if (configWriter.running) return','if (!current(policy) || !daemonProcess.running) return',
  'policy.config, configFilePath','code === 0 && root.current(policy) && root.daemonProcess.running','root.daemonProcess.signal(10)',
  'runtimeApi.pluginSettings[key] = value','runtimeApi.saveSettings()',
  'saveField("enabled", value, runtimeApi)','saveField("maxVisible", count, runtimeApi)','saveField("workspaceMaxVisible", updated, runtimeApi)',
  'saveField("perWorkspace", value, runtimeApi)','saveField("onlyAtMax", value, runtimeApi)',
  'runtimeApi.settingsContext.settingsView.workspaceMaxVisible','updated[String(wsId)] = count',
  'context = context || policyContext','const values = context.settingsView',
  'if (root.current(previous) && root.automationEnabled && exitCode !== 0 && exitStatus === 0) restartTimer.restart()',
  'onTriggered: root.reconcileDaemon()','retired = true; componentReady = false; stopDaemon()',
 ],
 'niri-auto-tile/BarWidget.qml':['pluginApi?.pluginSettings?.enabled','pluginApi?.pluginSettings?.maxVisible','mainInstance.setMaxVisible(4, pluginApi)','mainInstance.setEnabled(!isEnabled, pluginApi)'],
 'niri-auto-tile/Panel.qml':['pluginApi?.pluginSettings?.enabled','pluginApi?.pluginSettings?.perWorkspace','pluginApi?.pluginSettings?.maxVisible','getMaxVisibleForWorkspace(currentWorkspaceId, pluginApi.settingsContext)','setWorkspaceMaxVisible(currentWorkspaceId, count, pluginApi)','setMaxVisible(count, pluginApi)','setEnabled(checked, root.pluginApi)'],
 'niri-screensaver/Main.qml':[
  'selectedContext || pluginApi?.settingsContext','!retired && (policyContext?.current() ?? false)','policyCurrent ? policyContext.settingsView : ({})',
  'JSON.stringify(cfg)','if (componentReady) syncDebounce.restart()','interval: 250',
  'context = context || pluginApi?.settingsContext','if (retired || !context?.current()) return false','selectedContext = context',
  'if (!componentReady || !policyCurrent) return','const policy = {context: policyContext, generation: generation, values: cfg}',
  '_writeShellConfig(policy)','_syncIdleEntry(policy.values)','_syncHooks(policy.values)',
  'context.settingsView.launcherCommand','context.settingsView.killCommand','if (retired || !context?.current()) return []',
  'queuedConfig = policy','if (writeConfigProcess.running) return','policy.generation !== generation || policy.context !== policyContext || !policy.context.current()',
  '_renderShellConfig(policy.values)','writeConfigProcess.policy = policy','root.configDir, root.configFile',
  'timeout: parseInt(s.idleSeconds) || 300','command: s.launcherCommand || root.defaultLauncherCommand','resumeCommand: s.killCommand || root.defaultKillCommand',
  'const current = hooks[slot] || ""','if ((owned && current === owned) || (desired && !current)) { hooks[slot] = desired; return desired }',
  'ownedLockHook = _syncHookSlot("screenLock", ownedLockHook, command)','ownedUnlockHook = _syncHookSlot("screenUnlock", ownedUnlockHook, command)',
  '_syncHookSlots(s.enabled ? (s.killCommand || root.defaultKillCommand) : "")','_syncHookSlots("")',
  'writeConfigProcess.running = false','_removeRegistration()','retired = true','queuedConfig = null',
 ],
 'niri-screensaver/BarWidget.qml':[
  '_launcherArgv(root.pluginApi.settingsContext)','_killArgv(root.pluginApi.settingsContext)',
  'const context = root.pluginApi?.settingsContext','!context?.current() || statusProbe.running || !root.mainInstance',
  'statusProbe.policy = {context: context, launch: root.mainInstance._launcherArgv(context), kill: root.mainInstance._killArgv(context)}',
  'const admitted = policy','if (!admitted?.context?.current()) return','killProc.command = admitted.kill','launchProc.command = admitted.launch',
  'root.pluginApi.pluginSettings.enabled = false','root.pluginApi.pluginSettings.enabled = true','root.pluginApi.pluginSettings.enabled = !en',
  'root.mainInstance?.applySettings(root.pluginApi.settingsContext)',
 ],
 'niri-screensaver/Settings.qml':['_launcherArgv(root.pluginApi.runtimeContext)','_killArgv(root.pluginApi.runtimeContext)'],
}


def check(sources,manifests,dictionaries):
    codes={path:syntax.syntax.compact(text)[0] for path,text in sources.items() if path.endswith('.qml')};rows=[]
    for name,fields in FIELDS.items():
        if name not in manifests:continue
        descriptor=manifests[name]
        if set(descriptor['metadata']['settingsSchema']['fields'])!=fields:raise ValueError(name+': unreviewed field')
        entries=dict(main='Main.qml',barWidget='BarWidget.qml',settings='Settings.qml')
        if name=='niri-auto-tile':entries['panel']='Panel.qml'
        if descriptor['entryPoints']!=entries:raise ValueError(name+': unreviewed entry')
        if {path for path in codes if path.startswith(name+'/')}!={name+'/'+value for value in entries.values()}:raise ValueError(name+': unreviewed loaded QML')
        page=codes[name+'/Settings.qml']
        for anchor in ('visible: root.pluginApi?.scopeKind === "instance"','root.pluginApi?.tr("settings.shared-effect")','result.refreshState !== "current"','applySettings(root.pluginApi.runtimeContext)'):syntax.require(page,anchor,name+': '+anchor)
        for locale,dictionary in dictionaries[name].items():
            if not dictionary.get('settings',{}).get('shared-effect','').strip():raise ValueError(name+': explanation '+locale)
        for path,code in codes.items():
            if not path.startswith(name+'/'):continue
            raw=sources[path].encode();tree=syntax.syntax.compact(sources[path])[1]
            count=sum(node.type=='ui_object_definition' and bool(re.match(rb'Process\s*\{',raw[node.start_byte:node.end_byte])) for node in syntax.syntax.walk(tree.root_node))
            expected=({'Main.qml':2,'BarWidget.qml':0,'Panel.qml':1,'Settings.qml':0} if name=='niri-auto-tile' else {'Main.qml':4,'BarWidget.qml':4,'Settings.qml':4})[path.split('/')[-1]]
            if count!=expected or 'execDetached(' in code:raise ValueError(name+': unreviewed process owner '+path)
        main=codes[name+'/Main.qml']
        if name=='niri-auto-tile':
            if 'pluginSettings' in main.replace('runtimeApi.pluginSettings[key]=value',''):raise ValueError(name+': shared reader/writer')
            actual=set(re.findall(r'saveField\("([^"]+)"',main))
            if actual!={'enabled','maxVisible','workspaceMaxVisible','perWorkspace','onlyAtMax'}:raise ValueError(name+': finite native writer keys')
        else:
            for key in fields:
                if not re.search(r'(?:s|cfg)\.'+key+r'\b|context\.settingsView\.'+key+r'\b',main):raise ValueError(name+': missing field consumer '+key)
            if 'pluginSettings' in main.replace('root.pluginApi.pluginSettings.enabled',''):raise ValueError(name+': shared reader')
        rows.append(dict(plugin=name,fields=sorted(fields),entries=entries,resourceOwner='Main',legacyUnusedField='language' if name=='niri-auto-tile' else None))
    for path,anchors in ANCHORS.items():
        if path not in sources:continue
        for anchor in anchors:syntax.require(codes[path],anchor,path+': '+anchor)
    if 'niri-auto-tile' not in manifests:return rows
    script=ast.parse(sources['niri-auto-tile/auto-tile.py']);functions={node.name:node for node in script.body if isinstance(node,ast.FunctionDef)}
    for name in ('niri_cmd','niri_action','run_event_loop'):
        calls=[node for node in ast.walk(functions[name]) if isinstance(node,ast.Call) and isinstance(node.func,ast.Attribute) and isinstance(node.func.value,ast.Name) and node.func.value.id=='subprocess' and node.func.attr in ('run','Popen')]
        if len(calls)!=1 or not isinstance(calls[0].args[0],ast.Call) or not isinstance(calls[0].args[0].func,ast.Name) or calls[0].args[0].func.id!='_owned_niri_command':raise ValueError('unbound Python child '+name)
    child=ast.get_source_segment(sources['niri-auto-tile/auto-tile.py'],functions['_exec_owned_niri'])
    for anchor in ('prctl(1, signal.SIGKILL, 0, 0, 0) != 0','parent_pid <= 1 or os.getppid() != parent_pid','os.execvp("niri", ["niri", "msg", *args])'):
        if anchor not in child:raise ValueError('parent-death exec/race boundary '+anchor)
    if child.index('os.getppid()')<child.index('prctl(1,'):raise ValueError('race check precedes binding')
    text=sources['niri-auto-tile/auto-tile.py']
    if 'action=argparse.BooleanOptionalAction, default=None' not in text or 'ONLY_AT_MAX = args.only_at_max' not in text:raise ValueError('explicit false CLI policy')
    if 'if generation is not None and generation != _config_generation:' not in text or '_config_generation += 1' not in text:raise ValueError('retired Python redistribution generation')
    for name in ('_redistribute_workspace','redistribute'):
        calls=[node for node in ast.walk(functions[name]) if isinstance(node,ast.Call) and isinstance(node.func,ast.Name) and node.func.id=='niri_action']
        if not calls or any(not any(key.arg=='generation' and isinstance(key.value,ast.Name) and key.value.id=='generation' for key in node.keywords) for node in calls):raise ValueError('unfenced redistribution effect '+name)
    return rows


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--plugins',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);parser.add_argument('--selftest',action='store_true');parser.add_argument('--plugin',choices=tuple(FIELDS),action='append',help='Qualify only named independently delivered members; default: both');args=parser.parse_args()
    selected = tuple(name for name in FIELDS if not args.plugin or name in args.plugin)
    sources={name+'/'+path.name:path.read_text() for name in selected for path in (args.plugins/name).glob('*.qml')}
    if 'niri-auto-tile' in selected:
        sources['niri-auto-tile/auto-tile.py']=(args.plugins/'niri-auto-tile/auto-tile.py').read_text()
    manifests={name:json.loads((args.plugins/name/'manifest.json').read_text()) for name in selected};dictionaries={name:{path.name:json.loads(path.read_text()) for path in (args.plugins/name/'i18n').glob('*.json')} for name in selected}
    rows=check(sources,manifests,dictionaries);controls=[]
    if args.selftest:
        mutations=[
         ('niri-auto-tile/Settings.qml','applySettings(root.pluginApi.runtimeContext)','applySettings()','omitted-tile-page-origin'),
         ('niri-screensaver/Settings.qml','applySettings(root.pluginApi.runtimeContext)','applySettings()','omitted-screensaver-page-origin'),
         ('niri-auto-tile/Main.qml','policyContext.settingsView','pluginApi.settingsView','shared-tile-reader'),
         ('niri-auto-tile/Main.qml','property int maxVisible','property real maxVisible','tile-int-domain'),
         ('niri-auto-tile/Main.qml','String(policy.debounceMs / 1000.0)','String(policy.debounceMs)','tile-debounce-units'),
         ('niri-auto-tile/Main.qml','const policy = pendingLaunch || capturePolicy()','const policy = capturePolicy()','mutable-pending-launch'),
         ('niri-auto-tile/Main.qml','runtimeApi.saveSettings()','pluginApi.saveSettings()','shared-tile-writer'),
         ('niri-auto-tile/Main.qml','root.current(policy) && root.daemonProcess.running','root.daemonProcess.running','retired-config-signal'),
         ('niri-auto-tile/Panel.qml','setMaxVisible(count, pluginApi)','setMaxVisible(count)','omitted-panel-writer'),
         ('niri-auto-tile/BarWidget.qml','pluginSettings?.maxVisible','mainInstance?.maxVisible','shared-bar-count'),
         ('niri-auto-tile/auto-tile.py','_owned_niri_command("action", *args)','["niri", "msg", "action", *args]','unbound-action-child'),
         ('niri-auto-tile/auto-tile.py','os.getppid() != parent_pid','False','missing-parent-race-check'),
         ('niri-auto-tile/auto-tile.py','prctl(1, signal.SIGKILL, 0, 0, 0) != 0','False','missing-parent-binding'),
         ('niri-auto-tile/auto-tile.py','action=argparse.BooleanOptionalAction, default=None','action="store_true"','false-cli-dead-setting'),
         ('niri-auto-tile/auto-tile.py','if generation is not None and generation != _config_generation:','if False:','retired-python-effect'),
         ('niri-auto-tile/Main.qml','admittedMaxVisible = values.maxVisible ?? 4','admittedMaxVisible = maxVisible','stale-admission-binding'),
         ('niri-screensaver/Main.qml','policyContext.settingsView','pluginApi.settingsView','shared-screensaver-reader'),
         ('niri-screensaver/Main.qml','_renderShellConfig(policy.values)','_renderShellConfig(cfg)','mutable-config-writer'),
         ('niri-screensaver/Main.qml','policy.context !== policyContext || !policy.context.current()','policy.context !== policyContext','retired-shell-config'),
         ('niri-screensaver/Main.qml','if ((owned && current === owned) || (desired && !current))','if (true)','manual-hook-clobber'),
         ('niri-screensaver/Main.qml','_syncHookSlot("screenUnlock", ownedUnlockHook, command)','_syncHookSlot("screenUnlock", ownedLockHook, command)','borrowed-hook-slot-owner'),
         ('niri-screensaver/BarWidget.qml','if (!admitted?.context?.current()) return','if (!admitted) return','retired-probe-continuation'),
         ('niri-screensaver/BarWidget.qml','launchProc.command = admitted.launch','launchProc.command = root.mainInstance._launcherArgv()','mutable-probe-command'),
         ('niri-screensaver/Settings.qml','_launcherArgv(root.pluginApi.runtimeContext)','_launcherArgv()','shared-settings-action'),
        ]
        for path,old,new,label in mutations:
            if path not in sources:continue
            assert sources[path].count(old)==1,label
            changed=dict(sources);changed[path]=changed[path].replace(old,new)
            try:check(changed,manifests,dictionaries)
            except ValueError as error:controls.append(dict(control=label,rejectedAt=str(error)))
            else:raise RuntimeError('Niri control escaped '+label)
        for name in FIELDS:
            if name not in manifests:continue
            changed=json.loads(json.dumps(manifests));changed[name]['entryPoints']['main']='Unknown.qml'
            try:check(sources,changed,dictionaries)
            except ValueError as error:controls.append(dict(control='unreviewed-entry',plugin=name,rejectedAt=str(error)))
            else:raise RuntimeError('unreviewed Niri entry escaped')
    args.report.write_text(json.dumps(dict(status='PASS',members=rows,controls=controls,runtimeAcceptance=False,completeGroupAcceptance=False),indent=2)+'\n');print('PLUGIN_SETTINGS_NIRI_GROUP_CHECK: PASS (%d fields, %d controls)'%(sum(len(row['fields']) for row in rows),len(controls)))


if __name__=='__main__':main()
