#!/usr/bin/env python3
"""Finite two-field Catwalk reader, physical observer, presentation and reset map."""
import argparse
import importlib.util
import json
from pathlib import Path
spec=importlib.util.spec_from_file_location('catwalk_syntax',Path(__file__).with_name('plugin-settings-claude-check.py'));syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
ANCHORS={
 'Main.qml':['required property var settingsContext','readonly property bool current: settingsContext.current()','readonly property var cfg: current ? settingsContext.settingsView : ({})','cfg.minimumThreshold ?? 10','cfg.hideBackground ?? false','readonly property real cpuUsage: current ? readCpu() : 0','readonly property bool isRunning: current && cpuUsage >= minimumThreshold','settingsContext: context','return root.cpuUsage','root._settingsConsumers.delete(context); retired.destroy()','property real cpuUsage: SystemStatService.cpuUsage'],
 'BarWidget.qml':['settingsConsumerFor(pluginApi.settingsContext)','readonly property bool isRunning: root.settingsConsumer?.isRunning ?? false','readonly property real cpuUsage: root.settingsConsumer?.cpuUsage ?? 0','running: root.isRunning','running: !root.isRunning','source: root.currentIconSource'],
 'DesktopWidget.qml':['settingsConsumerFor(pluginApi.settingsContext)','showBackground: !(root.settingsConsumer?.hideBackground ?? false)','readonly property bool isRunning: root.settingsConsumer?.isRunning ?? false','source: root.currentIconSource','text: Math.round(root.cpuUsage) + "%"'],
 'Settings.qml':['pluginApi?.field("minimumThreshold")','pluginApi?.field("hideBackground")','onMoved: root.threshold.set(value)','root.background.set(checked)','pluginApi.saveSettings(function (result)','result.refreshState === "current"']}
def check(sources,manifest):
    fields=manifest['metadata']['settingsSchema']['fields'];assert set(fields)=={'minimumThreshold','hideBackground'} and all(row['editorUsage']=='configuration' for row in fields.values())
    for name,anchors in ANCHORS.items():
        code=syntax.syntax.compact(sources[name])[0]
        for anchor in anchors:syntax.require(code,anchor,name+': '+anchor)
    assert all(key not in sources['Panel.qml'] for key in ['minimumThreshold','hideBackground']),'Panel is a common physical-statistics view, not a selected configuration reader'
    assert 'pluginSettings' not in sources['Main.qml'],'configuration projection has no new writer'
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['source','plugins','report']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--selftest',action='store_true');a=p.parse_args();root=a.plugins/'catwalk';sources={p.name:p.read_text() for p in root.glob('*.qml')};manifest=json.loads((root/'manifest.json').read_text());check(sources,manifest);controls=[]
    mutations=[('Main.qml','settingsContext: context','settingsContext: pluginApi.settingsContext','factory-origin'),('Main.qml','current ? settingsContext.settingsView : ({})','pluginApi.settingsView','shared-configuration'),('Main.qml','cpuUsage >= minimumThreshold','cpuUsage >= 10','selected-threshold'),('Main.qml','root._settingsConsumers.delete(context);','root._settingsConsumers.clear();','retirement-owner'),('BarWidget.qml','settingsConsumerFor(pluginApi.settingsContext)','settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)','bar-reader'),('DesktopWidget.qml','settingsConsumerFor(pluginApi.settingsContext)','settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)','desktop-reader'),('DesktopWidget.qml','source: root.currentIconSource','source: "wrong"','image-child'),('Settings.qml','onMoved: root.threshold.set(value)','onMoved: {}','threshold-intent'),('Settings.qml','root.background.set(checked)','root.background.set(false)','background-intent')]
    if a.selftest:
        for name,old,new,label in mutations:
            assert old in sources[name];changed=dict(sources);changed[name]=changed[name].replace(old,new)
            try:check(changed,manifest)
            except (AssertionError,ValueError) as error:controls.append(dict(control=label,rejectedAt=str(error)))
            else:raise RuntimeError('Catwalk parsed control escaped '+label)
    a.report.write_text(json.dumps(dict(status='PASS',fields=['minimumThreshold','hideBackground'],controls=controls,runtimeAcceptance=False),indent=2)+'\n');print('CATWALK_MATRIX_CHECK: PASS (2 fields, %d controls)'%len(controls))
if __name__=='__main__':main()
