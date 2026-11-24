#!/usr/bin/env python3
"""Catalog page witness for listed generic Settings entries. Guest only.

Both scopes open through the actual popup/session and native owners. One field
control's own user signal carries intent; Apply and field Reset are read back
from the owning files by the fixture and again independently here. Main entry
points are not constructed, so no plugin command/network/device effect runs;
this is page/persistence proof, not a claim about each plugin's consumers.
"""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
SEED = dict(opaque=dict(keep=True))
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'is not installed', 'is not a type', 'Cannot assign to non-existent property')


def settings_files(plugin_dir):
    """The manifest entry plus Settings children: settings-named files/directories."""
    manifest = json.loads((plugin_dir / 'manifest.json').read_text())
    entry = plugin_dir / manifest['entryPoints']['settings'].split('?')[0]
    children = [path for path in sorted(plugin_dir.rglob('*.qml')) if path != entry and
                'fixtures' not in path.parts and 'tests' not in path.parts and
                any('settings' in part.lower() for part in path.relative_to(plugin_dir).parts)]
    return [entry] + children


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--ids', required=True, help='comma-separated plugin directories')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    ids = args.ids.split(',')
    # This executable is also used for focused cohorts. A missing/empty cohort
    # must not silently turn an aggregate invocation into a 0/0 green result.
    if not ids or any(not plugin or Path(plugin).name != plugin or plugin in ('.', '..') for plugin in ids):
        parser.error('--ids must name a nonempty comma-separated cohort')
    if len(set(ids)) != len(ids):
        parser.error('--ids contains duplicate catalog entries')
    for plugin in ids:
        manifest_path = args.plugins / plugin / 'manifest.json'
        if not manifest_path.is_file() or not json.loads(manifest_path.read_text()).get('entryPoints', {}).get('settings'):
            parser.error('--ids names a missing generic Settings entry: ' + plugin)
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        case, out = args.work_root, args.output
        install = case / 'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        for part in ('config/settings/plugins', 'cache', 'state'):
            (case / part).mkdir(parents=True)
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        inputs = {}
        for plugin in ids:
            shutil.copytree(args.plugins / plugin, case / 'config/plugins' / plugin, ignore=shutil.ignore_patterns('*.bak'))
            runner.write_json(case / 'config/settings/plugins' / (plugin + '.json'), SEED)
            inputs[plugin] = {str(path.relative_to(args.plugins)): hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in sorted((args.plugins / plugin).rglob('*')) if path.is_file() and path.suffix in ('.qml', '.js', '.json')}
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-catalog-pages.qml'
        error = None
        lint_files = [path for plugin in ids for path in settings_files(case / 'config/plugins' / plugin)]
        try:
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=dict(PHA_CATALOG_IDS=','.join(ids)),
                                      extra_lint=lint_files, timeout=30 + 25 * len(ids))
        except RuntimeError as failure:
            error = str(failure)
            text = (out / 'runtime.log').read_text()
        rows = [json.loads(line.split('CATALOG_ROW ', 1)[1]) for line in text.splitlines() if 'CATALOG_ROW ' in line]
        diagnostics = {}
        for line in text.splitlines():
            if any(marker in line for marker in BAD):
                hit = next((plugin for plugin in ids if '/plugins/' + plugin + '/' in line), 'shell')
                diagnostics.setdefault(hit, []).append(line.strip()[:400])
        results = {}
        rows_by = {}
        for item in rows:
            rows_by.setdefault(item['plugin'], {})[item['scope']] = item
        for plugin in ids:
            scoped = rows_by.get(plugin, {})
            reasons = [scope + ': ' + scoped[scope].get('detail', '') for scope in ('plugin', 'instance')
                       if scope in scoped and scoped[scope]['status'] not in ('PASS', 'UNEXERCISED', 'INFORMATIONAL')]
            unexercised = [scope for scope in ('plugin', 'instance') if scoped.get(scope, {}).get('status') == 'UNEXERCISED']
            reasons += ['missing ' + scope for scope in ('plugin', 'instance') if scope not in scoped]
            shared = json.loads((case / 'config/settings/plugins' / (plugin + '.json')).read_text())
            if shared != SEED:
                reasons.append('independent shared readback differs from seed after Reset')
            reasons += ['runtime: ' + line for line in diagnostics.get(plugin, [])]
            informational = all(scoped.get(scope, {}).get('status') == 'INFORMATIONAL' for scope in ('plugin', 'instance'))
            results[plugin] = dict(status='FAIL' if reasons else 'UNEXERCISED' if unexercised else 'INFORMATIONAL' if informational else 'PASS', reasons=reasons or
                                   ['unexercised ' + scope + ': ' + scoped[scope].get('detail', '') for scope in unexercised], rows=scoped)
        bar = case / 'config/settings/bar.json'
        placements = json.loads(bar.read_text())['widgets']['left'] if bar.exists() else []
        placement_readback = placements == [dict(id='plugin:' + plugin) for plugin in ids]
        # Every entry and loaded child ran through the fixture's actual qs/native lint universe.
        lint_log = (out / 'lint.log').read_text() if (out / 'lint.log').exists() else ''
        lint_exit = 0 if (out / 'lint.log').exists() and not (error and 'lint' in error) else 1
        for plugin in ids:
            if re.search(r'(?m)^(?:Error: [^\n]*/plugins/' + re.escape(plugin) + '/|Warning: [^\n]*/plugins/' + re.escape(plugin) + r'/[^\n]*\[(?:syntax|import|unresolved-type|missing-property)\])', lint_log):
                results[plugin]['status'] = 'FAIL'
                results[plugin]['reasons'].append('qmllint error-severity diagnostic')
        passed = [plugin for plugin in ids if results[plugin]['status'] in ('PASS', 'INFORMATIONAL')]
        unexercised = [plugin for plugin in ids if results[plugin]['status'] == 'UNEXERCISED']
        summary = dict(status='PASS' if len(passed) + len(unexercised) == len(ids) and lint_exit == 0 and not error
                       and placement_readback and not diagnostics.get('shell') else 'FAIL',
                       unexercised=unexercised,
                       independentPlacementReadback=placement_readback,
                       fixtureError=error, lintExit=lint_exit, shellDiagnostics=diagnostics.get('shell', []),
                       passed=passed, failed=[plugin for plugin in ids if plugin not in passed + unexercised], inputs=inputs, results=results,
                       witness='control user-signal emission through the actual popup/session/native owners; not physical input; Main not constructed')
        stage_receipt(out / 'result.json', summary)
        for plugin in ids:
            print('CATALOG %s: %s %s' % (plugin, results[plugin]['status'], '; '.join(results[plugin]['reasons'])[:600]), flush=True)
        print('CATALOG_PAGES: %s (%d/%d exercised, %d unexercised %s, lint rc %d%s)' % (summary['status'], len(passed), len(ids), len(unexercised), unexercised, lint_exit,
                                                           ', fixture ' + error if error else ''), flush=True)
        if summary['status'] == 'PASS':
            runner.remove_completed_installs(case, out)
        else:
            raise SystemExit(1)


if __name__ == '__main__':
    main()
