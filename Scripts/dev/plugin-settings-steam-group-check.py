#!/usr/bin/env python3
"""Finite parsed Steam fields, originating entries, retained stages and sole owner."""
import argparse
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import re

spec=importlib.util.spec_from_file_location('steam_syntax',Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
spec=importlib.util.spec_from_file_location('steam_anchors',Path(__file__).with_name('plugin-settings-action-group-check.py'))
anchors=importlib.util.module_from_spec(spec);spec.loader.exec_module(anchors)
FIELDS={'autoLaunchSteam','chatWidth','chatWidthPercent','enableChatNotifications','friendsWidth','friendsWidthPercent','gapSize','mainWidth','mainWidthPercent','topMarginPercent','useCustomLayout','windowHeightPercent'}
GEOMETRY={'gapSize':'int','topMarginPercent':'real','windowHeightPercent':'real','friendsWidthPercent':'real','mainWidthPercent':'real','chatWidthPercent':'real','useCustomLayout':'bool'}
STAGES={'detectWindows','detectAllWindows','moveAllWindows','moveWindows','showWorkspace','hideWorkspace','focusAdditionalWindows','executeFocus','detectNewWindows','moveNewWindows'}
MAIN=[
 'context = context || pluginApi?.settingsContext','values: context.settingsView','screenWidth: screenWidth, screenHeight: screenHeight, luaMode: luaMode',
 'return !_retired && policy && policy === _overlayPolicy && policy.current',
 'readonly property bool _policyCurrent: !_retired && (_overlayPolicy?.current ?? false)',
 'on_PolicyCurrentChanged: { if (!_policyCurrent) stopPolicy(); }',
 'Component.onDestruction: { _retired = true; stopPolicy(); }',
 'if (_retired || !context?.current() || _opening) return false','_overlayPolicy = capturePolicy(context)',
 'if (previous) previous.destroy()','detectWindows.policy = policy',
 'readonly property bool _observationsReady: luaModeProbed && resolutionProbed',
 'if (!policyCurrent(policy) || !_opening || !_observationsReady || overlayActive) return',
 'policy.screenWidth = screenWidth','policy.screenHeight = screenHeight','policy.luaMode = luaMode',
 'on_ObservationsReadyChanged: { if (_observationsReady) beginOpening(_overlayPolicy); }',
 'onExited: root.resolutionProbed = true','beginOpening(_overlayPolicy)',
 'detectAllWindows.policy = admitted','moveAllWindows.policy = admitted','moveWindows.policy = policy',
 'showWorkspace.policy = policy','hideWorkspace.policy = policy','focusAdditionalWindows.policy = admitted',
 'executeFocus.policy = admitted','detectNewWindows.policy = root._overlayPolicy','moveNewWindows.policy = admitted',
 'if (!root.policyCurrent(admitted)) { lines = []; return; }',
 'if (!root.policyCurrent(admitted)) { allSteamWindows = []; return; }',
 'if (!root.policyCurrent(admitted) || !overlayActive) { addresses = []; return; }',
 'if (!root.policyCurrent(admitted) || !overlayActive) { windowData = []; return; }',
 'if (!root.policyCurrent(admitted) || !overlayActive) return',
 'if (!root.policyCurrent(admitted)) return','if (!root.policyCurrent(policy)) return',
 'running: overlayActive && root._policyCurrent && !root._opening',
 'admitted.screenWidth * 0.30','admitted.screenHeight * 1.0',
 'root.doShowWorkspace(admitted)','moveWindowsToOverlay(admitted)',
 'var x = 0, y = policy.topMargin, w = 800, h = policy.windowHeight',
 'x = policy.centerOffset + policy.friendsWidth + policy.gapSize','w = policy.mainWidth',
 'x = policy.centerOffset','w = policy.friendsWidth','w = policy.chatWidth',
 'x = policy.centerOffset + policy.friendsWidth + policy.gapSize + policy.mainWidth + policy.gapSize',
 'root.hdResize(w, h, addr, policy)','root.hdMovePixel(x, y, addr, policy)',
 'root.hdMoveToSpecial(addr, admitted)','root.hdSetFloating(addr, admitted)','root.hdAlterTop(addr, admitted)',
 'function toggle() { root.toggleOverlay(); }']


def check(sources,manifest,dictionaries):
    metadata=manifest['metadata']['settingsSchema']['fields']
    if set(metadata)!=FIELDS or any(row['editorUsage']!='configuration' for row in metadata.values()):raise ValueError('Steam field ownership changed')
    if manifest['entryPoints']!=dict(main='Main.qml',barWidget='BarWidget.qml',panel='Panel.qml',settings='Settings.qml'):raise ValueError('unreviewed Steam entry')
    codes={};trees={}
    for name,text in sources.items():codes[name],trees[name]=syntax.compact(text)
    for anchor in MAIN:anchors.require(codes['Main.qml'],anchor,'Main: '+anchor)
    for key,kind in GEOMETRY.items():
        anchors.require(codes['OverlayPolicy.qml'],'readonly property '+kind+' '+key+': values.'+key+' ?? defaults.'+key,'typed admitted field '+key)
    for anchor in ('required property var context','required property var values','readonly property bool current: context?.current() ?? false','screenWidth * friendsWidthPercent / 100 - gapSize','screenWidth * mainWidthPercent / 100 - gapSize * 2','screenWidth * chatWidthPercent / 100 - gapSize','(screenWidth - friendsWidth - gapSize - mainWidth - gapSize - chatWidth) / 2'):
        anchors.require(codes['OverlayPolicy.qml'],anchor,'immutable geometry '+anchor)
    if codes['BarWidget.qml'].count('pluginApi.mainInstance.toggleOverlay(pluginApi.settingsContext)')!=2:raise ValueError('missing originating Bar caller')
    for key in ('friendsWidth','mainWidth','chatWidth'):
        anchors.require(codes['Panel.qml'],'pluginApi?.pluginSettings?.'+key,'selected guide '+key)
    for anchor in ('visible: root.pluginApi?.scopeKind === "instance"','root.pluginApi?.tr("settings.shared-effect")'):
        anchors.require(codes['Settings.qml'],anchor,'shared effect UI')
    for locale,data in dictionaries.items():
        if not data.get('settings',{}).get('shared-effect','').strip():raise ValueError('missing shared-effect '+locale)
    main=codes['Main.qml']
    if 'pluginSettings' in main:raise ValueError('shared live Main policy')
    if any(key in main for key in ('autoLaunchSteam','enableChatNotifications')):raise ValueError('unreviewed feature implementation')
    for name,code in codes.items():
        effects=[];raw=sources[name].encode()
        for node in syntax.walk(trees[name].root_node):
            if node.type!='ui_object_definition':continue
            text=raw[node.start_byte:node.end_byte].decode();match=re.match(r'(Process|Socket|Loader|IpcHandler|NotificationServer|Video)\s*\{',text.lstrip())
            if match:
                effects.append(match[1])
                if name=='Main.qml' and match[1]=='Process':
                    identifier=re.search(r'\bid:\s*(\w+)',text)[1]
                    if identifier in STAGES:
                        if not re.search(r'property\s+var\s+policy\s*:',text):raise ValueError('uncaptured Process '+identifier)
        expected=['Process']*14+['IpcHandler'] if name=='Main.qml' else ['Process'] if name=='BarWidget.qml' else []
        if sorted(effects)!=sorted(expected):raise ValueError('changed sole owner '+name+repr(effects))
        if 'execDetached(' in code or re.search(r'(?:root\.)?pluginApi=',code):raise ValueError('detached owner or replaced API '+name)
        if re.search(r'pluginSettings\s*(?:\[|=)',code) or 'saveSettings(' in code and name!='Settings.qml':raise ValueError('new Steam preference writer')
    stop=main[main.index('functionstopPolicy('):main.index('on_PolicyCurrentChanged:')]
    for stage in STAGES:anchors.require(stop,stage,'cancel '+stage)
    if 'pluginApi' in codes['OverlayPolicy.qml']:raise ValueError('policy acquired consumer API')
    if main.count('returnpolicy.luaMode')!=6:raise ValueError('dispatch syntax not admitted in every builder')
    return dict(configuration=sorted(FIELDS),selectedGeometry=sorted(GEOMETRY),selectedGuide=['friendsWidth','mainWidth','chatWidth'],unusedPreserved=['autoLaunchSteam','enableChatNotifications'],stages=sorted(STAGES),physicalOwners=1)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--plugins',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);parser.add_argument('--selftest',action='store_true');args=parser.parse_args()
    root=args.plugins/'hyprland-steam-overlay';sources={p.name:p.read_text() for p in root.glob('*.qml')};manifest=json.loads((root/'manifest.json').read_text());dictionaries={p.name:json.loads(p.read_text()) for p in (root/'i18n').glob('*.json')}
    result=check(sources,manifest,dictionaries);controls=[]
    if args.selftest:
        mutations=[('Main.qml','values: context.settingsView','values: pluginApi.pluginSettings','shared-admission'),
         ('BarWidget.qml','toggleOverlay(pluginApi.settingsContext)','toggleOverlay()','omitted-origin'),
         ('OverlayPolicy.qml','readonly property int gapSize','readonly property real gapSize','lost-int-conversion'),
         ('OverlayPolicy.qml','values.mainWidthPercent ?? defaults.mainWidthPercent','defaults.mainWidthPercent','lost-main-width'),
         ('Main.qml','detectAllWindows.policy = admitted','detectAllWindows.policy = null','lost-query-policy'),
         ('Main.qml','moveWindows.policy = policy','moveWindows.policy = null','lost-move-policy'),
         ('Main.qml','showWorkspace.policy = policy','showWorkspace.policy = null','lost-show-policy'),
         ('Main.qml','focusAdditionalWindows.policy = admitted','focusAdditionalWindows.policy = null','lost-focus-policy'),
         ('Main.qml','detectNewWindows.policy = root._overlayPolicy','detectNewWindows.policy = root.capturePolicy()','recaptured-monitor'),
         ('Main.qml','moveNewWindows.policy = admitted','moveNewWindows.policy = null','lost-continuing-policy'),
         ('Main.qml','return policy.luaMode','return root.luaMode','recaptured-syntax'),
         ('Main.qml','w = policy.mainWidth','w = root.mainWidth','shared-main-width'),
         ('Main.qml','if (!root.policyCurrent(admitted)) return','if (false) return','retired-continuation'),
         ('Main.qml','overlayActive && root._policyCurrent','overlayActive && true','retired-monitor'),
         ('Main.qml','_opening) return false','false) return false','overlapping-opening'),
         ('Main.qml','!_observationsReady || overlayActive','false || overlayActive','unready-observation-policy'),
         ('Main.qml','executeFocus, detectNewWindows','executeFocus','uncancelled-query'),
         ('Panel.qml','pluginApi?.pluginSettings?.friendsWidth','pluginApi?.mainInstance?.friendsWidth','shared-guide'),
         ('OverlayPolicy.qml','required property var values','required property var values\n Process {}','duplicate-owner')]
        for name,old,new,label in mutations:
            if old not in sources[name]:raise RuntimeError('stale Steam control '+label)
            altered=dict(sources);altered[name]=altered[name].replace(old,new)
            try:check(altered,manifest,dictionaries)
            except ValueError as error:controls.append(dict(control=label,rejectedAt=str(error)))
            else:raise RuntimeError('Steam control escaped '+label)
        changed=deepcopy(manifest);changed['metadata']['settingsSchema']['fields']['autoLaunchSteam']['editorUsage']='operational'
        try:check(sources,changed,dictionaries)
        except ValueError as error:controls.append(dict(control='reclassified-unused-configuration',rejectedAt=str(error)))
        else:raise RuntimeError('reclassified unused configuration escaped')
    args.report.write_text(json.dumps(dict(status='PASS',kind='finite-parsed-contract',member=result,controls=controls,runtimeAcceptance=False),indent=2)+'\n')
    print('STEAM_GROUP_CHECK: PASS (%d fields; %d controls)'%(len(FIELDS),len(controls)))


if __name__=='__main__':main()
