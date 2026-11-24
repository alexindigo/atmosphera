#!/usr/bin/env python3
"""Finite Assistant field/request/content ownership contract, not a general JS proof."""
import argparse
import importlib.util
import json
from pathlib import Path
from fixture_evidence import require
spec=importlib.util.spec_from_file_location('assistant_syntax',Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax=importlib.util.module_from_spec(spec);spec.loader.exec_module(syntax)
CONFIG=['ai','translator','maxHistoryLength','attachmentStyle','panelDetached','panelHeightRatio','panelPosition','panelWidth','scale']
ANCHORS={
 'Main.qml':['property var _settingsConsumers: new Map()', '_settingsConsumers.has(context)', 'settingsContext: context', '_settingsConsumers.set(context, client)',
  'root.retireRequests(retired, "all"); root._settingsConsumers.delete(context); retired.destroy()',
  'settingsConsumerFor(context === undefined ? pluginApi?.settingsContext : context)',
  'var policy = _consumer(context)?.captureChat()', 'var policy = _consumer(context)?.captureTranslation(target, source)',
  'model: settingsConsumer?.model || ""', '_recordConversation([], client.maxHistoryLength)',
  '_conversation = {messages: next, historyLimit: limit}',
  'prepareStateForSave(_conversation, activeTab, chatInputText, chatInputCursorPosition)',
  'addMessage("user", text.trim(), policy.maxHistoryLength)', 'messages.slice(0, index)',
  'policy.openaiBaseUrl, policy.apiKey, policy.model, policy.systemPrompt, history, policy.temperature',
  'policy.model, policy.apiKey, policy.systemPrompt, history, policy.temperature',
  'requestFactory.createObject(root, {policy: policy, curlArgs: command.args', 'if (worker.rejectedHttp(code))',
  'if (_chatRequest !== worker || !worker.policy.context.current()) return', 'if (_chatRequest !== worker) return',
  'if (_translationRequest !== worker) return', 'if (!worker.policy.context.current())',
  'ProviderLogic.parseTranslateResponse(worker.policy.backend, output)', 'worker.policy.maxHistoryLength',
  '_chatRequest = null', '_translationRequest = null', 'worker.cancel(); worker.destroy()',
  'Component.onDestruction: _lifetime.alive = false', 'pluginApi.pluginSettings.ai.provider = providerName',
  'pluginApi.pluginSettings.ai.models = existing'],
 'AssistantSettingsClient.qml':['required property var settingsContext', 'readonly property var cfg: settingsContext.settingsView',
  'cfg.ai?.provider', 'cfg.ai?.models?.[provider]', 'cfg.ai?.apiKeys?.[provider]', 'cfg.ai?.temperature ??',
  'cfg.ai?.systemPrompt', 'cfg.ai?.openaiLocal ?? false', 'cfg.ai?.openaiBaseUrl', 'cfg.maxHistoryLength || 100',
  'cfg.translator?.backend', 'cfg.translator?.sourceLanguage', 'cfg.translator?.targetLanguage', 'cfg.translator?.deeplApiKey',
  'owner.envApiKeys[provider]', 'owner.envDeeplApiKey', 'Object.freeze({context: settingsContext, identity: chatIdentity',
  'maxHistoryLength: maxHistoryLength', 'backend: translatorBackend', 'owner.retireRequests(client, "chat")',
  'owner.retireRequests(client, "translation")', 'onCurrentChanged: if (!current && _constructed) retire(client)'],
 'AssistantRequest.qml':['required property var delivered', 'required property var settled', 'if (!worker._finished)',
  'command: ["curl", "--fail-with-body", ...curlArgs]',
  'worker.delivered(worker, data)', 'if (_finished) return', '_finished = true; settled(worker, code, output, errors.text)',
  'function cancel() { _finished = true; running = false; }', 'onExited: code => finish(code)',
  'if (life.alive) worker.finish(-1)', 'Component.onDestruction: _lifetime.alive = false'],
 'AiChatView.qml':['settingsConsumerFor(pluginApi.settingsContext)', 'model: settingsConsumer?.model || ""', 'text: model',
  'mainInstance.clearMessages(pluginApi?.settingsContext)', 'mainInstance.regenerateLastResponse(pluginApi?.settingsContext)',
  'mainInstance.editMessage(id, newText, pluginApi?.settingsContext)', 'mainInstance.sendMessage(text, pluginApi?.settingsContext)',
  'mainInstance.saveState(pluginApi?.settingsContext)', 'readonly property var messages: mainInstance?.messages || []'],
 'TranslatorView.qml':['settingsConsumerFor(pluginApi.settingsContext)', 'onPluginApiChanged: translateTimer.stop()',
  'onOriginCurrentChanged: if (!originCurrent) translateTimer.stop()', 'mainInstance.translate(inputText, targetLanguage, sourceLanguage, pluginApi?.settingsContext)',
  'pluginApi.pluginSettings.translator.sourceLanguage = sourceLanguage', 'pluginApi.pluginSettings.translator.targetLanguage = targetLanguage',
  'pluginApi?.pluginSettings?.translator?.realTimeTranslation ?? true'],
 'Panel.qml':['mainInstance.saveState(pluginApi?.settingsContext)', 'pluginApi: root.pluginApi', 'mainInstance: root.mainInstance',
  'pluginApi?.pluginSettings?.panelPosition', 'pluginApi?.pluginSettings?.panelDetached', 'pluginApi?.pluginSettings?.attachmentStyle',
  'pluginApi?.pluginSettings?.panelWidth', 'pluginApi?.pluginSettings?.panelHeightRatio', 'pluginApi?.pluginSettings?.scale'],
 'BarWidget.qml':['pluginApi?.pluginSettings?.scale', 'pluginApi?.pluginSettings?.ai?.provider', 'pluginApi?.pluginSettings?.ai?.apiKeys?.[provider]',
  'mainInstance.clearMessages(pluginApi?.settingsContext)', 'BarService.openPluginSettings(screen, pluginApi.manifest)'],
 'MessageBubble.qml':['text: message.content', 'root.regenerateRequested()', 'root.editRequested(message.id, editArea.text)'],
 'Settings.qml':['root.pluginApi?.scopeKind === "instance"','pluginApi?.tr("settings.sharedContent")']}


def check(sources,manifest,dictionaries):
    code={name:syntax.compact(text)[0] for name,text in sources.items()}
    fields=manifest['metadata']['settingsSchema']['fields']
    require(set(fields)==set(CONFIG), 'Assistant configuration fields')
    for key in CONFIG:
        require(fields[key]['editorUsage']=='configuration', key+' configuration usage')
        syntax.require(code['Settings.qml'],'pluginApi?.field("'+key+'")',key+' intent')
    for name,anchors in ANCHORS.items():
        for anchor in anchors:syntax.require(code[name],anchor,name+': '+anchor)
    require('messages' not in code['AssistantSettingsClient.qml'], 'one common conversation, no client content store')
    require(code['Main.qml'].count(syntax.squash('requestFactory.createObject(root, {policy: policy, curlArgs: command.args'))==2, 'one owned worker per chat/translation admission')
    require('mainInstance' not in code['Settings.qml'], 'Settings has no request capability')
    for name,value in dictionaries.items():
        require(value['settings']['sharedContent']==dictionaries['en.json']['settings']['sharedContent'], name+' explicit fallback')
    return dict(configuration=CONFIG,legacyAiMembers=['model','maxHistoryLength'],contentOwner='one Main/cache',runtimeAcceptance=False)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('source','plugins','report'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--selftest',action='store_true');a=p.parse_args();r=a.plugins/'assistant-panel'
    sources={f.name:f.read_text() for f in r.glob('*.qml')};m=json.loads((r/'manifest.json').read_text());d={f.name:json.loads(f.read_text()) for f in (r/'i18n').glob('*.json')}
    member=check(sources,m,d);controls=[]
    mutations=[('Main.qml','_consumer(context)?.captureChat()','_consumer(undefined)?.captureChat()','shared-chat'),
      ('Main.qml','_consumer(context)?.captureTranslation(target, source)','_consumer(undefined)?.captureTranslation(target, source)','shared-translation'),
      ('Main.qml','_recordConversation([], client.maxHistoryLength)','_recordConversation([], settingsConsumer.maxHistoryLength)','shared-history-policy'),
      ('Main.qml','ProviderLogic.parseTranslateResponse(worker.policy.backend, output)','ProviderLogic.parseTranslateResponse(root.translatorBackend, output)','late-parser'),
      ('Main.qml','requestFactory.createObject(root,','requestFactory.createObject(null,','unowned-request'),
      ('Main.qml','worker.cancel(); worker.destroy();','worker.destroy();','missing-process-stop'),
      ('Main.qml','if (_chatRequest !== worker || !worker.policy.context.current()) return;','if (!worker) return;','late-stream'),
      ('AssistantSettingsClient.qml','owner.retireRequests(client, "chat")','owner.retireRequests(client, "none")','source-retirement'),
      ('AssistantSettingsClient.qml','onCurrentChanged: if (!current && _constructed) retire(client)','onCurrentChanged: {}','owner-retirement'),
      ('AssistantSettingsClient.qml','cfg.ai?.temperature ??','cfg.ai?.temperature ||','zero-temperature'),
      ('AssistantRequest.qml','if (_finished) return;','if (false) return;','duplicate-settlement'),
      ('AssistantRequest.qml','worker.finish(-1)','worker.finish(0)','failed-start-success'),
      ('AiChatView.qml','settingsConsumerFor(pluginApi.settingsContext)','settingsConsumerFor(mainInstance.pluginApi.settingsContext)','shared-view'),
      ('AiChatView.qml','text: model','text: "wrong"','model-child'),
      ('MessageBubble.qml','text: message.content','text: "wrong"','response-child'),
      ('TranslatorView.qml','onPluginApiChanged: translateTimer.stop()','onPluginApiChanged: {}','queued-debounce'),
      ('Panel.qml','mainInstance.saveState(pluginApi?.settingsContext)','mainInstance.saveState()','content-origin')]
    if a.selftest:
        for name,old,new,label in mutations:
            require(old in sources[name], label+' mutation anchor')
            changed=dict(sources);changed[name]=sources[name].replace(old,new)
            try:check(changed,m,d)
            except (AssertionError,ValueError) as error:controls.append(dict(control=label,rejectedAt=str(error)))
            else:raise RuntimeError('assistant control escaped: '+label)
    a.report.write_text(json.dumps(dict(status='PASS',member=member,controls=controls,runtimeAcceptance=False),indent=2)+'\n')
    print('ASSISTANT_CHECK: PASS (9 configuration, %d controls)'%len(controls))


if __name__=='__main__':main()
