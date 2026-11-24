#!/usr/bin/env python3
"""Finite G2 capture policy mappings, independent from runtime acceptance."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('capture_syntax', Path(__file__).with_name('plugin-settings-action-group-check.py'))
syntax = importlib.util.module_from_spec(spec)
spec.loader.exec_module(syntax)

MEMBERS = ('screen-recorder', 'screen-shot-and-record', 'screen-toolkit')
RECORDER_FIELDS = set('audioCodec audioSource colorRange copyToClipboard customFrameRate customReplayDuration directory filenamePattern frameRate hideInactive iconColor quality replayDuration replayEnabled replayStorage resolution restorePortalSession showCursor videoCodec videoSource'.split())
SHOT_FIELDS = set('enableCross enableWindowsSelection keepSourceScreenshot recordingNotifications recordingSavePath savePath screenshotEditor'.split())
TOOLKIT_FIELDS = set('filenameFormat gifMaxSeconds recordCopyToClipboard recordSkipConfirmation screenshotPath searchEngineUrl selectedOcrLang shareSkipPopover videoPath x02ApiKey x02Expiry'.split())
OPERATIONAL = set('colorHistory paletteColors installedLangs transAvailable detectedRecorder resultHex resultRgb resultHsv resultHsl colorCapturePath colorCacheBust ocrResult ocrCapturePath qrResult qrCapturePath translateResult'.split())
FIELDS = dict(zip(MEMBERS, (RECORDER_FIELDS, SHOT_FIELDS, TOOLKIT_FIELDS)))
ENTRIES = dict(main='Main.qml', barWidget='BarWidget.qml', settings='Settings.qml')
PROCESS_COUNTS = {
    'screen-recorder/Main.qml': 8,
    'screen-shot-and-record/Main.qml': 1, 'screen-shot-and-record/Panel.qml': 1,
    'screen-shot-and-record/ScreenShot.qml': 2, 'screen-shot-and-record/ScreenShotHypr.qml': 1, 'screen-shot-and-record/ScreenShotSway.qml': 1,
    'screen-toolkit/Main.qml': 9, 'screen-toolkit/overlays/Annotate.qml': 9,
    'screen-toolkit/overlays/Measure.qml': 1, 'screen-toolkit/overlays/Mirror.qml': 2,
    'screen-toolkit/overlays/Record.qml': 5, 'screen-toolkit/overlays/RegionSelector.qml': 2,
    'screen-toolkit/tools/ColorPicker.qml': 1, 'screen-toolkit/tools/Ocr.qml': 2,
    'screen-toolkit/tools/Qr.qml': 1, 'screen-toolkit/tools/Lens.qml': 1, 'screen-toolkit/tools/Palette.qml': 1,
    'screen-toolkit/widgets/ResultColor.qml': 1, 'screen-toolkit/widgets/ResultOcr.qml': 1,
    'screen-toolkit/widgets/ResultPalette.qml': 1, 'screen-toolkit/widgets/ResultQr.qml': 1,
    'screen-toolkit/utils/ToolProcess.qml': 1,
    'screen-toolkit/utils/TempPaths.qml': 1,
}
DETACHED = {'screen-recorder/Main.qml': 6, 'screen-shot-and-record/Main.qml': 1, 'screen-shot-and-record/ScreenShot.qml': 1, 'screen-shot-and-record/ScreenShotCaptureCommon.qml': 5}
ANCHORS = {
    'screen-recorder/Main.qml': [
        'recordingPolicy = policy', 'replayPolicy = policy', 'const settings = policy.settings', 'const settings = replayPolicy.settings',
        'if (!recordingPolicy?.context.current())', 'if (!replayPolicy?.context.current())', 'if (!policy?.context.current())',
        'policy.outputPath = outputPath', 'const completedPath = policy?.outputPath || ""', 'copyFileToClipboard(completedPath)',
        '() => { if (policy.context.current()) openFile(completedPath); }', '() => { if (policy.context.current()) openFile(savedPath); }',
        'copyFileToClipboard(savedPath)', 'buildResolutionFlag(settings)', 'var actualDuration = (replayDuration === "custom") ? customReplayDuration : replayDuration',
        'var actualFrameRate = (frameRate === "custom") ? customFrameRate : frameRate',
    ],
    'screen-recorder/BarWidget.qml': ['toggleRecording(pluginApi.settingsContext)', 'startReplay(pluginApi.settingsContext)', 'if (cfg.replayEnabled ?? defaults.replayEnabled ?? false)', 'cfg.iconColor', 'pluginApi?.pluginSettings?.hideInactive'],
    'screen-recorder/ControlCenterWidget.qml': ['toggleRecording(pluginApi.settingsContext)'],
    'screen-shot-and-record/Main.qml': [
        'return openAdmitted(target, capturePolicy(context))', 'root.recordingCheckPolicy = policy', 'const policy = root.recordingCheckPolicy',
        'requestedTarget === "" || !policy?.context.current()', 'root.stopRecording(policy.context, policy)',
        'root.openSelector(requestedTarget, policy)', 'root.selectorPolicy = policy', 'item.actionPolicy = root.selectorPolicy',
        'const policy = admitted || capturePolicy(context)', 'const recordingNotificationsEnabled = policy.settings.recordingNotifications',
    ],
    'screen-shot-and-record/Panel.qml': ['mainInstance?.capturePolicy(pluginApi?.settingsContext)', 'admittedPolicy = policy', 'mainInstance?.openAdmitted(target, admittedPolicy)', 'mainInstance?.stopRecording(pluginApi.settingsContext)'],
    'screen-shot-and-record/ScreenShot.qml': ['if (!actionPolicy?.context.current())', 'root.actionPolicy.settings.recordingNotifications', 'actionPolicy?.settings.enableCross'],
    'screen-shot-and-record/ScreenShotCaptureCommon.qml': ['if (!host.actionPolicy?.context.current()) return false', 'const settings = host.actionPolicy.settings'],
    'screen-shot-and-record/ScreenShotHypr.qml': ['actionPolicy?.settings.enableWindowsSelection'],
    'screen-shot-and-record/ScreenShotSway.qml': ['actionPolicy?.settings.enableWindowsSelection'],
    'screen-toolkit/Main.qml': [
        'const policy = capturePolicy(api?.settingsContext)', 'policy.api = api', 'timer.actionPolicy = policy', 'timer.actionPolicy = root.pendingPolicy',
        'root.pendingPolicy = policy', 'const policy = recordOverlay.actionPolicy', 'root.showResult(colorPickerOverlay.actionPolicy)',
        'root.showResult(ocrOverlay.actionPolicy)', 'root.showResult(qrOverlay.actionPolicy)', 'root.showResult(paletteOverlay.actionPolicy)',
        'annotateProc.actionPolicy = actionPolicy', 'annotateWinProc.actionPolicy = actionPolicy', 'pinGrimProc.actionPolicy = actionPolicy', 'pinFileProc.actionPolicy = actionPolicy',
        'annotateOverlay.parseAndShow(region, TempPaths.path("screen-toolkit-annotate.png"), screen, policy)',
        'root._regionScreen, actionPolicy', 'root.pendingRecordCursor, 0, 0, screen, actionPolicy',
        'measureOverlay.show(policy)', 'mirrorOverlay.show(screen, policy)', 'annotateOverlay.busy',
        'launchRecordFullscreen.actionPolicy = policy; root.isRunning = true; policy.api.withCurrentScreen(screen =>',
    ],
    'screen-toolkit/overlays/Record.qml': [
        'actionPolicy = policy', 'if (!policy?.context.current()) return false', 'if (!actionPolicy?.context.current())',
        'saveProc.actionPolicy = actionPolicy', 'var dir = U.videoDir(home, actionPolicy.settings.videoPath)',
        'actionPolicy.settings.filenameFormat', 'actionPolicy.settings.recordCopyToClipboard', 'actionPolicy.settings.recordSkipConfirmation',
        'actionPolicy?.settings.gifMaxSeconds', 'if (!root.actionPolicy?.context.current())',
        'root.recordState = ""; root.dismiss(); return',
    ],
    'screen-toolkit/overlays/Measure.qml': ['_shotPolicy = measureVariants.actionPolicy', 'var settings = overlayWin._shotPolicy.settings', 'if (!overlayWin._shotPolicy?.context.current())', 'overlayWin._shotPolicy === measureVariants.actionPolicy'],
    'screen-toolkit/overlays/Annotate.qml': [
        'if (busy || !policy?.context.current()) return false', 'readonly property bool busy: instances.some(window => window.operationBusy)',
        'root._primaryScreen, root.actionPolicy)', 'const policy = root.actionPolicy', 'var settings = policy.settings', 'var custom = actionPolicy?.settings.screenshotPath',
        'flattenForShareProc.actionPolicy = policy', 'uploadProc.actionPolicy = policy', 'saveFileProc.actionPolicy = policy',
        'copyProc.actionPolicy = policy', 'clipFlattenProc.actionPolicy = policy', 'zoomProc.actionPolicy = root.actionPolicy',
        'var apiKey = (policy.settings.x02ApiKey ?? "").trim()', 'var expiry = (policy.settings.x02Expiry ?? "7d").trim()',
        'var skipPop = actionPolicy.settings.shareSkipPopover ?? false', 'if (!policy.context.current())',
    ],
    'screen-toolkit/overlays/Mirror.qml': ['root._shotPolicy = actionPolicy', 'root._recordPolicy = actionPolicy', 'const policy = root._shotPolicy', 'const policy = root._recordPolicy', 'policy.settings.screenshotPath', 'policy.settings.videoPath', 'policy.settings.filenameFormat', 'if (!policy?.context.current())', 'if (!root._recordPolicy?.context.current()) return'],
}


def require(code, anchor, path):
    syntax.require(code, anchor, path + ': missing ' + anchor)


def check(sources, manifests, dictionaries):
    codes = {path: syntax.syntax.compact(text)[0] for path, text in sources.items()}
    rows = []
    for member in MEMBERS:
        fields = manifests[member]['metadata']['settingsSchema']['fields']
        if {key for key, value in fields.items() if value['editorUsage'] == 'configuration'} != FIELDS[member]: raise ValueError(member + ': configuration closure changed')
        if set(fields)-FIELDS[member] != (OPERATIONAL if member == 'screen-toolkit' else set()): raise ValueError(member + ': operational closure changed')
        if any(fields[key]['editorUsage'] != 'operational' for key in set(fields)-FIELDS[member]): raise ValueError(member + ': operational role changed')
        entries = dict(ENTRIES)
        if member != 'screen-shot-and-record': entries['controlCenterWidget'] = 'ControlCenterWidget.qml'
        if member != 'screen-recorder': entries['panel'] = 'Panel.qml'
        if manifests[member]['entryPoints'] != entries: raise ValueError(member + ': runtime entry closure changed')
        code = codes[member+'/Main.qml']
        for anchor in ('function capturePolicy(context)', 'context = context || pluginApi?.settingsContext', 'if (!context?.current()) return null', 'const settings = context.settingsView'): require(code, anchor, member)
        page = codes[member+'/Settings.qml']
        require(page, 'visible: root.pluginApi?.scopeKind === "instance"', member)
        require(page, 'root.pluginApi?.tr("settings.shared-effect")', member)
        for locale, dictionary in dictionaries[member].items():
            if not dictionary.get('settings', {}).get('shared-effect', '').strip(): raise ValueError(member+': missing shared-effect dictionary '+locale)
        field_rows = []
        for field in sorted(FIELDS[member]):
            if member == 'screen-recorder':
                path = member+('/BarWidget.qml' if field in ('hideInactive', 'iconColor') else '/Main.qml')
                anchor = 'pluginApi?.pluginSettings?.hideInactive' if field == 'hideInactive' else 'cfg.iconColor' if field == 'iconColor' else ('policy?.settings.copyToClipboard' if field == 'copyToClipboard' else 'settings.'+field)
            elif member == 'screen-shot-and-record':
                child = 'ScreenShot.qml' if field == 'enableCross' else 'ScreenShotHypr.qml' if field == 'enableWindowsSelection' else 'ScreenShotCaptureCommon.qml'
                path = member+'/'+child; anchor = ('actionPolicy?.settings.' if field in ('enableCross', 'enableWindowsSelection') else 'settings.')+field
            else:
                child = 'Panel.qml' if field == 'selectedOcrLang' else 'widgets/ResultOcr.qml' if field == 'searchEngineUrl' else 'overlays/Record.qml' if field in ('gifMaxSeconds', 'recordCopyToClipboard', 'recordSkipConfirmation', 'videoPath') else 'overlays/Annotate.qml'
                path = member+'/'+child
                anchor = 'pluginSettings.selectedOcrLang' if field == 'selectedOcrLang' else 'pluginSettings?.searchEngineUrl' if field == 'searchEngineUrl' else 'settings.'+field
                if field in ('gifMaxSeconds', 'filenameFormat'): anchor = 'settings.'+field if field == 'gifMaxSeconds' else 'settings?.filenameFormat'
            require(codes[path], anchor, path)
            field_rows.append(dict(field=field, consumer=path, read=anchor))
        rows.append(dict(plugin=member, fields=field_rows, operational=sorted(set(fields)-FIELDS[member]), entries=entries))
    for path, code in codes.items():
        raw=sources[path].encode(); tree=syntax.syntax.compact(sources[path])[1]
        processes=sum(node.type=='ui_object_definition' and bool(re.match(rb'(?:ToolProcess|Process)\s*\{',raw[node.start_byte:node.end_byte])) for node in syntax.syntax.walk(tree.root_node))
        if processes != PROCESS_COUNTS.get(path,0): raise ValueError(path+': physical/process owner closure changed')
        if code.count('execDetached(') != DETACHED.get(path,0): raise ValueError(path+': detached effect closure changed')
        # A view/page cannot construct a second Main or physical overlay owner.
        if not path.endswith('/Main.qml') and re.search(r'(?<![\w])(?:Main|Record|Mirror|Measure|Annotate|ColorPicker|Ocr|Qr|Lens|Palette)\{',code): raise ValueError(path+': second effect owner')
        if path.startswith('screen-toolkit/') and ('/overlays/' in path or '/tools/' in path):
            for field in TOOLKIT_FIELDS:
                if re.search(r'pluginSettings(?:\?\.|\.)'+field+r'\b',code): raise ValueError(path+': shared configuration reader '+field)
        if not path.endswith('/Main.qml'):
            for match in re.finditer(r'(?:\?\.|\.)(toggleRecording|startReplay|runColorPicker|runOcr|runQr|runLens|runAnnotate|runAnnotateFullscreen|runAnnotateActiveWindow|runPalette|runPin|runPinFromFile|runMeasure|runRecord|runRecordFullscreen|runMirror)\(([^()]*)\)',code):
                method,args=match.groups()
                wanted='pluginApi.settingsContext' if method in ('toggleRecording','startReplay') else 'api' if path.endswith('/overlays/Annotate.qml') else 'pluginApi'
                if args.split(',')[-1] != wanted: raise ValueError(path+': omitted/shared originating caller '+method)
        if 'writer.pluginSettings' in code or 'policy.api.pluginSettings' in code or 'actionPolicy.api.pluginSettings' in code: raise ValueError(path+': configuration capture gained a writer')
        for key in re.findall(r'pluginSettings(?:\?\.|\.)(\w+)=(?!=)',code):
            allowed=OPERATIONAL if path.startswith('screen-toolkit/') else set()
            if key not in allowed and not (path=='screen-toolkit/Panel.qml' and key=='selectedOcrLang'): raise ValueError(path+': shared/unreviewed capture writer '+key)
    for path, anchors in ANCHORS.items():
        for anchor in anchors: require(codes[path],anchor,path)
    main=codes['screen-toolkit/Main.qml']
    if main.count('propertyvaractionPolicy:null') != 17: raise ValueError('Toolkit: delayed process/timer policy closure changed')
    for tool in ('ColorPicker','Ocr','Qr','Lens','Palette'):
        code=codes['screen-toolkit/tools/'+tool+'.qml']
        require(code,'actionPolicy = policy',tool); require(code,'if (!root.actionPolicy?.context.current())',tool)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugins', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--selftest', action='store_true')
    args = parser.parse_args()
    sources = {str(path.relative_to(args.plugins)): path.read_text() for member in MEMBERS for path in (args.plugins/member).rglob('*.qml')}
    manifests = {member: json.loads((args.plugins/member/'manifest.json').read_text()) for member in MEMBERS}
    dictionaries = {member: {path.name:json.loads(path.read_text()) for path in (args.plugins/member/'i18n').glob('*.json')} for member in MEMBERS}
    members = check(sources, manifests, dictionaries); controls=[]
    if args.selftest:
        mutations=[
            ('screen-recorder/BarWidget.qml','toggleRecording(pluginApi.settingsContext)','toggleRecording()','omitted-recorder'),
            ('screen-recorder/Main.qml','const settings = context.settingsView','const settings = pluginApi.pluginSettings','shared-recorder'),
            ('screen-recorder/Main.qml','copyFileToClipboard(completedPath)','copyFileToClipboard(outputPath)','late-recording-path'),
            ('screen-shot-and-record/Panel.qml','capturePolicy(pluginApi?.settingsContext)','capturePolicy()','omitted-panel'),
            ('screen-shot-and-record/Main.qml','item.actionPolicy = root.selectorPolicy','item.actionPolicy = null','missing-child-policy'),
            ('screen-shot-and-record/ScreenShotCaptureCommon.qml','const settings = host.actionPolicy.settings','const settings = host.pluginApi.pluginSettings','shared-selector'),
            ('screen-toolkit/Panel.qml','runMeasure(pluginApi)','runMeasure()','omitted-toolkit'),
            ('screen-toolkit/Main.qml','timer.actionPolicy = root.pendingPolicy','timer.actionPolicy = null','missing-launch-policy'),
            ('screen-toolkit/overlays/Measure.qml','var settings = overlayWin._shotPolicy.settings','var settings = measureVariants.actionPolicy.settings','measure-replacement'),
            ('screen-toolkit/overlays/Annotate.qml','root._primaryScreen, root.actionPolicy)','root._primaryScreen)','zoom-caller'),
            ('screen-toolkit/overlays/Mirror.qml','policy.settings.videoPath','pluginApi.pluginSettings.videoPath','shared-mirror'),
            ('screen-toolkit/overlays/Record.qml','saveProc.actionPolicy = actionPolicy','saveProc.actionPolicy = null','record-completion-policy'),
            ('screen-toolkit/tools/Ocr.qml','!root.actionPolicy?.context.current()','!root.actionPolicy','retired-result'),
            ('screen-toolkit/overlays/Mirror.qml','!root._recordPolicy?.context.current()','!root._recordPolicy','retired-mirror-completion'),
            ('screen-toolkit/Main.qml','launchRecordFullscreen.actionPolicy = policy\n        root.isRunning = true','launchRecordFullscreen.actionPolicy = policy','overwritten-screen-admission'),
            ('screen-toolkit/BarWidget.qml','property var pluginApi: null','property var pluginApi: null\n Process { command: ["true"] }','second-owner'),
        ]
        mutations += [(member+'/Main.qml','if (!context?.current()) return null','if (!context) return null',member+'-retirement') for member in MEMBERS]
        mutations += [(member+'/Main.qml','const settings = context.settingsView','pluginApi.pluginSettings.opaque = "wrong"; const settings = context.settingsView',member+'-shared-writer') for member in MEMBERS]
        for path,old,new,label in mutations:
            if old not in sources[path]: raise RuntimeError('stale capture canary '+label)
            changed=dict(sources); changed[path]=sources[path].replace(old,new)
            try: check(changed,manifests,dictionaries)
            except ValueError as error: controls.append(dict(control=label,rejectedAt=str(error)))
            else: raise RuntimeError('capture canary escaped '+label)
        # Every declared configuration leaf has an independent rejecting read
        # mapping, not merely one representative token per Main.
        for member in members:
            for field in member['fields']:
                path, old = field['consumer'], field['read']
                if old not in sources[path]: raise RuntimeError('stale field canary '+field['field'])
                changed=dict(sources); changed[path]=sources[path].replace(old,'unreviewedCapturePolicy.'+field['field'])
                try: check(changed,manifests,dictionaries)
                except ValueError as error: controls.append(dict(control=member['plugin']+'-'+field['field']+'-reader',rejectedAt=str(error)))
                else: raise RuntimeError('field reader canary escaped '+field['field'])
        for member in MEMBERS:
            changed=json.loads(json.dumps(manifests)); changed[member]['entryPoints']['barWidget']='Unreviewed.qml'
            try: check(sources,changed,dictionaries)
            except ValueError as error: controls.append(dict(control=member+'-entry',rejectedAt=str(error)))
            else: raise RuntimeError('capture entry canary escaped')
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-contract', members=members, controls=controls, runtimeAcceptance=False, completeGroupAcceptance=False),indent=2)+'\n')
    print('PLUGIN_SETTINGS_CAPTURE_GROUP_CHECK: PASS')


if __name__ == '__main__':
    main()
