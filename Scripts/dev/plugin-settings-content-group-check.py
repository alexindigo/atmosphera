#!/usr/bin/env python3
"""Finite parsed selected-content field/caller/lifetime/shared-owner mapping."""
import argparse
from collections import Counter
import importlib.util
import json
from pathlib import Path
import re

spec=importlib.util.spec_from_file_location('content_syntax',Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
spec=importlib.util.spec_from_file_location('content_anchors',Path(__file__).with_name('plugin-settings-action-group-check.py'))
anchors=importlib.util.module_from_spec(spec);spec.loader.exec_module(anchors)
FIELDS={
 'clipper':['autoPaste','autoPasteDelay','autoPasteOnRightClick','cardColors','customColors','enableTodoIntegration','fullscreenMode','hidePanelBackground','notecardsEnabled','panelHeight','panelWidth','pincardsEnabled','showCloseButton'],
 'music-search':['autoSaveMp3AfterPlayback','defaultPanelLibrarySection','defaultPanelTab','panelDensity','previewMetadataMode','previewPaneWidth','previewThumbnailSize','showAlbumMetadata','showBarHoverTrackTitle','showDurationMetadata','showHomeArtists','showHomePlaylists','showHomeRecent','showHomeTags','showHomeTop','showPanelHeader','showPanelNowPlaying','showPanelPlaybackProgress','showPanelPreview','showPanelProviderChips','showPanelQueueControls','showPanelRecentTracks','showPanelSearchHelper','showPanelSpeedControls','showPanelStatusBanner','showPanelUrlActions','showPlayStatsMetadata','showPreviewChips','showRatingMetadata','showStatusMetadata','showTagMetadata','showUploaderMetadata','ytPlayerClient']}
READS={
 'clipper/Main.qml':['settings.enableTodoIntegration','settings.autoPasteDelay'],
 'clipper/Panel.qml':['settingsView?.'+key for key in ['autoPaste','autoPasteDelay','autoPasteOnRightClick','enableTodoIntegration','fullscreenMode','hidePanelBackground','notecardsEnabled','panelHeight','panelWidth','pincardsEnabled','showCloseButton']],
 'clipper/ClipboardCard.qml':['settingsView?.cardColors','settingsView?.customColors'],
 'music-search/Main.qml':['context.settingsView.autoSaveMp3AfterPlayback'],
 'music-search/BarWidget.qml':['pluginSettings?.showBarHoverTrackTitle'],
 'music-search/Panel.qml':['pluginSettings?.'+key for key in ['defaultPanelLibrarySection','defaultPanelTab','panelDensity','previewPaneWidth','showPanelHeader','showPanelNowPlaying','showPanelPlaybackProgress','showPanelPreview','showPanelProviderChips','showPanelQueueControls','showPanelRecentTracks','showPanelSearchHelper','showPanelSpeedControls','showPanelStatusBanner','showPanelUrlActions']],
 'music-search/LauncherProvider.qml':['cfg.'+key for key in ['previewMetadataMode','showUploaderMetadata','showAlbumMetadata','showDurationMetadata','showRatingMetadata','showTagMetadata','showPlayStatsMetadata','showHomeArtists','showHomePlaylists','showHomeRecent','showHomeTags','showHomeTop']],
 'music-search/MusicPreview.qml':['cfg.'+key for key in ['previewMetadataMode','previewThumbnailSize','showUploaderMetadata','showAlbumMetadata','showDurationMetadata','showPlayStatsMetadata','showStatusMetadata','showPreviewChips']]}
POLICY={
 'clipper/Main.qml':['context = context || pluginApi?.settingsContext','if (!context?.current()) return null','const policy = retainedPolicy || capturePolicy(context)','if (!policy?.context?.current() || !policy.enableTodoIntegration) return','root.selectionPolicy = policy','root.addTodoWithText(selectedText, root.pendingPageId, undefined, root.selectionPolicy)','root.selectorRequestPolicy = policy','root.showTodoPageSelector(selectedText, undefined, root.selectorRequestPolicy)','root.todoSelectorPolicy = policy','root.addTodoWithText(root.pendingSelectedText, pageId, undefined, root.todoSelectorPolicy)','root.todoSelectorPolicy?.context?.current()','root.pastePolicy = policy','root.pastePolicy?.context?.current() && root.wtypeAvailable','policy.autoPasteDelay','todoApi.pluginSettings.todos = todos','todoApi.pluginSettings.count = todos.length','todoApi.saveSettings()','if (getSelectionProcess.running) return','if (getSelectionForSelectorProcess.running) return'],
 'clipper/ClipboardCard.qml':['root.todoPolicy = root.pluginApi?.mainInstance?.capturePolicy(root.pluginApi.settingsContext)','root.todoText = root.preview.substring(0, 200)','addTodoWithText(root.todoText, pageId, undefined, root.todoPolicy)'],
 'music-search/Main.qml':['context = context || pluginApi?.settingsContext','if (!context?.current()) return null','const policy = retainedPolicy || capturePolicy(context)','policy?.context?.current() && policy.autoSaveMp3AfterPlayback','root.maybeAutoDownloadCurrentTrack(policy)','entry: copyEntry(entry)','function maybeAutoDownloadCurrentTrack(policy)','if (!policy?.context?.current()) return','var entry = policy.entry','root.queuePolicy = policy','root.queueBatchPolicy = policy','root.autoplayPolicy = policy','root.startQueue(undefined, root.autoplayPolicy)','root.skipQueue(undefined, root.queueBatchPolicy)','root.startQueue(undefined, root.queueBatchPolicy)','if (!root.queueBatchPolicy?.context?.current())','if (root.queuePolicy?.context?.current())','root.launchQueueEntry(root.queueEntries[0], undefined, root.queuePolicy)','playEntry(normalized, undefined, policy)'],
 'music-search/LauncherProvider.qml':['readonly property var cfg: pluginApi?.settingsView ?? ({})'],
 'music-search/MusicPreview.qml':['readonly property var cfg: detailCacheOwner?.pluginApi?.settingsView ?? ({})'],
 'music-search/Panel.qml':['pluginApi.pluginSettings.previewPaneWidth = rawWidth','pluginApi.saveSettings()'],
 'music-search/Settings.qml':['setYtPlayerClient(key)','setDownloadDirectory(target)','setDownloadCacheMaxMb(target)']}
EFFECTS={'clipper/Main.qml':dict(Process=15,IpcHandler=1),'clipper/SelectionContextMenu.qml':dict(Process=1),'music-search/Main.qml':dict(Process=14,IpcHandler=1),'music-search/Panel.qml':dict(Process=1),'music-search/LauncherProvider.qml':dict(Process=1),'music-search/MusicPreview.qml':dict(Process=1)}
ORIGIN={'playEntry','playUrl','startQueue','skipQueue','autoplaySavedTracks','playPlaylist','playQueueEntryNow','queuePlaylist'}


def check(sources,manifests,dictionaries):
    codes={};trees={}
    for name,text in sources.items():codes[name],trees[name]=syntax.compact(text)
    rows=[]
    for member,fields in FIELDS.items():
        metadata=manifests[member]['metadata']['settingsSchema']['fields']
        if set(metadata)!=set(fields) or any(value.get('editorUsage')!='configuration' for value in metadata.values()):raise ValueError(member+': reviewed field mapping changed')
        entries=dict(main='Main.qml',barWidget='BarWidget.qml',panel='Panel.qml',settings='Settings.qml')
        entries['controlCenterWidget' if member=='clipper' else 'launcherProvider']='ControlCenterWidget.qml' if member=='clipper' else 'LauncherProvider.qml'
        if manifests[member]['entryPoints']!=entries:raise ValueError(member+': unreviewed entry')
        for anchor in ('visible: root.pluginApi?.scopeKind === "instance"','root.pluginApi?.tr("settings.shared-effect")'):anchors.require(codes[member+'/Settings.qml'],anchor,member+': shared-effect description')
        for locale,data in dictionaries[member].items():
            if not data.get('settings',{}).get('shared-effect','').strip():raise ValueError(member+': missing shared description '+locale)
        rows.append(dict(plugin=member,configuration=fields,protectedExternalOwners=['clipboard','pins','notecards','Todo'] if member=='clipper' else ['helper-settings','library','queue','playback'],legacyNonconsumer=['ytPlayerClient'] if member=='music-search' else []))
    for mapping in (READS,POLICY):
        for name,items in mapping.items():
            for anchor in items:anchors.require(codes[name],anchor,name+': '+anchor)
    for name,code in codes.items():
        raw=sources[name].encode();effects=Counter()
        for node in syntax.walk(trees[name].root_node):
            if node.type!='ui_object_definition':continue
            match=re.match(rb'(Process|Socket|IpcHandler|MediaPlayer|Video)\s*\{',raw[node.start_byte:node.end_byte].lstrip())
            if match:effects[match.group(1).decode()]+=1
        if dict(effects)!=EFFECTS.get(name,{}):raise ValueError(name+': unreviewed physical/helper owner '+repr(dict(effects)))
        if name in ('music-search/LauncherProvider.qml','music-search/MusicPreview.qml') and re.search(r'mainInstance\?\.(?:show\w+|preview\w+)',code):raise ValueError(name+': shared presentation reader')
        if name in ('music-search/Panel.qml','music-search/LauncherProvider.qml'):
            calls=list(re.finditer(r'mainInstance\?\.('+ '|'.join(sorted(ORIGIN))+r')\(([^;\n]*)',sources[name]))
            if len(calls)!=(10 if name.endswith('/Panel.qml') else 16):raise ValueError(name+': reviewed action callers changed')
            for match in calls:
                if 'settingsContext' not in match.group(2):raise ValueError(name+': omitted origin '+match.group(1))
        if name=='clipper/Panel.qml':
            if code.count('triggerAutoPaste(root.pluginApi.settingsView?.autoPasteDelay,root.pluginApi.settingsContext)')!=4:raise ValueError('Clipper: every paste caller must supply origin')
        if name.startswith('music-search/') and 'saveSettings(' in code and name not in ('music-search/Settings.qml','music-search/Panel.qml'):raise ValueError(name+': helper gained native preference writer')
    return rows


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--plugins',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);parser.add_argument('--selftest',action='store_true');args=parser.parse_args()
    sources={};manifests={};dictionaries={}
    for member in FIELDS:
        manifests[member]=json.loads((args.plugins/member/'manifest.json').read_text())
        dictionaries[member]={path.name:json.loads(path.read_text()) for path in (args.plugins/member/'i18n').glob('*.json')}
        sources.update({str(path.relative_to(args.plugins)):path.read_text() for path in (args.plugins/member).rglob('*.qml')})
    rows=check(sources,manifests,dictionaries);controls=[]
    if args.selftest:
        mutations=[('clipper/Main.qml','settings.enableTodoIntegration','pluginApi.settingsView.enableTodoIntegration','shared-todo-admission'),('clipper/Main.qml','root.selectionPolicy = policy','root.selectionPolicy = null','lost-selection-policy'),('clipper/Main.qml','root.todoSelectorPolicy?.context?.current()','true','retired-new-page'),('clipper/Main.qml','root.pastePolicy?.context?.current() && root.wtypeAvailable','root.wtypeAvailable','retired-paste'),('clipper/Main.qml','todoApi.pluginSettings.todos = todos','pluginApi.pluginSettings.todos = todos','wrong-content-writer'),('clipper/Panel.qml','root.pluginApi.settingsView?.autoPasteDelay, root.pluginApi.settingsContext','root.pluginApi.settingsView?.autoPasteDelay','omitted-paste-origin'),('clipper/ClipboardCard.qml','undefined, root.todoPolicy','root.pluginApi.settingsContext','recaptured-card-policy'),('music-search/Main.qml','entry: copyEntry(entry)','entry: entry','aliased-track'),('music-search/Main.qml','policy.autoSaveMp3AfterPlayback) {','root.autoSaveMp3AfterPlayback) {','shared-playback-policy'),('music-search/Main.qml','root.launchQueueEntry(root.queueEntries[0], undefined, root.queuePolicy)','root.launchQueueEntry(root.queueEntries[0])','queue-recapture'),('music-search/Main.qml','root.startQueue(undefined, root.autoplayPolicy)','root.startQueue()','saved-autoplay-recapture'),('music-search/Main.qml','!root.queueBatchPolicy?.context?.current()','false','retired-batch'),('music-search/Panel.qml','playEntry(normalized, root.pluginApi.settingsContext)','playEntry(normalized)','omitted-panel-origin'),('music-search/LauncherProvider.qml','cfg.showUploaderMetadata','mainInstance?.showUploaderMetadata','shared-launcher-presentation'),('music-search/MusicPreview.qml','cfg.showUploaderMetadata','detailCacheOwner?.mainInstance?.showUploaderMetadata','shared-preview-presentation'),('music-search/Main.qml','property var pluginApi: null','property var pluginApi: null\n Process {}','duplicate-helper-owner')]
        for name,old,new,label in mutations:
            if old not in sources[name]:raise RuntimeError('stale content control '+label)
            changed=dict(sources);changed[name]=changed[name].replace(old,new)
            try:check(changed,manifests,dictionaries)
            except ValueError as error:controls.append(dict(control=label,rejectedAt=str(error)))
            else:raise RuntimeError('content control escaped '+label)
        for member in FIELDS:
            changed=json.loads(json.dumps(manifests));changed[member]['entryPoints']['panel']='Unreviewed.qml'
            try:check(sources,changed,dictionaries)
            except ValueError as error:controls.append(dict(control='unreviewed-entry',plugin=member,rejectedAt=str(error)))
            else:raise RuntimeError('content entry escaped')
    args.report.write_text(json.dumps(dict(status='PASS',kind='finite-parsed-contract',members=rows,controls=controls,runtimeAcceptance=False,completeGroupAcceptance=False),indent=2)+'\n');print('CONTENT_GROUP_CHECK: PASS (%d members; %d controls)'%(len(rows),len(controls)))


if __name__=='__main__':main()
