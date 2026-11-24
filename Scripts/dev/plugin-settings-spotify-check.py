#!/usr/bin/env python3
"""Finite parsed Spotify field, applied-action, IO lifetime and writer contract."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('spotify_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
FIELDS = {'accessToken', 'refreshToken', 'tokenExpiresAt', 'clientId', 'clientSecret', 'callbackPort', 'playerId', 'message'}
PROTECTED = {'accessToken', 'refreshToken', 'tokenExpiresAt'}
ANCHORS = {
    'Main.qml': ['property var _settingsConsumers: new Map()', 'if (!context || !context.current()) return null', 'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)', 'settingsContext: context', 'root._settingsConsumers.delete(context)', 'retired.destroy()', '_settingsConsumers.set(context, client)', '_settingsConsumers.get(runtimeApi.settingsContext) !== client || !client.accepts(input)', 'var writer = runtimeApi', 'writer.saveSettings(', 'settingsConsumerFor(api?.settingsContext)?.refreshAccessToken(api)', '!result.unresolvedGroups || !result.unresolvedGroups.length'],
    'SpotifySettingsClient.qml': ['settingsContext.settingsView', 'settingsContext.current()', 'api.apiRole === "settings-editor"', 'api.settingsContext !== settingsContext', 'var values = api.pluginSettings', 'rawPort: values.callbackPort ?? 8888', 'callbackPort: callbackPort', 'input.api.settingsContext.current()', 'values.clientId === input.clientId && values.clientSecret === input.clientSecret', '(values.callbackPort ?? 8888) === input.rawPort', 'const [code, state, error] = line.split(":")', 'state !== pending.state', 'pending.generation !== root._generation', 'root.requestToken(pending.input', '++_generation; _authorization = null; _saving = false', 'request.onreadystatechange = function() {}; request.abort()', 'callbackServer.running = false; browser.running = false', 'job.running = false; job.destroy()', 'generation !== root._generation || !root.accepts(input)', 'root._slots.delete(slot)', '_slots.get(slot)', 'onCredentialsKeyChanged: if (_constructed) cancel()', 'onCurrentChanged: if (!current && _constructed) { cancel(); retire(root); }', 'Component.onDestruction: { _lifetime.alive = false; cancel(); }', 'observation.adoptTokens(root, input, tokens', 'input.refreshToken', 'input.accessToken', 'input.playerId', 'String(input.callbackPort)', 'state: state', 'root.shuffle(input, state, true)', 'root.devices(api)'],
    'BarWidget.qml': ['settingsConsumerFor(pluginApi.settingsContext)', 'mainInstance.refreshAccessToken(pluginApi)', 'pluginSettings?.message'],
    'Panel.qml': ['settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumer?.authorize(root.pluginApi)', 'settingsConsumer?.devices(root.pluginApi)', 'settingsConsumer?.search(query, pluginApi)', 'settingsConsumer?.play(data, pluginApi)', 'settingsConsumer?.shufflePlayback(pluginApi)', 'settingsConsumer?.playlists(pluginApi)', 'AuthorizationStatus{', '"spotify-authorize"', '"spotify-devices"'],
    'Settings.qml': ['AuthorizationStatus{', 'pluginSettings?.accessToken', '"authorization.settings-guidance"', 'settingsConsumerFor(pluginApi.runtimeContext)', 'root.settingsConsumer?.status'],
}


def check(sources, manifest, dictionary):
    code = {path: syntax.squash(syntax.compact(text)[0]) for path, text in sources.items()}
    declared = manifest['metadata']['settingsSchema']['fields']
    if set(declared) != FIELDS or {k for k, v in declared.items() if v['editorUsage'] == 'operational'} != PROTECTED: raise ValueError('Spotify declared/protected fields changed')
    for path, anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(code[path], anchor, path + ': captured runtime contract: ' + anchor)
    for key in FIELDS - PROTECTED - {'message'}: syntax.require(code['Settings.qml'], 'field("' + key + '")', 'explicit configuration field: ' + key)
    for key in PROTECTED: syntax.require(code['Main.qml'], 'writer.pluginSettings.' + key + '=', 'Main operational writer: ' + key)
    page = code['Settings.qml']
    if any(edge in page for edge in ['Process{', 'newXMLHttpRequest(', 'Auth.', 'adoptTokens(', 'requestToken(', 'authorize(', 'saveState(']): raise ValueError('Settings acquired runtime auth/action edge')
    for path, text in code.items():
        if path != 'Main.qml' and re.search(r'pluginSettings\.[A-Za-z_]\w*=', text): raise ValueError(path + ': operational writer outside Main')
    if 'Process{' in code['Panel.qml'] or 'newXMLHttpRequest(' in code['Panel.qml']: raise ValueError('Panel acquired independent IO owner')
    for key in ('settings-guidance', 'runtime-guidance', 'authorize', 'token-available', 'not-authorized', 'pending', 'failed'):
        if not dictionary.get('authorization', {}).get(key, '').strip(): raise ValueError('missing authorization copy: ' + key)
    return dict(fields=sorted(FIELDS), operational=sorted(PROTECTED), runtimeEntries=['BarWidget.qml', 'Panel.qml'], knownUnused=['message presentation', 'legacy playlistSelectionId with no UI producer'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'report'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true'); args = parser.parse_args()
    root = args.plugins / 'spotify-player'
    sources = {p.name: p.read_text() for p in root.glob('*.qml')}; manifest = json.loads((root / 'manifest.json').read_text()); dictionary = json.loads((root / 'i18n/en.json').read_text())
    row = check(sources, manifest, dictionary); controls = []
    if args.selftest:
        mutations = [('Main.qml', 'var writer = runtimeApi;', 'var writer = root.pluginApi;', 'shared-writer'), ('Main.qml', 'root._settingsConsumers.delete(context)', 'context', 'retirement'), ('SpotifySettingsClient.qml', 'var values = api.pluginSettings;', 'var values = settingsContext.settingsView;', 'draft-credentials'), ('SpotifySettingsClient.qml', 'request.onreadystatechange = function() {}; request.abort()', 'request.abort()', 'late-token'), ('SpotifySettingsClient.qml', 'state !== pending.state', 'false', 'callback-state'), ('SpotifySettingsClient.qml', 'root.shuffle(input, state, true)', 'root.shuffle(root.inputFor(input.api), state, true)', 'play-shuffle-capture'), ('SpotifySettingsClient.qml', 'if (!current && _constructed) { cancel(); retire(root); }', 'if (!current && _constructed) { retire(root); }', 'context-cancellation'), ('BarWidget.qml', 'mainInstance.refreshAccessToken(pluginApi)', 'mainInstance.refreshAccessToken()', 'bar-origin'), ('Panel.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)', 'shared-panel'), ('Settings.qml', 'pluginApi?.saveSettings();', 'pluginApi.mainInstance.adoptTokens({});', 'page-action')]
        for path, old, new, label in mutations:
            if sources[path].count(old) != 1: raise RuntimeError('stale Spotify control: ' + label)
            changed = dict(sources); changed[path] = sources[path].replace(old, new)
            try: check(changed, manifest, dictionary)
            except ValueError as error: controls.append(dict(control=label, rejectedAt=str(error)))
            else: raise RuntimeError('Spotify control escaped: ' + label)
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-spotify-contract', members=[row], controls=controls, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_SPOTIFY_CHECK: PASS (%d fields, %d controls)' % (len(FIELDS), len(controls)))


if __name__ == '__main__': main()
