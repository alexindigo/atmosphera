#!/usr/bin/env python3
"""Finite parsed wallpaper field/origin/owner contract, not runtime acceptance."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec=importlib.util.spec_from_file_location('wallpaper_syntax',Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
spec=importlib.util.spec_from_file_location('wallpaper_anchors',Path(__file__).with_name('plugin-settings-action-group-check.py'))
anchors=importlib.util.module_from_spec(spec);spec.loader.exec_module(anchors)

ROLES={
 'linux-wallpaperengine-controller':{
  'configuration':'applyWallpaperColorsOnApply autoApplyOnStartup badgeEnabled badgeOrder defaultAudioReactiveEffects defaultClamp defaultDisableMouse defaultDisableParallax defaultFps defaultFullscreenPauseOnlyActive defaultMuted defaultNoAutomute defaultNoFullscreenPause defaultScaling defaultVolume enableExtraPropertiesEditor iconColor panelPageSize showSidebarDescription wallpaperScanCacheMinutes wallpapersFolder'.split(),
  'operational':'lastKnownGoodScreens panelLastSelectedPath runtimeRecoveryPending screens wallpaperColorScreenshots'.split(),
  'content':['wallpaperProperties']},
 'mpvpaper':{'configuration':'active automation automationMode automationTime currentWallpaper fillMode hardwareAcceleration isMuted isPlaying mpvSocket profile volume wallpapersFolder'.split(),'operational':['oldWallpapers','thumbCacheReady'],'content':[]},
 'video-wallpaper':{'configuration':'activeBackend automation automationCustomTime automationMode automationTime currentWallpaper enabled fillMode hardwareAcceleration isMuted monitorSpecific monitors mpvSocket orientation profile volume wallpapersFolder'.split(),'operational':['isPlaying'],'content':[]}}

# Every declared leaf has a finite mapping. A monitor command's field domain is
# not an invented independent top-level output authority; preserve that existing
# distinction, including the legacy global currentWallpaper/isPlaying leaves.
READS={
 'linux-wallpaperengine-controller':{
  'Panel.qml':{'applyWallpaperColorsOnApply':'cfg.applyWallpaperColorsOnApply','badgeEnabled':'cfg.badgeEnabled','badgeOrder':'cfg.badgeOrder','enableExtraPropertiesEditor':'cfg.enableExtraPropertiesEditor','panelPageSize':'cfg.panelPageSize','showSidebarDescription':'cfg.showSidebarDescription'},
  'BarWidget.qml':{'iconColor':'cfg.iconColor'},
  'WallpaperCatalog.qml':{'wallpapersFolder':'cfg.wallpapersFolder','wallpaperScanCacheMinutes':'cfg.wallpaperScanCacheMinutes'},
  'Main.qml':{key:'cfg.'+key for key in 'defaultAudioReactiveEffects defaultClamp defaultDisableMouse defaultDisableParallax defaultFps defaultFullscreenPauseOnlyActive defaultMuted defaultNoAutomute defaultNoFullscreenPause defaultScaling defaultVolume'.split()}},
 'mpvpaper':{'Main.qml':{key:'cfg.'+key for key in ROLES['mpvpaper']['configuration']}},
 'video-wallpaper':{'Main.qml':{'activeBackend':'root.cfg.activeBackend','monitors':'root.cfg.monitors','wallpapersFolder':'cfg.wallpapersFolder'},
  'main/Automation.qml':{'automation':'Commands.automationSettings(cfg','automationMode':'globalSettings.automationMode','automationTime':'globalSettings.automationTime','monitorSpecific':'cfg.monitorSpecific'},
  'main/Mpvpaper.qml':{'enabled':'cfg.enabled','mpvSocket':'cfg.mpvSocket'},
  'settings/AutomationTab.qml':{'automationCustomTime':'automationCustomTime'},
  'common/MonitorCommands.js':{key:'"'+key+'"' for key in 'currentWallpaper fillMode hardwareAcceleration isMuted orientation profile volume'.split()}}}

POLICY={
 'linux-wallpaperengine-controller/Main.qml':[
  'readonly property var cfg: policyContext?.settingsView || ({})','property var catalogClients: new Map()',
  'catalogClients.has(context)','catalogClients.set(context, client)','context.current()',
  'function reload(showToast = false, context)','function setScreenWallpaperWithOptions(screenName, path, options, runtimeApi)',
  'function setAllScreensWallpaperWithOptions(path, options, runtimeApi)','const writer = runtimeApi || pluginApi',
  'writer.pluginSettings.defaultVolume','writer.saveSettings()','pluginApi.pluginSettings.screens',
  'const policy = enginePolicy','const currentScreens = cloneValue(policy.screens)',
  'restartEngine(null, policy.context, policy)','pendingPolicy = policy','enginePolicy = policy',
  'root.startEngineWithCommand(nextCommand, nextPolicy)','enginePolicy?.context?.current()',
  'screens: cloneValue(pluginApi.pluginSettings.screens)','properties: cloneValue(pluginApi.pluginSettings.wallpaperProperties)',
  'defaultFps: defaultFps','policy.properties[wallpaperIdFromPath(path)]','policy.options',
  'return EngineHelpers.buildEngineCommand(options)','readonly property int defaultFps:',
  'readonly property bool defaultAutoApply: pluginApi?.pluginSettings.autoApplyOnStartup',
  'pluginApi.pluginSettings.lastKnownGoodScreens = currentScreens','pluginApi.pluginSettings.panelLastSelectedPath = String(path)',
  'capturePolicyFn: root.captureColorPolicy','property int colorAdmissionFps: 30'],
 'linux-wallpaperengine-controller/WallpaperCatalog.qml':[
  'readonly property var cfg: settingsContext.settingsView','const value = Number(cfg.wallpaperScanCacheMinutes',
  'requestFolder = folderPath','requestGeneration = generation','root.requestGeneration !== root.generation',
  'root.requestFolder !== root.folderPath','scanner.running = false','root.retire(root)',
  'scanner.command = ["bash", pluginApi.pluginDir + "/scripts/scan-wallpapers.sh", requestFolder]'],
 'linux-wallpaperengine-controller/WallpaperColorManager.qml':[
  'required property var capturePolicyFn','const wallpaperProperties = policy.properties[wallpaperIdFromPathFn(wallpaperPath)]',
  'policy.fps','policy.clamp','colorPolicy = policy','pendingWallpaperColorReuseRequest.policy = policy',
  'request.policy = policy','const policy = root.colorPolicy','if (!policy?.context?.current()) return',
  'root.applyWallpaperColorsFromPath(request.path, request, request.policy)',
  'root.startWallpaperColorCapture(request.wallpaperPath, request.screenName, request.scaling, !!request.notify, request.policy)',
  'pluginApi.pluginSettings.wallpaperColorScreenshots[screenName]'],
 'linux-wallpaperengine-controller/Settings.qml':['main.activatePolicy(root.pluginApi.runtimeContext)','main.reload(false, root.pluginApi.runtimeContext)','enabled: root.pluginApi?.scopeKind !== "instance"'],
 'linux-wallpaperengine-controller/Panel.qml':['mainInstance?.settingsConsumerFor(pluginApi?.settingsContext)','catalog?.cachedWallpaperItems',
  'mainInstance?.setScreenWallpaperWithOptions(targetScreen, path, options, pluginApi)',
  'mainInstance?.setAllScreensWallpaperWithOptions(path, options, pluginApi)',
  'mainInstance?.refreshWallpaperCache(force, true, pluginApi?.settingsContext)',
  'mainInstance?.scheduleWallpaperColorsFromPath(path, colorApplyOptions, pluginApi?.settingsContext)',
  'mainInstance?.reload(true, pluginApi?.settingsContext)','mainInstance?.rememberPanelPath(next, flushToDisk)'],
 'linux-wallpaperengine-controller/BarWidget.qml':['mainInstance?.refreshWallpaperCache(true, true, pluginApi?.settingsContext)','mainInstance?.reload(true, pluginApi?.settingsContext)'],
 'mpvpaper/Main.qml':[
  'readonly property var cfg: policyContext?.settingsView','readonly property bool policyCurrent: policyContext?.current()',
  'function registerRuntime(runtimeApi)','function activatePolicy(context)','function setPreference(key, value, runtimeApi)',
   'runtimeApi.pluginSettings[key] = value','runtimeApi.pluginSettings.currentWallpaper = path','runtimeApi.pluginSettings.isPlaying = true','runtimeApi.saveSettings()',
  'runtimeOrigins.find(api => api.settingsContext === context && context.current())',
  'settingsContext: root.policyContext','runtimeWriter: root.runtimeWriter','pluginApi: root.pluginApi',
  'pluginApi.pluginSettings.oldWallpapers','pluginApi.pluginSettings.thumbCacheReady',
  'const writer = root.runtimeWriterForPolicy(); if (writer) root.random(writer)',
  'pendingBrowse = {writer: runtimeApi, context: runtimeApi.settingsContext',
   'request.context !== policyContext','request.folder !== String(request.context.settingsView.wallpapersFolder ?? "")','model.status !== FolderListModel.Ready',
   'model !== browseChoices','setWallpaper(model.get(index, "filePath"), request.writer)'],
 'mpvpaper/main/Mpvpaper.qml':[
  'required property var settingsContext','property var runtimeWriter: null','function replacePolicy()',
  'generation !== root.policyGeneration','admittedContext !== settingsContext',
  'const writer = runtimeWriter','writer?.settingsContext === settingsContext && settingsContext.current()',
   'writer.pluginSettings.volume = v','writer.saveSettings()',
  'thumbnails.startColorGen(settingsContext, currentWallpaper)'],
 'mpvpaper/main/Thumbnails.qml':['colorRequest = {context: context, path: String(path)}',
  'root.colorRequest !== request || !request.context.current()','root.getThumbPath(request.path)',
  'const videoUrl = request.path','thumbColorGenTimerProc.request = request',
  'request === root.colorRequest && request?.context?.current()',
  'pluginApi.pluginSettings.thumbCacheReady = true','pluginApi.pluginSettings.thumbCacheReady = false'],
 'mpvpaper/main/InnerService.qml':['pluginApi.pluginSettings.oldWallpapers = wallpapers'],
  'mpvpaper/Settings.qml':['root.pluginApi.mainInstance?.activatePolicy(root.pluginApi.runtimeContext)'],
 'mpvpaper/Panel.qml':['registerRuntime(pluginApi)','setWallpaper(wallpaper.path, pluginApi)','setPreference("isPlaying", value, root.pluginApi)','setPreference("isMuted", value, root.pluginApi)','setPreference("wallpapersFolder", paths[0], pluginApi)'],
 'mpvpaper/BarWidget.qml':['registerRuntime(pluginApi)','setPreference("active", !root.active, root.pluginApi)'],
 'video-wallpaper/Main.qml':['function registerRuntime(runtimeApi)','function activatePolicy(context)','function admitRuntime(runtimeApi)',
  'readonly property var cfg: policyContext?.settingsView','if (root.policyCurrent) wallpaperLoader.active = true',
  'if (!root.policyCurrent) return null','runtimeWriter: root.runtimeWriter','admitRuntime: root.admitRuntime',
  'if (root.runtimeWriter) root.random(screen, root.runtimeWriter)','if (root.runtimeWriter) root.nextWallpaper(screen, root.runtimeWriter)'],
  'video-wallpaper/main/Functions.qml':['const writer = runtimeApi','if (!runtimeApi?.settingsContext?.current())',
   'return writer.pluginSettings.monitors','writer.pluginSettings.monitors = value','writer.saveSettings()',
   'request.context !== settingsContext','model !== browseChoices','request.folder !== String(request.context.settingsView.wallpapersFolder ?? "")',
   'setWallpaper(model.get(index), undefined, request.writer, request.screens)'],
 'video-wallpaper/main/InnerService.qml':['readonly property var cfg: settingsContext?.settingsView',
  'runtimeWriter?.settingsContext === settingsContext && policyCurrent','pluginApi: root.runtimeWriter',
  'onSettingsContextChanged: requestBaseline()'],
 'video-wallpaper/common/SaveTimer.qml':['context: context, writer: pluginApi','root._pending.writer?.settingsContext?.current()',
  'const writer = body.writer','writer.pluginSettings.monitors = value','writer.saveSettings(finish)'],
 'video-wallpaper/main/Mpvpaper.qml':['readonly property var cfg: settingsContext?.settingsView',
  'policyCurrent && (cfg.enabled ?? false)','function replacePolicy()','admittedContext !== settingsContext'],
 'video-wallpaper/main/VideoWallpaper.qml':['readonly property var cfg: settingsContext?.settingsView','policyCurrent && (cfg.enabled ?? false)'],
 'video-wallpaper/main/Automation.qml':['readonly property var cfg: settingsContext?.settingsView','root.policyCurrent && root.monitorSpecific && selectedAutomation'],
 'video-wallpaper/main/ColorGeneration.qml':['readonly property var cfg: settingsContext?.settingsView','policyCurrent && (cfg.enabled ?? false)'],
 'video-wallpaper/main/IPC.qml':['required property var admitRuntime','!admitRuntime(pluginApi)','!root.admitRuntime(root.pluginApi)'],
 'video-wallpaper/Settings.qml':['root.pluginApi.mainInstance?.activatePolicy(root.pluginApi.runtimeContext)'],
 'video-wallpaper/BarWidget.qml':['registerRuntime(pluginApi)','pluginApi.mainInstance?.admitRuntime(pluginApi)'],
 'video-wallpaper/Panel.qml':['registerRuntime(pluginApi)','root.pluginApi.mainInstance?.admitRuntime(root.pluginApi)'],
  'video-wallpaper/panel/PerScreenPanel.qml':['pluginApi.mainInstance?.admitRuntime(pluginApi)']}

# Closed-world caller/effect inventory, alongside the semantic field anchors.
# An added child or call cannot hide behind an already reviewed root entry.
CALLS={
 'linux-wallpaperengine-controller/BarWidget.qml':dict(refreshWallpaperCache=1,stopAll=1,reload=1),
 'linux-wallpaperengine-controller/Panel.qml':dict(settingsConsumerFor=1,getWallpaperProperties=3,rememberPanelPath=1,getScreenConfig=1,setAllScreensWallpaperWithOptions=1,
     setScreenWallpaperWithOptions=1,scheduleWallpaperColorsFromPath=2,refreshWallpaperCache=3,stopAll=1,reload=1),
 'linux-wallpaperengine-controller/Settings.qml':dict(activatePolicy=1,refreshWallpaperCache=1,hasAnyConfiguredWallpaper=1,reload=1,retainWallpaperColorScreenshots=1),
 'mpvpaper/BarWidget.qml':dict(registerRuntime=2,setPreference=5),
 'mpvpaper/Panel.qml':dict(registerRuntime=2,thumbRegenerate=1,getThumbUrl=1,setWallpaper=1,setPreference=3,random=1,clear=1),
 'mpvpaper/Settings.qml':dict(activatePolicy=1),
 'video-wallpaper/BarWidget.qml':dict(registerRuntime=2,admitRuntime=3),
 'video-wallpaper/Panel.qml':dict(registerRuntime=2,thumbRegenerate=1,admitRuntime=3),
 'video-wallpaper/panel/PerScreenPanel.qml':dict(admitRuntime=1,getThumbPath=1,random=1,clear=1),
 'video-wallpaper/Settings.qml':dict(activatePolicy=1)}
EFFECTS={
 'linux-wallpaperengine-controller/Main.qml':dict(Process=4,IpcHandler=1),
 'linux-wallpaperengine-controller/WallpaperCatalog.qml':dict(Process=1),
 'linux-wallpaperengine-controller/WallpaperColorManager.qml':dict(Process=2),
 'linux-wallpaperengine-controller/Panel.qml':dict(Process=2),
 'linux-wallpaperengine-controller/Settings.qml':dict(Process=3),
 'linux-wallpaperengine-controller/components/wallpaper/GridSection.qml':dict(Video=1),
 'linux-wallpaperengine-controller/components/wallpaper/PreviewCard.qml':dict(Video=1),
 'mpvpaper/Main.qml':dict(IpcHandler=1),
 'mpvpaper/main/Mpvpaper.qml':dict(Process=1,Socket=1),
 'mpvpaper/main/Thumbnails.qml':dict(Process=3),
 'video-wallpaper/main/IPC.qml':dict(IpcHandler=1),
 'video-wallpaper/main/Mpvpaper.qml':dict(Process=2,Socket=1),
 'video-wallpaper/main/VideoWallpaper.qml':dict(Video=1),
 'video-wallpaper/main/Thumbnails.qml':dict(Process=3),
 'video-wallpaper/common/FolderModel.qml':dict(Process=1)}

TOOLS={
 'mpvpaper/common/ToolRow.qml':['required property var randomAction','required property var clearAction','randomAction()','clearAction()'],
 'video-wallpaper/common/ToolRow.qml':['required property var randomAction','required property var clearAction','randomAction()','clearAction()'],
 'mpvpaper/Panel.qml':['randomAction: () => root.pluginApi.mainInstance.random(root.pluginApi)','clearAction: () => root.pluginApi.mainInstance.clear(root.pluginApi)'],
 'video-wallpaper/panel/PerScreenPanel.qml':['randomAction: () => root.pluginApi.mainInstance.random(root.screenName, root.pluginApi)','clearAction: () => root.pluginApi.mainInstance.clear(root.screenName, root.pluginApi)'],
 'mpvpaper/Settings.qml':['randomAction: root.stageRandomWallpaper','clearAction: root.stageClearWallpaper','currentWallpaperField.set("")',
     'currentWallpaperField.set(model.get(Math.floor(Math.random() * model.count), "filePath"))',
     'model !== randomChoices','request.folder !== randomFolderPath','model.status !== FolderListModel.Ready'],
 'video-wallpaper/settings/GeneralTab.qml':['randomAction: root.stageRandomWallpaper','clearAction: root.stageClearWallpaper','saveWallpaperChoice(path, screens)',
     'currentWallpaper = path','pendingRandom = {folder: Settings.preprocessPath(root.wallpapersFolder), screens: wallpaperScreens()}',
     'model !== randomChoices','request.folder !== randomFolderPath','model.status !== FolderListModel.Ready'],
 'video-wallpaper/Settings.qml':['onSaveWallpaperChoice: (path, screens) =>','field: "currentWallpaper", value: path']}


def check(sources,manifests,dictionaries):
    codes={}
    trees={}
    for path,text in sources.items():
        # Parse standalone JS as a function body in the same QML/JS grammar.
        # Only Qt's known .pragma directive is removed; all JS stays parsed.
        if path.endswith('.js'):
            text='QtObject { function script() {\n'+re.sub(r'^\.pragma library\s*$', '', text, flags=re.M)+'\n} }'
        try:
            codes[path],trees[path]=syntax.compact(text)
        except ValueError as error: raise ValueError(path+': '+str(error)) from error
    rows=[]
    for name,roles in ROLES.items():
        fields=manifests[name]['metadata']['settingsSchema']['fields']
        expected={field:role for role,members in roles.items() for field in members}
        if {field:value.get('editorUsage') for field,value in fields.items()}!=expected: raise ValueError(name+': declared leaf/role mapping changed')
        if manifests[name]['entryPoints']!=dict(main='Main.qml',barWidget='BarWidget.qml',panel='Panel.qml',settings='Settings.qml'): raise ValueError(name+': runtime entry mapping changed')
        mapped={field for entries in READS[name].values() for field in entries}
        if name=='linux-wallpaperengine-controller': mapped.add('autoApplyOnStartup')
        if mapped!=set(roles['configuration']): raise ValueError(name+': incomplete configuration mapping')
        for path,entries in READS[name].items():
            for field,anchor in entries.items(): anchors.require(codes[name+'/'+path],anchor,name+': field '+field+' at '+path)
        settings=codes[name+'/Settings.qml']
        for anchor in ('visible: root.pluginApi?.scopeKind === "instance"','root.pluginApi?.tr("settings.shared-effect")'): anchors.require(settings,anchor,name+': shared-effect UI')
        for locale,dictionary in dictionaries[name].items():
            if not dictionary.get('settings',{}).get('shared-effect','').strip(): raise ValueError(name+': explanation missing '+locale)
        rows.append(dict(plugin=name,configuration=roles['configuration'],protected={role:value for role,value in roles.items() if role!='configuration'}))
    for path,items in POLICY.items():
        for anchor in items: anchors.require(codes[path],anchor,path+': '+anchor)
    for path,items in TOOLS.items():
        for anchor in items: anchors.require(codes[path],anchor,path+': '+anchor)
    from collections import Counter
    for path,code in codes.items():
        if '/fixtures/' in path: continue
        callers=dict(Counter(re.findall(r'(?:mainInstance|main)\??\.(\w+)\(',code)))
        effects=Counter()
        raw=sources[path].encode()
        for node in syntax.walk(trees[path].root_node):
            if node.type!='ui_object_definition':continue
            match=re.match(rb'(Process|Socket|IpcHandler|MediaPlayer|AudioOutput|Video)\s*\{',raw[node.start_byte:node.end_byte].lstrip())
            if match:effects[match.group(1).decode()]+=1
        effects=dict(effects)
        if callers!=CALLS.get(path,{}):raise ValueError(path+': unreviewed Main caller inventory '+repr(callers))
        if effects!=EFFECTS.get(path,{}):raise ValueError(path+': unreviewed physical/native effect owner '+repr(effects))
        if 'execDetached(' in code and (path!='linux-wallpaperengine-controller/WallpaperColorManager.qml' or code.count('execDetached(')!=1):raise ValueError(path+': unreviewed detached effect')
        if path.endswith('/common/ToolRow.qml') and ('mainInstance' in code or '.saveSettings(' in code):raise ValueError(path+': ToolRow selected an owner instead of injected callbacks')
    if codes['video-wallpaper/Main.qml'].count('settingsContext:root.policyContext')!=7: raise ValueError('video-wallpaper: every Main child receives selected policy')
    if codes['video-wallpaper/Main.qml'].count('Variants{')!=1 or codes['mpvpaper/Main.qml'].count('Mpvpaper{')!=1: raise ValueError('singular physical wallpaper owner changed')
    # Per-context catalog workers are read-only source queries. No native writer
    # or physical engine is allowed in that client or any placed wallpaper view.
    if re.search(r'(?:saveSettings\(|pluginSettings\.|execDetached\(|linux-wallpaperengine")',codes['linux-wallpaperengine-controller/WallpaperCatalog.qml']): raise ValueError('catalog gained a physical/native writer')
    for name in ROLES:
        for path in (name+'/BarWidget.qml',name+'/Panel.qml'):
            if 'execDetached(' in codes[path]: raise ValueError(path+': duplicate detached physical owner')
    return rows


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--plugins',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);parser.add_argument('--selftest',action='store_true');args=parser.parse_args()
    sources={};manifests={};dictionaries={}
    for name in ROLES:
        manifests[name]=json.loads((args.plugins/name/'manifest.json').read_text())
        dictionaries[name]={p.name:json.loads(p.read_text()) for p in (args.plugins/name/'i18n').glob('*.json')}
        sources.update({str(p.relative_to(args.plugins)):p.read_text() for p in (args.plugins/name).rglob('*') if p.suffix in ('.qml','.js')})
    rows=check(sources,manifests,dictionaries);controls=[]
    if args.selftest:
        mutations=[
          ('linux-wallpaperengine-controller/Main.qml','policyContext?.settingsView','pluginApi?.pluginSettings','shared-lwe-policy'),
          ('linux-wallpaperengine-controller/Main.qml','cloneValue(policy.screens)','cloneValue(pluginApi.pluginSettings.screens)','mutable-lwe-stability'),
          ('linux-wallpaperengine-controller/Main.qml','restartEngine(null, policy.context, policy)','restartEngine()','lost-lwe-recovery-origin'),
          ('linux-wallpaperengine-controller/Panel.qml','setScreenWallpaperWithOptions(targetScreen, path, options, pluginApi)','setScreenWallpaperWithOptions(targetScreen, path, options)','omitted-lwe-writer'),
          ('linux-wallpaperengine-controller/WallpaperCatalog.qml','root.requestGeneration !== root.generation','false','unfenced-lwe-source'),
          ('mpvpaper/Main.qml','runtimeApi.pluginSettings.currentWallpaper = path','pluginApi.pluginSettings.currentWallpaper = path','shared-mpv-writer'),
          ('mpvpaper/BarWidget.qml','setPreference("active", !root.active, root.pluginApi)','setPreference("active", !root.active)','omitted-mpv-origin'),
          ('mpvpaper/main/Thumbnails.qml','root.getThumbPath(request.path)','root.getThumbPath(root.currentWallpaper)','mutable-mpv-color-target'),
          ('video-wallpaper/Main.qml','runtimeWriter: root.runtimeWriter','runtimeWriter: root.pluginApi','shared-video-baseline-writer'),
          ('video-wallpaper/common/SaveTimer.qml','const writer = body.writer','const writer = root.pluginApi','retargeted-video-delayed-writer'),
          ('video-wallpaper/main/Automation.qml','root.policyCurrent && root.monitorSpecific && selectedAutomation','root.monitorSpecific && selectedAutomation','retired-video-automation'),
           ('video-wallpaper/main/Mpvpaper.qml','admittedContext !== settingsContext','false','retargeted-video-socket')]
        mutations += [
          ('mpvpaper/Panel.qml','mainInstance.clear(root.pluginApi)','mainInstance.clear()','omitted-mpv-tool-origin'),
          ('video-wallpaper/panel/PerScreenPanel.qml','mainInstance.random(root.screenName, root.pluginApi)','mainInstance.random(root.screenName)','omitted-video-tool-origin'),
          ('mpvpaper/Settings.qml','clearAction: root.stageClearWallpaper','clearAction: () => root.pluginApi.mainInstance.clear()','live-settings-clear'),
          ('video-wallpaper/settings/GeneralTab.qml','request.folder !== randomFolderPath','false','stale-settings-random-folder'),
          ('mpvpaper/main/Automation.qml','Item {','Item { Process {}','extra-physical-owner')]
        for path,old,new,label in mutations:
            if sources[path].count(old)!=1: raise RuntimeError('stale wallpaper control '+label)
            changed=dict(sources);changed[path]=changed[path].replace(old,new,1)
            try:check(changed,manifests,dictionaries)
            except ValueError as error:controls.append(dict(control=label,rejectedAt=str(error)))
            else:raise RuntimeError('wallpaper control escaped '+label)
        for name in ROLES:
            changed=json.loads(json.dumps(manifests));changed[name]['entryPoints']['barWidget']='Unreviewed.qml'
            try:check(sources,changed,dictionaries)
            except ValueError as error:controls.append(dict(control='unreviewed-entry',plugin=name,rejectedAt=str(error)))
            else:raise RuntimeError('wallpaper entry escaped')
    args.report.write_text(json.dumps(dict(status='PASS',kind='finite-parsed-contract',members=rows,controls=controls,runtimeAcceptance=False,completeGroupAcceptance=False),indent=2)+'\n')
    print('WALLPAPER_GROUP_CHECK: PASS (%d members; %d controls)'%(len(rows),len(controls)))


if __name__=='__main__':main()
