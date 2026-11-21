#!/usr/bin/env python3
"""Finite parsed G1f fields, provider leases, request chains and retained owners."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('provider_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
FIELDS = {
    'github-feed': {'GithubFeedSettingsClient.qml': 'username token githubUrl refreshInterval maxEvents showStars showForks showPRs showRepoCreations showMyRepoStars showMyRepoForks showNotificationBadge colorizationEnabled colorizationIcon colorizationBadge colorizationBadgeText defaultTab enableSystemNotifications notifyGitHubNotifications notifyStars notifyForks notifyPRs notifyRepoCreations notifyMyRepoStars notifyMyRepoForks', 'Settings.qml': 'openInBrowser'},
    'model-usage': {'ModelUsageSettingsClient.qml': 'providers barDisplayMode barCycleIntervalSec barMetric refreshIntervalSec'},
    'mawaqit': {'MawaqitSettingsClient.qml': 'city country method tune tuneFajr tuneDhuhr tuneAsr tuneMaghrib tuneIsha school showNotifications playAzan azanFile hijriDayOffset showElapsed fajrAngle ishaAngle', 'BarWidget.qml': 'showCountdown hidePrayerName widgetIcon dynamicIcon textColor iconColor activeColor', 'Panel.qml': 'weekStartDay', 'Main.qml': '_cacheData _cacheCity _cacheCountry _cacheMethod _cacheSchool _cacheSavedAt _cacheFajrAngle _cacheIshaAngle'},
}
CLIENTS = {'github-feed': 'GithubFeedSettingsClient.qml', 'model-usage': 'ModelUsageSettingsClient.qml', 'mawaqit': 'MawaqitSettingsClient.qml'}
ANCHORS = {
    'github-feed/GithubFeedSettingsClient.qml': ['JSON.stringify([username, token, githubUrl])', 'old.stop(); observation.retireWorker(old); old.destroy()', 'username: username, token: token, githubUrl: githubUrl', 'onSourceKeyChanged: if (_constructed) { stop(); Qt.callLater(replaceSource); }', 'configurationError !== "" || (_worker?.hasError ?? false)', 'configurationError || (_worker?.errorMessage ?? "")'],
    'github-feed/GithubFeedWorker.qml': ['required property string username', 'required property string token', 'required property string githubUrl', 'active = false', 'for (var process of [followingProcess, worker0, worker1, worker2, worker3, worker4, worker5, myReposProcess, notificationsProcess, markReadProcess]) process.running = false', 'markReadQueue = []; batchQueue = []', 'observation.saveCache(root,', 'observation.downloadAvatars(root, root.events)', 'interval: root.refreshInterval * 1000', 'root.githubRestApiUrl + "/notifications/threads/" + threadId', '"Authorization: Bearer " + root.token', 'if (root.active && exitCode !== 0)'],
    'github-feed/Main.qml': ['worker.client._worker === worker', 'accepts(worker) && worker.client === settingsConsumer', 'data.schema === 1 && data.sourceUsername === worker.username && data.sourceOrigin === worker.githubWebUrl', 'sourceUsername: worker.username, sourceOrigin: worker.githubWebUrl', 'encodeURIComponent(worker.githubWebUrl) + "__" + encodeURIComponent(login)', '"file://" + encodeURI(avatarsDir + "/" + key + ".png")', 'if (_notified.has(key)) return', 'JSON.stringify([worker.githubWebUrl, worker.username, identity])', 'if (!root.accepts(root._avatar.worker))', 'if (!accepts(next.worker)) continue', '_avatarQueue = _avatarQueue.filter(entry => entry.worker !== worker)', 'pluginApi.pluginSettings.username = newUsername'],
    'model-usage/Main.qml': ['property var _providerLeases: new Map()', 'var key = sourceKeyFor(id, options)', 'path(options.statsPath ?? "~/.claude/stats-cache.json")', 'path(options.credentialsPath ?? "~/.claude/.credentials.json")', 'Quickshell.env("OPENROUTER_API_KEY") || (options.apiKey ?? "")', 'Quickshell.env("OPENCODE_ZEN_API_KEY") || Quickshell.env("OPENCODE_API_KEY") || Quickshell.env("ZEN_API_KEY") || (options.apiKey ?? "")', '++existing.leases', 'sourceSettings: JSON.parse(JSON.stringify(options))', 'if (--provider.leases > 0) return', '_providerLeases.delete(provider.leaseKey); provider.enabled = false; provider.cancelRequests(); provider.destroy()'],
    'model-usage/ModelUsageSettingsClient.qml': ['JSON.stringify(pluginSettings.providers ?? ({}))', 'observation.acquireProvider(id, pluginSettings.providers[id])', 'for (var old of previous) observation.releaseProvider(old)', 'interval: root.barCycleIntervalSec * 1000', 'interval: root.refreshIntervalSec * 1000', 'onProviderKeyChanged: if (_constructed) selectProviders()'],
    'model-usage/providers/ProviderLifetime.qml': ['readonly property var providerSettings: sourceSettings', 'var xhr = new XMLHttpRequest(); _requests.add(xhr)', 'if (!enabled || !_requests.has(xhr)) return false', '_requests.delete(xhr)', 'xhr.onreadystatechange = function() {}; xhr.abort()', 'Component.onDestruction: cancelRequests()'],
    'model-usage/providers/Claude.qml': ['if (tokenChanged) { root.cancelRequests(); root.lastProbeAtMs = 0; }', 'cancelRequests(); oauthAccessToken = ""', 'if (root.enabled) root.clearCredentials()', 'root.finishRequest(xhr)', 'root.enabled ? root.resolvePath(root.providerSettings?.statsPath', 'root.enabled ? root.resolvePath(root.providerSettings?.credentialsPath', 'nowMs - root.lastProbeAtMs'],
    'model-usage/providers/Codex.qml': ['root.enabled ? root.latestSessionPath : ""', 'if (!root.enabled) return', 'else sessionLister.running = false', 'root.loadPreviousSessionFile()', 'root.sessionPaths[root.sessionPathIndex]'],
    'model-usage/providers/Copilot.qml': ['if (!root.enabled) return', 'else tokenProcess.running = false', 'root.cancelRequests()', 'root.finishRequest(xhr)', 'now - root.lastRefreshAtMs'],
    'model-usage/providers/Gemini.qml': ['sessionAggregator.running = false; sessionCounter.running = false', 'if (!root.enabled) return'],
    'model-usage/providers/OpenRouter.qml': ['Quickshell.env("OPENROUTER_API_KEY")', 'return envKey || (providerSettings?.apiKey ?? "")', 'root.cancelRequests()', 'root.finishRequest(xhr)', 'completed === days.length'],
    'model-usage/providers/Zen.qml': ['Quickshell.env("OPENCODE_ZEN_API_KEY")', 'Quickshell.env("OPENCODE_API_KEY")', 'Quickshell.env("ZEN_API_KEY")', 'const capturedKey = root.apiKey', 'root.validatedApiKey = capturedKey', 'root.finishRequest(xhr)', 'root.cancelRequests()'],
    'mawaqit/MawaqitSettingsClient.qml': ['JSON.stringify([city, country, method, school, tuneParam, fajrAngle, ishaAngle])', 'syncTimer.stop(); updateTimer.stop(); retryTimer.stop()', 'old.onreadystatechange = function() {}; old.abort()', 'generation !== root._generation || root._xhr !== xhr', 'observation.saveCache(root, weekData)', 'observation.cacheFor(root)', 'observation.onPrayerTime(root, prayerKey)', 'onSourceKeyChanged: if (_constructed) replaceSource()', 'if (!current || _xhr) return'],
    'mawaqit/Main.qml': ['client === settingsConsumer && pluginApi.settingsContext.current()', 'cached?.schema === 1 && cached.source === client.sourceKey', 'JSON.stringify({schema: 1, source: client.sourceKey, days: days})', 'CalendarCache { id: calendarCache; pluginApi: root.pluginApi }', 'if (client.showNotifications && !_notified.has(key))', 'if (prayerKey !== "Imsak" && client.playAzan && !_played.has(key))'],
}


def check(sources, manifests):
    code = {path: syntax.squash(syntax.compact(text)[0]) for path, text in sources.items()}
    rows = []
    for member, mapping in FIELDS.items():
        declared = manifests[member]['metadata']['settingsSchema']['fields']; fields = {key for keys in mapping.values() for key in keys.split()}
        if fields != set(declared): raise ValueError(member + ': unreviewed declared leaves')
        protected = {key for key, value in declared.items() if value['editorUsage'] == 'operational'}
        expected = set(FIELDS['mawaqit']['Main.qml'].split()) if member == 'mawaqit' else set()
        if protected != expected: raise ValueError(member + ': protected leaves reclassified')
        main = code[member + '/Main.qml']; client = code[member + '/' + CLIENTS[member]]
        for anchor in ['property var _settingsConsumers: new Map()', 'if (!context || !context.current()) return null', 'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)', 'settingsContext: context', 'root._settingsConsumers.delete(context)', 'retired.destroy()', '_settingsConsumers.set(context, client)']: syntax.require(main, anchor, member + ': captured client factory/retirement')
        for anchor in ['settingsContext.settingsView', 'settingsContext.current()', 'onCurrentChanged:', 'retire(']: syntax.require(client, anchor, member + ': selected context/lifetime')
        for filename, keys in mapping.items():
            for key in keys.split():
                text = code[member + '/' + filename]
                if member == 'github-feed' and key == 'openInBrowser': syntax.require(text, 'pluginApi?.field("openInBrowser")', member + ': preserved known-unused field')
                elif not re.search(r'\.' + re.escape(key) + r'\b', text): raise ValueError(member + ': missing selected field mapping: ' + key)
        entries = {value for key, value in manifests[member]['entryPoints'].items() if key in {'barWidget', 'panel', 'controlCenterWidget', 'desktopWidget', 'launcherProvider'}}
        for entry in entries: syntax.require(code[member + '/' + entry], 'settingsConsumerFor(pluginApi.settingsContext)', member + ': selected entry ' + entry)
        rows.append(dict(plugin=member, fields=sorted(fields), operational=sorted(protected), runtimeEntries=sorted(entries), knownUnused=['openInBrowser'] if member == 'github-feed' else []))
    for path, anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(code[path], anchor, path + ': provider/request ownership: ' + anchor)
    worker = code['github-feed/GithubFeedWorker.qml']
    for method in ['handleFollowingResponse', 'finishFollowingFetch', 'assignNextBatch', 'handleWorkerResponse', 'fetchMyRepoEvents', 'handleMyReposResponse', 'fetchFromGitHub', 'fetchNotifications', 'handleNotificationsResponse', 'markAllNotificationsAsRead', 'markNotificationAsRead', 'processMarkReadQueue', 'finalizeFetch']:
        if not re.search(r'function' + method + r'\([^)]*\)\{if\(!active\)return', worker): raise ValueError('GitHub: unfenced chain entry ' + method)
    for path, text in code.items():
        if '/providers/' in path and not path.endswith('/ProviderLifetime.qml'):
            if 'newXMLHttpRequest(' in text: raise ValueError(path + ': unowned XHR lifetime')
            syntax.require(text, 'ProviderLifetime{', path + ': request owner base')
        if not path.endswith('/Main.qml') and '.pluginSettings.' in text and re.search(r'pluginSettings\.[A-Za-z_]\w*=', text): raise ValueError(path + ': child acquired a native preference writer')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'report'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true'); args = parser.parse_args()
    sources, manifests = {}, {}
    for member in FIELDS:
        manifests[member] = json.loads((args.plugins / member / 'manifest.json').read_text())
        sources.update({member + '/' + str(p.relative_to(args.plugins / member)): p.read_text() for p in (args.plugins / member).rglob('*.qml')})
    rows = check(sources, manifests); controls = []
    if args.selftest:
        mutations = [(member + '/Main.qml', 'root._settingsConsumers.delete(context)', 'context', 'retirement') for member in FIELDS]
        mutations += [('github-feed/Main.qml', 'encodeURIComponent(worker.githubWebUrl) + "__" + encodeURIComponent(login)', 'encodeURIComponent(login)', 'avatar-origin'), ('github-feed/Main.qml', 'if (!accepts(next.worker)) continue', 'if (false) continue', 'avatar-queue-retirement'), ('github-feed/GithubFeedSettingsClient.qml', 'configurationError !== "" || (_worker?.hasError ?? false)', '(_worker?.hasError ?? false)', 'unconfigured-error')]
        mutations += [('github-feed/Main.qml', 'encodeURI(avatarsDir + "/" + key + ".png")', 'avatarsDir + "/" + key + ".png"', 'avatar-file-url')]
        mutations += [(member + '/Panel.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.base.settingsContext)', 'shared-view') for member in FIELDS]
        mutations += [('github-feed/Main.qml', 'worker.client === settingsConsumer', 'true', 'shared-cache-owner'), ('github-feed/Main.qml', 'data.sourceOrigin === worker.githubWebUrl', 'true', 'cache-provenance'), ('github-feed/Main.qml', 'if (_notified.has(key)) return', 'if (false) return', 'common-notification'), ('github-feed/GithubFeedWorker.qml', 'function processMarkReadQueue() {\n        if (!active) return;', 'function processMarkReadQueue() {', 'captured-patch-queue'), ('model-usage/Main.qml', 'if (--provider.leases > 0) return', 'if (false) return', 'last-lease'), ('model-usage/providers/ProviderLifetime.qml', '!enabled || !_requests.has(xhr)', '!enabled', 'retired-request'), ('model-usage/providers/Claude.qml', 'root.cancelRequests(); root.lastProbeAtMs = 0;', 'root.lastProbeAtMs = 0;', 'credential-handoff'), ('model-usage/providers/Zen.qml', 'root.validatedApiKey = capturedKey', 'root.validatedApiKey = root.apiKey', 'captured-probe-key'), ('mawaqit/Main.qml', 'client === settingsConsumer && pluginApi.settingsContext.current()', 'pluginApi.settingsContext.current()', 'shared-prayer-cache'), ('mawaqit/MawaqitSettingsClient.qml', 'school, tuneParam, fajrAngle', 'school, fajrAngle', 'tune-source'), ('mawaqit/MawaqitSettingsClient.qml', 'generation !== root._generation || root._xhr !== xhr', 'false', 'late-prayer-response')]
        for path, old, new, label in mutations:
            expected_count = 2 if label == 'late-prayer-response' else 1
            if sources[path].count(old) != expected_count: raise RuntimeError('stale provider control: ' + path + '/' + old)
            changed = dict(sources); changed[path] = sources[path].replace(old, new)
            try: check(changed, manifests)
            except ValueError as error: controls.append(dict(path=path, control=label, rejectedAt=str(error)))
            else: raise RuntimeError('provider control escaped: ' + label)
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-provider-contract', members=rows, controls=controls, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_PROVIDER_CHECK: PASS (%d members, %d controls)' % (len(rows), len(controls)))


if __name__ == '__main__': main()
