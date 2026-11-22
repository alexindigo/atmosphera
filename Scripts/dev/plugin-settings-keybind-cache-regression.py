#!/usr/bin/env python3
"""Real shared state owner, native second Apply and independent cold cache reuse."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('keybind_cache_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)

def main():
    p = argparse.ArgumentParser(description=__doc__); profile_argument(p)
    for name in ('source', 'plugins', 'work-root', 'output'): p.add_argument('--'+name, type=Path, required=True)
    args = p.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source/'Scripts/dev/plugin-settings-keybind-cache-regression.py': p.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): p.error('fresh owned roots required')
    with (profile.work_base/'.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX|fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        case, out = args.work_root, args.output
        install = case/'install'; shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git','.envrc','__pycache__'))
        for part in ('config/settings/plugins','cache','state'): (case/part).mkdir(parents=True)
        dest = case/'config/plugins/keybind-cheatsheet'; shutil.copytree(args.plugins/'keybind-cheatsheet', dest)
        source = case/'fixture.kdl'; source.write_text('binds {\n    Mod+Return { spawn "fixture-command"; }\n}\n')
        legacy = [dict(title='legacy',binds=[dict(keys='OLD',desc='unqualified legacy')])]
        prefs = dict(niriConfigPath=str(source),cheatsheetData=legacy,detectedCompositor='',opaque={'keep':True})
        runner.write_json(case/'config/settings.json',dict(settingsVersion=62)); runner.write_json(case/'config/plugins.json',dict(version=6,states={},sources=[]))
        preference = case/'config/settings/plugins/keybind-cheatsheet.json'; runner.write_json(preference,prefs)
        descriptor=json.loads((dest/'manifest.json').read_text())
        fixture=dest/'tests/cache-owner.qml'
        runner.write_json(out/'inputs.json',dict(source=str(args.source),plugins=str(args.plugins),files={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),fixture,*sorted(dest.glob('*.qml')),dest/'MangoParser.js']}))
        env=dict(KEYBIND_CACHE_MANIFEST=json.dumps(descriptor),KEYBIND_CACHE_SOURCE=str(source))
        warm=out/'warm'; warm.mkdir()
        text=runner.run_fixture(profile,install,case,warm,fixture,extra_env=env,extra_lint=tuple(sorted(dest.glob('*.qml'))),timeout=100)
        if 'KEYBIND_CACHE: SAVED_PASS' not in text: raise RuntimeError('warm cache endpoint missing')
        saved=json.loads(preference.read_text())
        # Reset general choices removes the path, followed by that input's explicit
        # restoration. Hidden and opaque leaves must survive both real Applies.
        expected=dict(prefs,windowWidth=1492)
        if saved!=expected: raise RuntimeError('complete preference readback: '+repr((saved,expected)))
        state=case/'state/plugins/keybind-cheatsheet/state.json'
        values=json.loads(state.read_text())
        if values.get('detectedCompositor')!='niri' or not values.get('cheatsheetSource') or 'Run: fixture-command' not in json.dumps(values.get('cheatsheetData')): raise RuntimeError('independent actual state-file readback')
        runner.write_json(out/'independent-warm.json',dict(preferences=saved,state=values))
        before={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in [preference,state]}
        cold=out/'cold'; cold.mkdir()
        text=runner.run_fixture(profile,install,case,cold,fixture,extra_env=dict(env,KEYBIND_CACHE_COLD='1'),extra_lint=tuple(sorted(dest.glob('*.qml'))),timeout=100)
        if 'KEYBIND_CACHE: COLD_PASS' not in text or before!={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in [preference,state]}: raise RuntimeError('cold cache read published or endpoint missing')
        runner.write_json(out/'result.json',dict(status='PASS',nativeApplies=2,independentCompleteDocuments=2,coldReaders=1,coldHashes=before,completePlanAcceptance=False))
        runner.remove_completed_installs(case,out)
if __name__=='__main__': main()
