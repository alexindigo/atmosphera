#!/usr/bin/env python3
"""Actual Dmenu IPC/Panel session-policy witnesses in the assigned guest."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
from copy import deepcopy
import re

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('dmenu_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


def replace_code(text, old, new):
    pattern = r'\s*'.join(re.escape(token) for token in re.findall(r'[A-Za-z_$][\w$]*|\d+|[^\s]', old))
    changed, count = re.subn(pattern, lambda _: new, text)
    if count != 1: raise RuntimeError('stale Dmenu mutation: ' + old)
    return changed


def run(args, profile):
    case, out = args.work_root / 'session', args.output / 'session'
    case.mkdir(); out.mkdir(); (out / 'persisted').mkdir()
    install = case / 'install'
    shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__', '.qmlls.ini'))
    for part in ('config/settings/plugins', 'cache', 'state', 'home', 'results'):
        (case / part).mkdir(parents=True)
    dest = case / 'config/plugins/dmenu'; shutil.copytree(args.plugins / 'dmenu', dest)
    substitutions = []
    if args.mode == 'lifetime':
        path = dest / 'Main.qml'; original = path.read_text()
        old = 'onLoaded: Qt.callLater(root.finishFileRequest, fileLoader)'
        new = 'onLoaded: root.pluginApi.state.dmenuFileContinuations.push({ loader: fileLoader, request: request })'
        path.write_text(replace_code(original, old, new))
        substitutions.append(dict(path='dmenu/Main.qml', kind='hold-real-FileView-completion', before=hashlib.sha256(original.encode()).hexdigest(), after=hashlib.sha256(path.read_bytes()).hexdigest()))
    runner.write_json(out / 'substitutions.json', substitutions)
    wanted = None
    if args.control:
        changes = {
            'prefix': ('Main.qml', 'handleSelection(state.customInputPrefix + text', 'handleSelection(pluginApi.pluginSettings.customInputPrefix + text', 'selection keeps admitted prefix after later preferences'),
            'toast': ('Main.qml', 'var showToast = state.showToastOnSelect;', 'var showToast = pluginApi.pluginSettings.showToastOnSelect;', 'explicit request toast false survives later shared true'),
            'toast-disabled': ('Main.qml', 'if (showToast) {', 'if (false) {', 'actual enabled toast reaches notification consumer'),
            'rendered-child': ('Panel.qml', 'text: itemRect.itemData.name || ""', 'text: "wrong-Dmenu-child"', 'actual IPC row Text displays admitted item and limit'),
            'defaults': ('Main.qml', 'var defaults = request.defaults;', 'var defaults = pluginApi.pluginSettings;', 'file completion keeps captured defaults and file prompt'),
            'open': ('Main.qml', 'if (root.requestCurrent(request) && state.active)', 'if (true)', 'superseded screen callback cannot open replacement'),
            'close': ('Main.qml', 'root.ownerCurrent && capturedApi === root.pluginApi && generation === root.requestGeneration', 'root.ownerCurrent && capturedApi === root.pluginApi', 'late close cannot close newer session'),
            'toggle': ('Main.qml', 'root.ownerCurrent && capturedApi === pluginApi && generation === root.requestGeneration', 'root.ownerCurrent && capturedApi === pluginApi', 'superseded toggle cannot retarget a new menu'),
            'options': ('Main.qml', 'opts[key] === undefined', 'true', 'explicit request options outrank file config'),
            'retirement': ('Main.qml', 'onOwnerCurrentChanged: if (!ownerCurrent) endSession(false)', 'onOwnerCurrentChanged: {}', 'retired API fences screen and active session'),
            'close-policy': ('Panel.qml', 'function onSessionEnded(sid) { root.updateFilter(); }', 'function onSessionEnded(sid) { root.updateFilter(); pluginApi.closePanel(pluginApi.panelOpenScreen); }', 'closeOnSelect false cannot be overridden by Panel'),
        }
        name, old, new, wanted = changes[args.control]; path = dest / name; original = path.read_text()
        path.write_text(replace_code(original, old, new)); substitutions.append(dict(path='dmenu/' + name, kind=args.control, before=hashlib.sha256(original.encode()).hexdigest(), after=hashlib.sha256(path.read_bytes()).hexdigest()))
        runner.write_json(out / 'substitutions.json', substitutions)
    runner.write_json(case / 'menu.json', dict(items=['Alpha', 'Beta', 'Gamma'], prompt='File prompt', allowCustomInput=True, maxResults=1, resultFormat='json', resultFile=str(case / 'results/file-loser'), callbackCmd="printf wrong > '" + str(case / 'results/callback-loser') + "'"))
    runner.write_json(case / 'array.json', ['One', 'Two'])
    (case / 'items.txt').write_text('Text A::Text B')
    shared = dict(customInputPrefix='captured:', maxResults=100, panelPosition='center', resultFile=str(case / 'results/default'), showFooter=True, showMatchCount=True, showToastOnSelect=False, opaque=dict(keep=True))
    for path, data in [('config/settings.json', dict(settingsVersion=62)), ('config/plugins.json', dict(version=6, states={}, sources=[])), ('config/settings/plugins/dmenu.json', shared), ('config/settings/bar.json', dict(widgets=dict(left=[])))]:
        runner.write_json(case / path, data)
    initial = dict(shared=shared, bar=dict(widgets=dict(left=[])))
    edited = deepcopy(initial); edited['shared'].update(panelPosition='top_right', maxResults=50, resultFile=str(case / 'results/policy'), showFooter=False, showMatchCount=False, showToastOnSelect=True)
    later = deepcopy(edited); later['shared'].update(customInputPrefix='later:', showToastOnSelect=True)
    runner.write_json(case / 'input.json', dict(plugin='dmenu'))
    runner.write_json(case / 'expectations.json', dict(initial=initial, discarded=initial, edited=edited, later=later))
    env = dict(PHA_DMENU_CASE=str(case), PHA_DMENU_MODE=args.mode, PHA_DMENU_OUTPUT=str(out), PHA_DMENU_DISK=str(args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py'), HOME=str(case / 'home'))
    try:
        fixture = 'plugin-settings-dmenu-lifetime.qml' if args.mode == 'lifetime' else 'plugin-settings-dmenu-session.qml'
        text = runner.run_fixture(profile, install, case, out, args.source / 'Scripts/dev/fixtures' / fixture, extra_env=env, extra_lint=tuple(dest.glob('*.qml')), timeout=90)
    except RuntimeError:
        log = (out / 'runtime.log').read_text()
        if args.old_red: wanted = 'selection keeps admitted prefix after later preferences'
        if not wanted or wanted not in log or (out / 'runtime.exit').read_text().strip() != '2': raise
        actual = (case / 'results/policy').read_text() if (case / 'results/policy').exists() else None
        if args.old_red and actual != 'later:typed': raise RuntimeError('old red did not reach actual result bytes')
        result = dict(status='PASS', originalRed=args.old_red, control=args.control, rejectedAt=wanted, actualResult=actual, completePlanAcceptance=False)
    else:
        if args.old_red or args.control: raise RuntimeError('original/control Dmenu defect escaped')
        if 'DMENU_SESSION: PASS ' + args.mode not in text or any(item in text for item in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'DMENU_ASSERT:')):
            raise RuntimeError('Dmenu consumer/diagnostic failure')
        if args.mode == 'policy':
            if (case / 'results/policy').read_text() != 'captured:typed': raise RuntimeError('independent prefix result differs')
            if (case / 'results/callback').read_text() != 'captured:typed': raise RuntimeError('independent callback result differs')
            if (case / 'results/notice').read_text() != 'Notice': raise RuntimeError('independent positive-toast result differs')
        else:
            if (case / 'results/file').read_text() != 'captured:typed' or (case / 'results/file-callback').read_text() != 'captured:typed': raise RuntimeError('independent file request result/callback differs')
            expected_names = {'file', 'file-callback', 'index', 'index-callback', 'text', 'alt', 'alt-callback'}
            if {p.name for p in (case / 'results').iterdir()} != expected_names: raise RuntimeError('retired/overridden request wrote a result')
            if (case / 'results/index').read_text() != '1' or (case / 'results/index-callback').read_text() != 'Two' or (case / 'results/text').read_text() != 'Text B': raise RuntimeError('independent array/text/index/name result differs')
            alt = json.loads((case / 'results/alt').read_text()); callback = json.loads((case / 'results/alt-callback').read_text())
            if alt != callback or alt['value'] != 'alternate' or alt['index'] != 0 or not isinstance(alt['sessionId'], int): raise RuntimeError('independent alt-action JSON result differs')
        expected = later['shared'] if args.mode == 'policy' else dict(shared, customInputPrefix='later:', showToastOnSelect=True)
        if json.loads((case / 'config/settings/plugins/dmenu.json').read_text()) != expected:
            raise RuntimeError('complete native shared document differs')
        cold = False
        if args.mode == 'policy':
            for boundary in ('initial', 'discarded', 'edited', 'later'):
                observed = json.loads((out / 'persisted' / (boundary + '.json')).read_text())
                if observed != dict(status='PASS', values=json.loads((case / 'expectations.json').read_text())[boundary]): raise RuntimeError('native documents differ at ' + boundary)
            cold_out = out / 'cold'; cold_out.mkdir()
            before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case / 'config').rglob('*.json')}
            text = runner.run_fixture(profile, install, case, cold_out, args.source / 'Scripts/dev/fixtures/plugin-settings-dmenu-session.qml', extra_env=dict(env, PHA_DMENU_MODE='cold'), timeout=90)
            if 'DMENU_SESSION: PASS cold' not in text or any(marker in text for marker in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'DMENU_ASSERT:')): raise RuntimeError('cold consumer failed')
            after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case / 'config').rglob('*.json')}
            if before != after: raise RuntimeError('cold consumer published configuration')
            runner.write_json(cold_out / 'observed.json', dict(status='PASS', configurationBefore=before, configurationAfter=after))
            cold = True
        result = dict(status='PASS', mode=args.mode, nonpublishingColdConsumer=cold, physicalProof=False, completePlanAcceptance=False)
    runner.write_json(out / 'result.json', result)
    runner.remove_completed_installs(case, out)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--old-red', action='store_true')
    parser.add_argument('--mode', choices=('policy', 'lifetime'), default='policy')
    parser.add_argument('--control', choices=('prefix', 'toast', 'toast-disabled', 'rendered-child', 'defaults', 'open', 'close', 'toggle', 'options', 'retirement', 'close-policy'))
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if args.old_red and (args.control or args.mode != 'policy'): parser.error('original red requires the unmutated policy witness')
    if args.control and args.mode != ('policy' if args.control in ('prefix', 'toast', 'toast-disabled', 'rendered-child') else 'lifetime'): parser.error('control requires its policy/lifetime witness')
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-dmenu-regression.py': parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned profile roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        paths = [Path(__file__), args.source / 'Scripts/dev/guest_profile.py', args.source / 'Scripts/dev/plugin-settings-host-assets-regression.py', args.source / 'Scripts/dev/fixtures/plugin-settings-query-disk.py'] + list((args.source / 'Scripts/dev/fixtures').glob('plugin-settings-dmenu-*.qml'))
        runner.write_json(args.output / 'inputs.json', dict(source=str(args.source), plugins=str(args.plugins), files={str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, pluginFiles={str(p.relative_to(args.plugins)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.plugins / 'dmenu').rglob('*') if p.is_file()}))
        runner.write_json(args.output / 'result.json', run(args, profile))


if __name__ == '__main__': main()
