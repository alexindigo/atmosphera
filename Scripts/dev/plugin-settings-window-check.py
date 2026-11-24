#!/usr/bin/env python3
"""Finite parsed G5 capture, field, native writer and retirement mappings."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('window_syntax', Path(__file__).with_name('plugin-settings-polling-check.py'))
syntax = importlib.util.module_from_spec(spec); spec.loader.exec_module(syntax)
FIELDS = {
    'wallcards': {'selected': 'animate_window animation_cards_duration animation_window_duration background_color background_opacity card_height card_spacing card_strip_width cards_shown center_width_ratio hide_help hide_top_bar live_preview selected_filter shear_factor top_bar_height', 'bar': 'iconColor', 'manifestOnly': 'image_filter video_filter', 'unusedLegacy': 'animation_duration icon_color'},
    'somnus': {'selected': 'animationsEnabled buttonHeight buttonOpacity buttonSpacing buttonWidth hoverColor hoverDesaturation lockOnSuspend overlayBlur overlayTint panelTint useOverlay', 'bar': 'iconColor', 'manifestOnly': '', 'unusedLegacy': ''},
}
WINDOWS = {'wallcards': 'Wallcards.qml', 'somnus': 'SomnusWindow.qml'}


def check(sources, manifests, dictionaries):
    code = {path: syntax.compact(text)[0] for path, text in sources.items()}
    rows = []
    for name, mapping in FIELDS.items():
        all_fields = {key for fields in mapping.values() for key in fields.split()}
        if all_fields != set(manifests[name]['metadata']['settingsSchema']['fields']):
            raise ValueError(name + ': unreviewed declared leaves')
        main = code[name + '/Main.qml']; window = code[name + '/' + WINDOWS[name]]
        for anchor in ('property var windowApi: null', 'readonly property bool windowCurrent: windowApi?.settingsContext.current() ?? false',
                       'caller = caller || pluginApi', '!caller?.settingsContext.current()', 'windowApi = caller', '"pluginApi": caller',
                       'onWindowCurrentChanged: if (windowApi && !windowCurrent)', 'windowLoader.active = false', 'if (root.windowApi === retired) root.windowApi = null'):
            syntax.require(main, anchor, name + ': originating window capture/lifetime: ' + anchor)
        if 'Qt.binding' in main:
            raise ValueError(name + ': late-bound window API')
        opener = 'toggle(root.pluginApi, root.screen)' if name == 'wallcards' else 'togglePanel?.(screen, pluginApi)'
        syntax.require(code[name + '/BarWidget.qml'], opener, name + ': placed opener capture')
        ipc = 'root.show(root.pluginApi)' if name == 'wallcards' else 'root.togglePanel(screen, root.pluginApi)'
        syntax.require(main, ipc, name + ': explicit plugin-scope IPC')
        for key in mapping['selected'].split():
            if not re.search(r'pluginSettings(?:\?|)\.' + key + r'\b', window):
                raise ValueError(name + ': selected window field missing: ' + key)
        for key in mapping['bar'].split():
            if not re.search(r'(?:cfg|pluginSettings)(?:\?|)\.' + key + r'\b', code[name + '/BarWidget.qml']):
                raise ValueError(name + ': direct Bar field missing: ' + key)
        for key in mapping['manifestOnly'].split():
            syntax.require(window, 'metadata?.defaultSettings?.' + key, name + ': existing manifest-only feature gap changed')
        settings = code[name + '/Settings.qml']
        for anchor in ('visible: root.pluginApi?.scopeKind === "instance"', 'root.pluginApi?.tr("shared-window-effect")'):
            syntax.require(settings, anchor, name + ': shared physical-effect explanation')
        for locale, dictionary in dictionaries[name].items():
            if not dictionary.get('shared-window-effect', '').strip():
                raise ValueError(name + ': missing shared-effect dictionary: ' + locale)
        rows.append(dict(plugin=name, fields=mapping, runtimeEntries=manifests[name]['entryPoints'], window=WINDOWS[name]))
    for anchor in ('function saveLayout(callback)', 'const api = root.pluginApi; if (!api?.settingsContext.current())', 'if (!api?.settingsContext.current()) return false', 'return api.saveSettings(callback)', 'root.saveLayout()'):
        syntax.require(code['wallcards/Wallcards.qml'], anchor, 'wallcards: originating native layout writer: ' + anchor)
    for field in 'card_height center_width_ratio cards_shown card_spacing card_strip_width hide_top_bar live_preview selected_filter hide_help animate_window'.split():
        syntax.require(code['wallcards/Wallcards.qml'], 'api.pluginSettings.' + field + '=', 'wallcards: selected runtime writer: ' + field)
    somnus = code['somnus/SomnusWindow.qml']
    syntax.require(somnus, 'const lockOnSuspend = pluginApi?.pluginSettings?.lockOnSuspend ?? true', 'somnus: selected policy captured before Close')
    syntax.require(somnus, 'if (lockOnSuspend) CompositorService.lockAndSuspend(); else CompositorService.suspend()', 'somnus: admitted suspend policy')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'plugins', 'report'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--selftest', action='store_true'); args = parser.parse_args()
    sources, manifests, dictionaries = {}, {}, {}
    for name in FIELDS:
        manifests[name] = json.loads((args.plugins / name / 'manifest.json').read_text())
        dictionaries[name] = {p.stem: json.loads(p.read_text()) for p in (args.plugins / name / 'i18n').glob('*.json')}
        sources.update({name + '/' + str(p.relative_to(args.plugins / name)): p.read_text() for p in (args.plugins / name).rglob('*.qml')})
    rows = check(sources, manifests, dictionaries); controls = []
    if args.selftest:
        mutations = [(name + '/Main.qml', '"pluginApi": caller', '"pluginApi": root.pluginApi', 'shared-window') for name in FIELDS]
        mutations += [(name + '/Main.qml', 'onWindowCurrentChanged: if (windowApi && !windowCurrent)', 'onWindowCurrentChanged: if (false)', 'retirement') for name in FIELDS]
        mutations += [('wallcards/BarWidget.qml', 'toggle(root.pluginApi, root.screen)', 'toggle()', 'missing-opener'), ('somnus/BarWidget.qml', 'togglePanel?.(screen, pluginApi)', 'togglePanel?.(screen)', 'missing-opener'), ('wallcards/Wallcards.qml', 'const api = root.pluginApi', 'const api = root.pluginApi.base', 'shared-writer'), ('somnus/SomnusWindow.qml', 'if (lockOnSuspend)', 'if (true)', 'shared-suspend-policy')]
        for path, old, new, label in mutations:
            if sources[path].count(old) != 1:
                raise RuntimeError('stale window control: ' + path + '/' + old)
            changed = dict(sources); changed[path] = sources[path].replace(old, new)
            try:
                check(changed, manifests, dictionaries)
            except ValueError as error:
                controls.append(dict(path=path, control=label, rejectedAt=str(error)))
            else:
                raise RuntimeError('window control escaped: ' + label)
    args.report.write_text(json.dumps(dict(status='PASS', kind='finite-parsed-window-contract', members=rows, controls=controls, runtimeAcceptance=False), indent=2) + '\n')
    print('PLUGIN_SETTINGS_WINDOW_CHECK: PASS (%d members, %d controls)' % (len(rows), len(controls)))


if __name__ == '__main__':
    main()
