#!/usr/bin/env python3
"""Finite parsed calendar field, projection, provider and lifetime contract."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('calendar_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
FIELDS = 'panelMode weekStart timeFormat lineColorType hourLineOpacity dayLineOpacity'.split()
ANCHORS = {
    'Main.qml': ['property var _settingsConsumers: new Map()', 'if (!context || !context.current()) return null', 'if (_settingsConsumers.has(context)) return _settingsConsumers.get(context)', 'settingsContext: context', 'root._settingsConsumers.delete(context)', 'retired.destroy()', '_settingsConsumers.set(context, client)', 'settingsConsumerFor(pluginApi.settingsContext)', 'if (_requestQueued) return', 'root._requestQueued = false', 'if (!client.current || !client.hasLoadedOnce) continue', 'new Date(client.weekStart)', 'new Date(client.weekEnd)', 'first.setDate(first.getDate() - 7)', 'last.setDate(last.getDate() + 14)', 'if (!start || first < start) start = first', 'if (!end || last > end) end = last', 'if (!start || !end) return', 'CalendarService.loadEvents(Math.max(0, Math.ceil((end - now) / 86400000)), Math.max(0, Math.ceil((now - start) / 86400000)))', 'if (client.current) client.updateEventsFromService()', 'function onAvailableChanged()', 'if (client.current) client.loadEvents()', 'function initializePluginSettings()', 'for (var key of Object.keys(submitted)) pluginApi.pluginSettings[key] = submitted[key]', 'function togglePanel()'],
    'WeeklyCalendarSettingsClient.qml': ['required property var settingsContext', 'settingsContext.current()', 'settingsContext.settingsView', 'onCurrentChanged: if (_constructed && !current)', 'retire(root)', 'if (root.current) root.loadEvents()', 'if (!current || !CalendarService.available || isLoading) return', 'hasLoadedOnce = true', 'requestEvents()', 'if (!current) return', 'onWeekStartSettingChanged: if (_constructed && hasLoadedOnce) queueLoad()', 'onCurrentDateChanged: if (_constructed) queueLoad()', 'var overlapsWeek = eventStart < weekEndDate && eventEnd > weekStartDate', 'processTimedEventIntoArray(eventObj, newEvents)', 'calculateAllDayEventLayout()', 'updateOverlappingEvents()', 'data[e.index] = {', 'totalLanes: total', 'if (current) currentDate = new Date()'],
    'Panel.qml': ['settingsConsumerFor(pluginApi.settingsContext)', 'mainInstance.panelModeSetting === "attached"', 'mainInstance.panelModeSetting === "centered"', 'mainInstance?.eventsModel', 'mainInstance?.allDayEventsWithLayout', 'mainInstance.formatTime(d)', 'mainInstance?.formatTimeRangeForDisplay(model)', 'mainInstance?.hourLineOpacitySetting ?? 0.5', 'mainInstance?.dayLineOpacitySetting ?? 0.9', 'mainInstance?.getEventTooltip(model)', 'mainInstance?.handleEventClick(eventData)', 'mainInstance.navigateWeek(event.key === Qt.Key_Left ? -7 : 7)'],
    'BarWidget.qml': ['settingsConsumerFor(pluginApi.settingsContext)', 'readonly property QtObject pluginCore: settingsConsumer', 'var events = pluginCore.eventsModel', 'pluginCore.formatTimeRangeForDisplay(currentEv)', 'pluginCore.formatTimeRangeForDisplay(nextEv)', 'target: pluginCore', 'root.pluginApi?.openPanel(root.screen)'],
    'Settings.qml': ['visible: root.pluginApi?.scopeKind === "instance"', 'root.pluginApi?.tr("settings.shared-effect")', 'checked: root.timeFormat === "12h"', 'root.timeFormatField.set(checked ? "12h" : "24h")', 'root.hourLineOpacityField?.value ?? 0.5', 'root.dayLineOpacityField?.value ?? 0.9']
}


def check(sources, manifest, dictionaries):
    code = {name: syntax.compact(text)[0] for name, text in sources.items()}
    if set(FIELDS) != set(manifest['metadata']['settingsSchema']['fields']): raise ValueError('unreviewed calendar leaves')
    if set(manifest['entryPoints']) != {'main', 'settings', 'panel', 'barWidget'}: raise ValueError('unreviewed calendar entry')
    for path, anchors in ANCHORS.items():
        for anchor in anchors: syntax.require(code[path], anchor, path + ': calendar ownership: ' + anchor)
    client = code['WeeklyCalendarSettingsClient.qml']
    for key in FIELDS:
        if not re.search(r'\bcfg\.' + key + r'\b', client): raise ValueError('missing selected calendar leaf: ' + key)
        if manifest['metadata']['settingsSchema']['fields'][key]['editorUsage'] != 'configuration': raise ValueError('calendar classification changed')
    if 'pluginSettings' in client or '.saveSettings(' in client or 'CalendarService.loadEvents(' in client: raise ValueError('client acquired preference/provider owner')
    if 'target: CalendarService' in code['Panel.qml']: raise ValueError('per-view common event owner')
    for locale, dictionary in dictionaries.items():
        if not dictionary.get('settings', {}).get('shared-effect', '').strip(): raise ValueError('missing common-calendar explanation: ' + locale)
    return dict(plugin='weekly-calendar', fields=FIELDS, entries=manifest['entryPoints'], sharedProviderOwner='CalendarService', selectedProjectionOwner='Main')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'report'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true'); args = parser.parse_args()
    root = args.plugins / 'weekly-calendar'
    sources = {p.name: p.read_text() for p in root.glob('*.qml')}
    manifest = json.loads((root / 'manifest.json').read_text())
    dictionaries = {p.stem: json.loads(p.read_text()) for p in (root / 'i18n').glob('*.json')}
    row = check(sources, manifest, dictionaries); controls = []
    if args.selftest:
        changes = [('Main.qml', 'root._settingsConsumers.delete(context)', 'context', 'retirement'), ('Panel.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)', 'shared-panel'), ('BarWidget.qml', 'settingsConsumerFor(pluginApi.settingsContext)', 'settingsConsumerFor(pluginApi.mainInstance.pluginApi.settingsContext)', 'shared-bar'), ('Main.qml', 'if (!client.current || !client.hasLoadedOnce) continue;', 'if (!client.hasLoadedOnce) continue;', 'retired-range'), ('Main.qml', 'if (!start || first < start) start = first;', 'start = first;', 'last-range-wins'), ('WeeklyCalendarSettingsClient.qml', 'if (root.current) root.loadEvents()', 'root.loadEvents()', 'queued-retirement'), ('Settings.qml', 'root.timeFormatField.set(checked ? "12h" : "24h")', 'root.timeFormatField.set(checked ? "translated12" : "translated24")', 'localized-source-id'), ('Panel.qml', 'mainInstance?.hourLineOpacitySetting ?? 0.5', 'mainInstance?.hourLineOpacitySetting || 0.5', 'zero-opacity')]
        changes += [('WeeklyCalendarSettingsClient.qml', 'cfg.' + key, 'other.' + key, 'shared-' + key) for key in FIELDS]
        changes += [('Main.qml', 'if (client.current) client.updateEventsFromService();', 'if (client.current && client.hasLoadedOnce) client.updateEventsFromService();', 'initial-unavailable-observation')]
        for path, old, new, label in changes:
            if sources[path].count(old) != 1: raise RuntimeError('stale calendar control: ' + label)
            changed = dict(sources); changed[path] = sources[path].replace(old, new)
            try: check(changed, manifest, dictionaries)
            except ValueError as error: controls.append(dict(control=label, rejectedAt=str(error)))
            else: raise RuntimeError('calendar control escaped: ' + label)
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-calendar-contract', member=row, controls=controls, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_CALENDAR_CHECK: PASS (6 fields, %d controls)' % len(controls))


if __name__ == '__main__': main()
