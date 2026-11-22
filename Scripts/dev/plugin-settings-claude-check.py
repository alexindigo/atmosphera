#!/usr/bin/env python3
"""Finite Claude fields, serial ACP/session/permission ownership and entry contract."""
import argparse
import importlib.util
import json
import re
from pathlib import Path
spec=importlib.util.spec_from_file_location('claude_syntax',Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
def require(code,anchor,message):
    # Match parsed tokens while retaining whitespace inside literal strings.
    parts=re.findall(r'"(?:[^"\\]|\\.)*"|\x27(?:[^\x27\\]|\\.)*\x27|[^\s;]',anchor)
    if ''.join(parts) not in code:raise ValueError(message)
CONFIG=['claude','maxHistoryLength','attachmentStyle','panelDetached','panelHeightRatio','panelPosition','panelWidth','scale']
ANCHORS={
 'Main.qml':['property var _settingsConsumers: new Map()', '_settingsConsumers.has(context)', 'settingsContext: context', '_settingsConsumers.set(context, client)',
  'root.retireRequests(retired); root._settingsConsumers.delete(context); retired.destroy()',
  'settingsConsumerFor(context === undefined ? pluginApi?.settingsContext : context)', 'var policy = _consumer(context)?.capture()',
  '_pendingPrompts.filter(request => request.policy.context !== client.settingsContext)', 'if (acpProcess?.policy.context === client.settingsContext)',
  '_saveHistoryLength = client.maxHistoryLength', 'var maxHistory = _saveHistoryLength',
  'return worker && acpProcess === worker && !worker.cancelled && _policyCurrent(worker.policy)',
  'policy.context.current() && _consumer(policy.context)?.identity === policy.identity',
  'processFactory.createObject(root, {policy: policy, workingDirectory: cwd, command: [root.resolvedBinaryPath]',
  'if (life.alive && root._acpCurrent(source)) root._sendInitialize()',
  'if (life.alive && root._acpCurrent(source)) root._onAcpLine(line)',
  'if (life.alive && root._acpCurrent(source)) root._onAcpExited(code)',
  'acpProcess = null', 'worker.cancel(); worker.destroy()', 'Component.onDestruction: _lifetime.alive = false',
  '"Failed to start claude-code-acp (code "', 'if (!root.isManuallyStopped && code !== 0)',
  'acpProcess.policy.workingDir ? Logic.expandHome(acpProcess.policy.workingDir, home) : home',
  'if (params.sessionId !== root.sessionId) return',
  'params.sessionId !== sessionId) return false',
  'rpcId: rpcId, options: options, worker: acpProcess, sessionId: sessionId',
  'pending.worker !== acpProcess || !_acpCurrent(pending.worker) || pending.sessionId !== sessionId',
  '_acpWrite(Logic.makeAcpResponse(pending.rpcId, result))',
  'Object.freeze({text: text, policy: policy})', 'var request = _pendingPrompts[0]',
  'acpProcess.policy.context !== request.policy.context || acpProcess.policy.identity !== request.policy.identity',
  '_dispatchPrompt(request)', 'Logic.firstTurnPrefix(request.policy.claude)',
  'originApi = originApi === undefined ? pluginApi : originApi',
  'originApi?.settingsContext?.current()', 'Object.assign({}, originApi.pluginSettings.claude || {})',
  'originApi.pluginSettings.claude = next', 'originApi.saveSettings()',
  'setClaudeField("workingDir", rest, originApi)', 'setClaudeField("model", rest, originApi)',
  'root.sendMessage(message)', 'root.setClaudeField("workingDir", path || "")', '["which", "claude-code-acp"]'],
 'ClaudeSettingsClient.qml':['required property var settingsContext', 'readonly property var cfg: settingsContext.settingsView',
  'cfg.claude || ({})','cfg.maxHistoryLength || 200','readonly property string identity: JSON.stringify(claudeSettings)',
  'Object.freeze({context: settingsContext, identity: identity', 'Object.freeze(JSON.parse(JSON.stringify(claudeSettings)))',
  'maxHistoryLength: maxHistoryLength', 'owner.retireRequests(client)', 'onCurrentChanged: if (!current && _constructed) retire(client)'],
 'ClaudeProcess.qml':['required property var policy', 'required property var becameStarted', 'worker.delivered(worker, line)',
  '!worker.cancelled && !worker._finished', 'onExited: code => finish(code)', 'if (_finished || cancelled) return',
  '_finished = true', 'settled(worker, code)', 'worker.finish(-1)', 'function cancel() { cancelled = true; running = false; }',
  'Component.onDestruction: _lifetime.alive = false'],
 'Panel.qml':['settingsConsumerFor(pluginApi.settingsContext)', 'permissionMode: settingsConsumer?.permissionMode',
  'dangerouslySkip: settingsConsumer?.dangerouslySkip', 'var wd = settingsConsumer?.workingDir || ""',
  'mainInstance?.newSession(pluginApi?.settingsContext)', 'mainInstance.handleSlashCommand(trimmed, pluginApi)',
  'mainInstance.sendMessage(trimmed, pluginApi?.settingsContext)', 'mainInstance.saveState(pluginApi?.settingsContext)',
  'mainInstance?.messages || []', 'bubbleRoot.mainInstance.approveOnce(entry.id)', 'bubbleRoot.mainInstance.denyToolUse(entry.id)',
  'pluginApi?.pluginSettings?.panelPosition', 'pluginApi?.pluginSettings?.panelDetached', 'pluginApi?.pluginSettings?.attachmentStyle',
  'pluginApi?.pluginSettings?.panelWidth', 'pluginApi?.pluginSettings?.panelHeightRatio', 'pluginApi?.pluginSettings?.scale'],
 'BarWidget.qml':['settingsConsumerFor(pluginApi.settingsContext)', 'permissionMode: settingsConsumer?.permissionMode',
  'dangerouslySkip: settingsConsumer?.dangerouslySkip', 'mainInstance?.newSession(pluginApi?.settingsContext)',
  'mainInstance?.clearMessages(pluginApi?.settingsContext)', 'BarService.openPluginSettings(screen, pluginApi.manifest)'],
 'Settings.qml':['root.pluginApi?.scopeKind === "instance"', 'pluginApi?.tr("settings.sharedContent")',
  'pluginApi.resetFields(["claude"])', 'var next = Object.assign({}, editClaude)', 'return claudeField.set(next)']}


def check(sources,manifest,dictionary):
    code={name:syntax.compact(text)[0] for name,text in sources.items()}
    fields=manifest['metadata']['settingsSchema']['fields'];assert set(fields)==set(CONFIG)
    assert all(fields[key]['editorUsage']=='configuration' for key in CONFIG)
    for key in ('claude','panelPosition','panelDetached','panelWidth','panelHeightRatio'):
        require(code['Settings.qml'],'pluginApi?.field("'+key+'")',key+' intent')
    for name,anchors in ANCHORS.items():
        for anchor in anchors:require(code[name],anchor,name+': '+anchor)
    assert 'messages' not in code['ClaudeSettingsClient.qml'],'one Main conversation, no client content store'
    assert 'mainInstance' not in code['Settings.qml'],'page has no ACP action capability'
    assert dictionary['settings']['sharedContent']
    return dict(configuration=CONFIG,contentOwner='one Main conversation/draft/cache',processOwner='one serial Main ACP generation',
                unchangedUnsupportedAcpMembers=['binary','model','fallbackModel','permissionMode','dangerouslySkipPermissions','allowedTools','disallowedTools','additionalDirs','mcpConfigPath','strictMcpConfig','sessionId','autoResume','maxTurns','includePartialMessages'],runtimeAcceptance=False)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('source','plugins','report'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--selftest',action='store_true');a=p.parse_args();r=a.plugins/'claude-code-panel'
    sources={f.name:f.read_text() for f in r.glob('*.qml')};manifest=json.loads((r/'manifest.json').read_text());dictionary=json.loads((r/'i18n/en.json').read_text())
    member=check(sources,manifest,dictionary);controls=[]
    mutations=[
      ('Main.qml','var policy = _consumer(context)?.capture()','var policy = _consumer(undefined)?.capture()','shared-prompt'),
      ('Main.qml','_saveHistoryLength = client.maxHistoryLength','_saveHistoryLength = settingsConsumer.maxHistoryLength','shared-history'),
      ('Main.qml','if (acpProcess?.policy.context === client.settingsContext)','if (false)','missing-retirement'),
      ('Main.qml','if (life.alive && root._acpCurrent(source)) root._onAcpLine(line)','if (life.alive) root._onAcpLine(line)','late-wire'),
      ('Main.qml','params.sessionId !== sessionId) return false','false) return false','foreign-permission'),
      ('Main.qml','pending.worker !== acpProcess || !_acpCurrent(pending.worker) || pending.sessionId !== sessionId','false','permission-retarget'),
      ('Main.qml','Logic.firstTurnPrefix(request.policy.claude)','Logic.firstTurnPrefix(root.claudeSettings)','late-prefix'),
      ('Main.qml','originApi.pluginSettings.claude = next','pluginApi.pluginSettings.claude = next','shared-writer'),
      ('Main.qml','worker.cancel(); worker.destroy()','worker.destroy()','missing-stop'),
      ('ClaudeSettingsClient.qml','owner.retireRequests(client)','owner.retireRequests(null)','source-retirement'),
      ('ClaudeSettingsClient.qml','onCurrentChanged: if (!current && _constructed) retire(client)','onCurrentChanged: {}','owner-retirement'),
      ('ClaudeProcess.qml','if (_finished || cancelled) return','if (false) return','duplicate-settlement'),
      ('ClaudeProcess.qml','worker.finish(-1)','worker.finish(0)','failed-start-success'),
      ('Panel.qml','settingsConsumerFor(pluginApi.settingsContext)','settingsConsumerFor(mainInstance.pluginApi.settingsContext)','shared-panel'),
      ('Panel.qml','var wd = settingsConsumer?.workingDir || ""','var wd = "wrong"','cwd-child'),
      ('BarWidget.qml','settingsConsumerFor(pluginApi.settingsContext)','settingsConsumerFor(mainInstance.pluginApi.settingsContext)','shared-bar'),
      ('Panel.qml','mainInstance.sendMessage(trimmed, pluginApi?.settingsContext)','mainInstance.sendMessage(trimmed)','lost-origin')]
    if a.selftest:
        for name,old,new,label in mutations:
            assert old in sources[name],label
            changed=dict(sources);changed[name]=sources[name].replace(old,new)
            try:check(changed,manifest,dictionary)
            except (AssertionError,ValueError) as error:controls.append(dict(control=label,rejectedAt=str(error)))
            else:raise RuntimeError('Claude control escaped '+label)
    a.report.write_text(json.dumps(dict(status='PASS',member=member,controls=controls,runtimeAcceptance=False),indent=2)+'\n')
    print('CLAUDE_CHECK: PASS (8 configuration, %d parsed controls)'%len(controls))


if __name__=='__main__':main()
