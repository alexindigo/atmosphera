#!/usr/bin/env python3
"""Finite field/entry/generation map for the three existing worker clients."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
spec=importlib.util.spec_from_file_location('worker_syntax',Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
MEMBERS={
    'air-quality':('AirQualitySettingsClient.qml','AirQualityQueryWorker.qml','aqiScale aqicnToken boldText customLatitude customLongitude dataSource refreshInterval useNoctaliaLocation'),
    'github-contributions':('ContributionsSettingsClient.qml','ContributionsQueryWorker.qml','layout refreshInterval showLabels showTotal token username weeksShown'),
    'arch-updater':('ArchUpdaterSettingsClient.qml','ArchUpdaterQueryWorker.qml','aurCmd aurHomepageCmd boldText boldVer boldVerDesktop boldVerPanel closeButton closeOnSettings customIconPath desktopTip enableColorization flatpak hideOnEmpty hoverTip iconColor iconName noctalia panelContext panelTooltip refreshInterval refreshTimer systemCmd toast tooltip updateCmd useDistroLogo')}
# Existing P006/legacy declarations, not newly promised consumers. These bytes
# stay native-owned. The matrix must not silently invent timer policy or migrate
# the old unused presentation keys while qualifying selected query ownership.
LEGACY={'arch-updater':{'boldVer':'legacy declaration, no current reader/control','desktopTip':'legacy declaration, no current reader/control','refreshTimer':'page visibility only; P006 timer policy explicitly separate'}}
ANCHORS={
    'air-quality': ['JSON.stringify([cfg.dataSource, cfg.aqicnToken, cfg.useNoctaliaLocation, cfg.customLatitude, cfg.customLongitude, cfg.aqiScale, cfg.refreshInterval, Settings.data.location?.weatherEnabled, Settings.data.location?.name, _weather?.latitude, _weather?.longitude])','configuration: cfg','location: Object.freeze({'],
    'github-contributions':['JSON.stringify([username, token, cfg.refreshInterval])','configuration: cfg','(cfg.username ?? "").trim()','(cfg.token ?? "").trim()'],
    'arch-updater':['JSON.stringify([systemCmd, aurCmd, flatpak, noctalia, refreshInterval])','configuration: Object.freeze({','actionSettings: root.actionSettings','systemCmd: systemCmd','aurCmd: aurCmd','flatpak: flatpak','noctalia: noctalia','refreshInterval: refreshInterval','toast: cfg.toast','updateCmd: cfg.updateCmd','aurHomepageCmd: cfg.aurHomepageCmd']}
def require(code,anchor,label):syntax.require(code,anchor,label+': '+anchor)
def check(sources,manifests):
    rows=[]
    for plugin,(clientFile,workerFile,declared) in MEMBERS.items():
        raw=sources[plugin];codes={name:syntax.compact(text)[0] for name,text in raw.items()};manifest=manifests[plugin];fields=manifest['metadata']['settingsSchema']['fields'];wanted=set(declared.split())
        if set(fields)!=wanted or any(v['editorUsage']!='configuration' for v in fields.values()):raise ValueError(plugin+': unreviewed field set or usage')
        main,client,worker,page=(codes[n] for n in ['Main.qml',clientFile,workerFile,'Settings.qml'])
        for anchor in ['property var _settingsConsumers: new Map()','if (!context || !context.current()) return null','if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)','settingsContext: context','root._settingsConsumers.delete(context)','retired.destroy()','_settingsConsumers.set(context, client)']:require(main,anchor,plugin+' Main')
        for anchor in ['readonly property bool current: settingsContext.current()','readonly property var cfg: current ? settingsContext.settingsView : ({})','var old = _worker; _worker = null; old.active = false; old.destroy()','_retireWorker(); if (!current) return','on_QueryIdentityChanged: _replaceQuery()','if (!current && _constructed) { _retireWorker(); retire(root); }','Component.onDestruction: _retireWorker()']:require(client,anchor,plugin+' client')
        for anchor in ANCHORS[plugin]:require(client,anchor,plugin+' query identity')
        require(worker,'required property var configuration',plugin+' worker')
        require(worker,'running: root.active',plugin+' worker timer')
        require(worker,'if (!root.active) return',plugin+' result fence')
        require(page,'settingsConsumerFor(root.pluginApi.runtimeContext)?.refresh()',plugin+' completion')
        require(page,'result.refreshState',plugin+' receipt admission')
        entries=[]
        for kind,path in manifest['entryPoints'].items():
            if kind not in {'barWidget','desktopWidget','panel','launcherProvider','controlCenterWidget'}:continue
            code=codes[path];entries.append(path)
            if plugin=='arch-updater' and kind=='controlCenterWidget':require(code,'pluginApi.togglePanel(screen, this)',plugin+' route-only ControlCenter');continue
            require(code,'settingsConsumerFor(pluginApi.settingsContext)',plugin+' '+kind)
        readers=''.join(code for name,code in codes.items() if name not in {'Main.qml','Settings.qml'})
        mapped=[]
        for key in sorted(wanted):
            if key in LEGACY.get(plugin,{}):
                mapped.append(dict(field=key,classification=LEGACY[plugin][key]));continue
            if not re.search(r'(?:cfg|pluginSettings)(?:\?|)\.'+key+r'\b',readers):raise ValueError(plugin+': missing selected field consumer '+key)
            require(page,'field("'+key+'")',plugin+' page field '+key)
            mapped.append(dict(field=key,classification='selected configuration'))
        rows.append(dict(plugin=plugin,fields=mapped,entries=entries))
    return rows
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for key in ['source','plugins','report']:p.add_argument('--'+key,type=Path,required=True)
    p.add_argument('--selftest',action='store_true');a=p.parse_args();sources={};manifests={}
    for plugin in MEMBERS:
        root=a.plugins/plugin;sources[plugin]={p.name:p.read_text() for p in root.glob('*.qml')};manifests[plugin]=json.loads((root/'manifest.json').read_text())
    rows=check(sources,manifests);controls=[]
    if a.selftest:
        for plugin,(client,worker,_) in MEMBERS.items():
            for name,old,new,label in [('Main.qml','settingsContext: context','settingsContext: pluginApi.settingsContext','factory-context'),('Main.qml','root._settingsConsumers.delete(context)','root._settingsConsumers.clear()','retirement-cache'),(client,'settingsContext.settingsView','pluginApi.pluginSettings','shared-reader'),(client,'old.active = false;','/* keep active */','generation-fence'),('DesktopWidget.qml','settingsConsumerFor(pluginApi.settingsContext)','settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)','desktop-reader'),('Settings.qml','root.pluginApi.runtimeContext','root.pluginApi.settingsContext','completion-context')]:
                assert sources[plugin][name].count(old)==1,(plugin,name,old)
                mutated={k:dict(v) for k,v in sources.items()};mutated[plugin][name]=mutated[plugin][name].replace(old,new)
                try:check(mutated,manifests)
                except ValueError as error:controls.append(dict(plugin=plugin,control=label,rejectedAt=str(error)))
                else:raise RuntimeError('worker matrix parsed control escaped '+plugin+'/'+label)
    a.report.write_text(json.dumps(dict(status='PASS',members=rows,controls=controls,runtimeAcceptance=False),indent=2)+'\n');print('WORKER_MATRIX_CHECK: PASS (%d members, %d fields, %d controls)'%(len(rows),sum(len(r['fields']) for r in rows),len(controls)))
if __name__=='__main__':main()
