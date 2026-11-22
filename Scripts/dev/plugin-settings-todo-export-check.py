#!/usr/bin/env python3
"""Finite parsed Todo display/export policy and protected-content ownership."""
import argparse
import importlib.util
import json
from pathlib import Path
spec=importlib.util.spec_from_file_location('todo_export_syntax',Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax=importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
CONFIG='exportEmptySections exportFormat exportPath isExpanded priorityColors showBackground showCompleted useCustomColors'.split()
PROTECTED=dict(todos='content',pages='content',current_page_id='content',count='operational',completedCount='operational')
ANCHORS={
 'Main.qml':['context = context || pluginApi?.settingsContext','if (!context || !context.current()) return false','if (exportBusy)', 'pluginApi.tr("main.export_busy")','var cfg = context.settingsView','exportPath: cfg.exportPath','exportFormat: cfg.exportFormat','exportEmptySections: cfg.exportEmptySections','todos: Pages.clone(rawTodos)','pages: Pages.clone(rawPages)','content = JSON.stringify(request.todos, null, 2)','content = generateExportMarkdown(request)','var exportPath = request.exportPath','request.filePath = filePath','_exportRequest = request','if (!request || !request.context.current()) return','request.filePath.replace','var showEmptySections = request.exportEmptySections','var todos = request.todos','var pages = request.pages','pluginApi.pluginSettings.todos = rawTodos.slice()','pluginApi.pluginSettings.pages = rawPages.slice()','pluginApi.pluginSettings.count = rawTodos.length','pluginApi.pluginSettings.completedCount = rawTodos.filter(t => t.completed).length','function exportTodos() { doExportTodos()'],
 'Panel.qml':['mainInstance.doExportTodos(pluginApi.settingsContext)','value: pluginApi?.pluginSettings?.showCompleted','var useCustomColors = pluginApi?.pluginSettings?.useCustomColors','var customColors = pluginApi?.pluginSettings?.priorityColors'],
 'DesktopWidget.qml':['showBackground: (pluginApi && pluginApi.pluginSettings','pluginApi.pluginSettings.showBackground !== undefined ? pluginApi.pluginSettings.showBackground','value: pluginApi?.pluginSettings?.isExpanded','value: pluginApi?.pluginSettings?.showCompleted','var useCustomColors = pluginApi?.pluginSettings?.useCustomColors','var customColors = pluginApi?.pluginSettings?.priorityColors'],
 'Settings.qml':['visible: root.pluginApi?.scopeKind === "instance"','pluginApi.tr("settings.shared-effect")','readonly property bool sharedContent: pluginApi?.scopeKind === "plugin"','enabled: root.sharedContent','pluginApi.contentField("pages")','pluginApi.contentField("todos")','pluginApi.contentField("current_page_id")']
}
def check(sources,manifest,dictionaries):
    code={key:syntax.compact(value)[0] for key,value in sources.items()}
    fields=manifest['metadata']['settingsSchema']['fields']
    assert set(fields)==set(CONFIG)|set(PROTECTED),'unreviewed Todo leaves'
    for key in CONFIG: assert fields[key]['editorUsage']=='configuration',key
    for key,usage in PROTECTED.items(): assert fields[key]['editorUsage']==usage,(key,usage)
    for name,anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(code[name],anchor,name+': '+anchor)
    for anchor in ['onExited: code => root.settleExport(code)','onRunningChanged: { if (!running) root.settleExport(-1)', 'function settleExport(code) { var request = _exportRequest; _exportRequest = null']:
        syntax.require(code['Main.qml'],anchor,'single request settlement: '+anchor)
    for key in set(CONFIG)-{'isExpanded'}: syntax.require(code['Settings.qml'],'pluginApi?.field("'+key+'")',key)
    assert manifest['entryPoints']==dict(main='Main.qml',barWidget='BarWidget.qml',desktopWidget='DesktopWidget.qml',panel='Panel.qml',settings='Settings.qml',controlCenterWidget='ControlCenterWidget.qml')
    for locale,value in dictionaries.items(): assert value['main']['export_busy'] and value['settings']['shared-effect'],locale
    return dict(configuration=CONFIG,protected=PROTECTED,contentOwner='existing common Main/preferences',exportPolicy='captured originating context',ipc='plugin-level',contentMigration=False,runtimeAcceptance=False)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('source','plugins','report'): parser.add_argument('--'+key,type=Path,required=True)
    parser.add_argument('--selftest',action='store_true'); args=parser.parse_args(); root=args.plugins/'todo'
    sources={p.name:p.read_text() for p in root.glob('*.qml')}; manifest=json.loads((root/'manifest.json').read_text()); dictionaries={p.stem:json.loads(p.read_text()) for p in (root/'i18n').glob('*.json')}
    member=check(sources,manifest,dictionaries); controls=[]
    changes=[('Main.qml','var cfg = context.settingsView','var cfg = pluginApi.pluginSettings','shared-policy'),('Panel.qml','mainInstance.doExportTodos(pluginApi.settingsContext)','mainInstance.doExportTodos()','lost-origin'),('Main.qml','if (exportBusy)','if (false)','busy'),('Main.qml','!request.context.current()','false','retired-feedback'),('Main.qml','request.filePath.replace','currentExportPath.replace','mutable-result'),('Main.qml','var exportPath = request.exportPath','var exportPath = pluginApi.pluginSettings.exportPath','late-path'),('Main.qml','request.exportEmptySections','false','empty-policy'),('Main.qml','Pages.clone(rawTodos)','rawTodos','content-alias'),('Main.qml','pluginApi.pluginSettings.todos = rawTodos.slice()','context.pluginSettings.todos = rawTodos.slice()','content-writer'),('DesktopWidget.qml','pluginApi?.pluginSettings?.isExpanded','mainInstance.pluginApi.pluginSettings.isExpanded','shared-expanded'),('DesktopWidget.qml','pluginApi.pluginSettings.showBackground','mainInstance.pluginApi.pluginSettings.showBackground','shared-background'),('Panel.qml','pluginApi?.pluginSettings?.showCompleted','mainInstance.pluginApi.pluginSettings.showCompleted','shared-filter'),('Panel.qml','pluginApi?.pluginSettings?.priorityColors','mainInstance.pluginApi.pluginSettings.priorityColors','shared-colors')]
    changes += [('Main.qml','root.settleExport(-1)','root.settleExport(0)','failed-start-result'),('Main.qml','_exportRequest = null;\n    if (!request','if (!request','settlement-release')]
    if args.selftest:
        for name,old,new,label in changes:
            assert old in sources[name],label
            changed=dict(sources); changed[name]=sources[name].replace(old,new)
            try: check(changed,manifest,dictionaries)
            except (ValueError,AssertionError) as error: controls.append(dict(control=label,rejectedAt=str(error)))
            else: raise RuntimeError('Todo control escaped: '+label)
    args.report.write_text(json.dumps(dict(status='PASS',member=member,controls=controls,runtimeAcceptance=False),indent=2)+'\n'); print('TODO_EXPORT_CHECK: PASS (8 configuration, 5 protected, %d controls)'%len(controls))
if __name__=='__main__': main()
