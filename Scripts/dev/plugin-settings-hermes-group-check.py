#!/usr/bin/env python3
"""Finite parsed Hermes field, caller, session and resource ownership contract."""
import argparse
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import re
from fixture_evidence import require

spec=importlib.util.spec_from_file_location('hermes_syntax',Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
FIELDS={
    'bridgeHost':('Main.qml','String(cfg.bridgeHost ?? defaults.bridgeHost ?? "127.0.0.1")'),
    'bridgePort':('HermesClient.qml','readonly property int bridgePort: remote ? (cfg.bridgePort ?? defaults.bridgePort ?? 19777) : (defaults.bridgePort ?? 19777)'),
    'stateFile':('Main.qml','expandHome(String(cfg.stateFile ?? defaults.stateFile ?? "~/.cache/noctalia-hermes/state.json"))'),
    'hermesHome':('Main.qml','expandHome(String(cfg.hermesHome ?? defaults.hermesHome ?? "~/.hermes"))'),
    'hermesCommand':('Main.qml','String(cfg.hermesCommand ?? defaults.hermesCommand ?? "hermes")'),
    'autoStartBridge':('Main.qml','Boolean(cfg.autoStartBridge ?? defaults.autoStartBridge ?? true)'),
    'autoStartGateway':('Main.qml','Boolean(cfg.autoStartGateway ?? defaults.autoStartGateway ?? true)'),
    'clientOnlyMode':('HermesClient.qml','readonly property bool remote: cfg.clientOnlyMode ?? defaults.clientOnlyMode ?? false'),
    'bridgeTokenManual':('Main.qml','remote ? String(cfg.bridgeTokenManual ?? defaults.bridgeTokenManual ?? "") : ""'),
    'statusPollIntervalSec':('HermesClient.qml','readonly property int pollSeconds: cfg.statusPollIntervalSec ?? defaults.statusPollIntervalSec ?? 30'),
    'hideWhenIdle':('HermesClient.qml','readonly property bool hideWhenIdle: cfg.hideWhenIdle ?? defaults.hideWhenIdle ?? false'),
    'launcherPrefix':('HermesClient.qml','readonly property string launcherPrefix: cfg.launcherPrefix ?? defaults.launcherPrefix ?? ">hermes"'),
    'panelPinned':('HermesClient.qml','readonly property bool panelPinned: cfg.panelPinned ?? defaults.panelPinned ?? false'),
    'showToolActivity':('HermesClient.qml','readonly property bool showToolActivity: cfg.showToolActivity ?? defaults.showToolActivity ?? false'),
    'defaultProvider':('Main.qml','String(cfg.defaultProvider ?? defaults.defaultProvider ?? "")'),
    'defaultModel':('Main.qml','String(cfg.defaultModel ?? defaults.defaultModel ?? "")'),
}
ANCHORS={
    'Main.qml':[
        'property var _settingsConsumers: new Map()', '_settingsConsumers.has(context)',
        'if (retired || !context?.current()) return null',
        'requestedContext = policy.context', 'sourceKey(policy) === sourceKey(appliedPolicy)',
        'pendingBoundary = {path:path,payload:payload,policy:policy}',
        'retiringConnection.retireConnection()', 'if (!policy?.context.current() || retiringConnection) return false',
        'if (!boundary || !active?.ready || !boundary.policy.context.current()) return',
        'if (!life.alive || root.pendingBoundary !== boundary) return',
        'active.policy.remote || active.policy.context !== api?.settingsContext',
        'if (!life.alive || root.connection !== active || !data || !api.settingsContext.current()) return',
        'api.saveSettings()', 'pluginApi: root.pinnedPanelApi',
        'function openPreferredPanel(screen, buttonItem, runtimeApi)',
        'root.pinnedPanelApi = api', '_lifetime.alive = false',
        'if (!request || activeModel || pendingBoundary || !active?.ready || !request.policy.context.current() || sourceKey(request.policy) !== sourceKey(appliedPolicy)) return',
        'if (!life.alive || root.connection !== active || root.activeModel !== request) return',
        'if (root.pendingModel) root.flushModel()',
    ],
    'HermesConnection.qml':[
        'readonly property bool current: !retired && policy.context.current()',
        'const life = _lifetime', 'const generation = tokenGeneration',
        'if (xhr.readyState !== XMLHttpRequest.DONE || !life.alive) return',
        'if (!root.current || (credentialBound && generation !== root.tokenGeneration)) return',
        'if (!context.current()) { if (settled) settled(null); return; }',
        'const credentialBound = path !== "/health" && path !== "/detect"',
        'xhr.setRequestHeader("X-Bridge-Token", token)',
        'request.xhr.onreadystatechange = null; request.xhr.abort()',
        '"--state-file",policy.stateFile,"--hermes-home",policy.hermesHome,"--hermes-command",policy.command',
        'root.current && !root.policy.remote ? root.policy.stateFile : ""',
        'if (!root.current || root.policy.remote) return',
        'root.tokenGeneration++; root.localToken = value; root.cancelRequests(true, true)',
        'interval: root.sessionRunning ? 1500 : root.policy.pollSeconds * 1000',
        'interval: 500', 'attempts > 20', 'sequence === root.stateRequest',
    ],
    'HermesClient.qml':['readonly property var cfg: settingsContext.settingsView','interval: client.pollSeconds * 1000','running: client.current','client.retire(client)'],
    'Settings.qml':[
        'root.mainInstance?.applySettings(root.pluginApi.runtimeContext, trim)',
        'result.refreshState !== "current"', 'pluginApi?.tr("settings.sharedEffect")',
        'pluginApi?.tr("settings.pendingRestart")',
        'if (!life.alive || xhr.readyState !== XMLHttpRequest.DONE)',
        'generation !== root._probeGeneration || root._probe !== xhr',
        'readonly property string valueDefaultModel: root.defaultModelField?.value ?? ""',
    ],
    'BarWidget.qml':[
        'settingsConsumerFor(pluginApi?.settingsContext)',
        'mainInstance.openPreferredPanel(root.screen, root, pluginApi)',
        'mainInstance?.createSession(pluginApi.settingsContext)',
        'mainInstance?.interrupt(pluginApi.settingsContext)',
        'mainInstance?.refreshState(pluginApi.settingsContext)',
        'mainInstance?.startGateway(pluginApi.settingsContext)',
    ],
    'Panel.qml':[
        'settingsConsumerFor(pluginApi?.settingsContext)',
        'sendPrompt(text, pluginApi?.settingsContext)',
        'api.pluginSettings.panelPinned = value', 'api.saveSettings(function(result)',
        'setPinnedPanelRequested(value, api)',
        'if (!life.alive || !api?.settingsContext.current()) return',
        'resumeSession(sid, pluginApi?.settingsContext)',
        'respondApproval("approved", all, pluginApi?.settingsContext)',
        'respondApproval("denied", false, pluginApi?.settingsContext)',
    ],
    'LauncherProvider.qml':[
        'settingsConsumerFor(pluginApi?.settingsContext)',
        'mainInstance.openPreferredPanel(null, null, pluginApi)',
        'life.alive && api?.settingsContext.current() && owner?.oneShot(content, api.settingsContext)',
        'owner?.createSession(api.settingsContext)', 'owner?.resumeSession(storedId, api.settingsContext)',
    ],
    'PinnedPanelWindow.qml':['pluginApi: root.pluginApi'],
}


def check(sources,manifest,words):
    fields=manifest['metadata']['settingsSchema']['fields']
    require(set(fields)==set(FIELDS)|{'configured'}, 'Hermes settings fields')
    require(fields['configured']['editorUsage']=='operational', 'Hermes configured flag is operational')
    require(all(fields[key]['editorUsage']=='configuration' for key in FIELDS), 'Hermes configuration usage')
    require(manifest['entryPoints']==dict(main='Main.qml',barWidget='BarWidget.qml',panel='Panel.qml',launcherProvider='LauncherProvider.qml',settings='Settings.qml'), 'Hermes entry points')
    code={name:syntax.compact(text)[0] for name,text in sources.items()}
    for key,(name,anchor) in FIELDS.items():
        syntax.require(code[name],anchor,key+': selected field')
        syntax.require(code['Settings.qml'],'pluginApi?.field("'+key+'")',key+': page field')
    for name,anchors in ANCHORS.items():
        for anchor in anchors:syntax.require(code[name],anchor,name+': '+anchor)
    require(sum(len(re.findall(r'\bProcess\s*\{',value)) for value in code.values())==1, 'single managed bridge Process')
    require(not re.search(r'\bsetPinnedPanelRequested\s*\(',code['Settings.qml']), 'page cannot borrow shared pin API')
    require(all(words['settings'][key] for key in ('sharedEffect','pendingRestart')), 'Hermes shared effect and restart explanations')
    return dict(configuration=sorted(FIELDS),protected=['configured'],managedOwner='HermesConnection.qml',sharedChatOwner='Main.qml')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugins',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);parser.add_argument('--selftest',action='store_true')
    args=parser.parse_args();root=args.plugins/'hermes-agent'
    sources={name:(root/name).read_text() for name in ANCHORS}
    manifest=json.loads((root/'manifest.json').read_text());words=json.loads((root/'i18n/en.json').read_text())
    member=check(sources,manifest,words);controls=[]
    if args.selftest:
        mutations=[(name,anchor,'false','field-'+key) for key,(name,anchor) in FIELDS.items()]
        mutations += [(name,anchor,'false','contract-'+str(i)) for i,(name,anchor) in enumerate([
            ('Main.qml','sourceKey(policy) === sourceKey(appliedPolicy)'),
            ('Main.qml','retiringConnection.retireConnection()'),
            ('HermesConnection.qml','generation !== root.tokenGeneration'),
            ('HermesConnection.qml','request.xhr.abort()'),
            ('Settings.qml','root.pluginApi.runtimeContext'),
            ('Panel.qml','api.pluginSettings.panelPinned = value'),
            ('LauncherProvider.qml','owner?.oneShot(content, api.settingsContext)'),
        ])]
        for name,old,new,label in mutations:
            candidate=deepcopy(sources)
            tokens=re.findall(r'"(?:[^"\\]|\\.)*"|\x27(?:[^\x27\\]|\\.)*\x27|[^\s]',old)
            candidate[name],count=re.subn(r'\s*'.join(re.escape(token) for token in tokens),lambda _:new,candidate[name],count=1)
            require(count==1, label+' mutation anchor')
            try:check(candidate,manifest,words)
            except (ValueError,AssertionError):controls.append(label)
            else:raise AssertionError('Hermes control escaped '+label)
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(dict(status='PASS',member=member,controls=controls,generalJavaScriptProof=False),indent=2)+'\n')
    print('HERMES_GROUP: PASS '+str(len(controls))+' controls')


if __name__=='__main__':main()
