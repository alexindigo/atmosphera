#!/usr/bin/env python3
"""Query/data completion and identity preservation across async providers."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

from launcher_workspace import ROOT
sys.path.insert(0, str(ROOT / 'tools'))
from filechooser_isolation import enter, guest, profile_env
from launcher_paste_support import png


def main():
    enter(runtime_seconds=180)
    guest()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    runtime, output = ROOT / 'runtime' / args.label, ROOT / 'evidence' / args.label
    output.mkdir()
    tree, profile = runtime / 'tree', runtime / 'profile'
    shutil.copytree(source, tree, symlinks=True)
    (tree / 'shell.qml').write_text((source / 'Scripts/dev/fixtures/launcher-provider-data.qml').read_text())
    env = profile_env(profile)
    settings = json.loads((source / 'Configs/defaults.json').read_text())
    settings['settingsVersion'] = 62
    settings['general']['animationDisabled'] = True
    settings['appLauncher']['enableClipboardHistory'] = True
    (profile / 'config/settings.json').write_text(json.dumps(settings))
    env['CLIPHIST_DB_PATH'] = str(profile / 'history.db')
    for text in ('Data Alpha seed', 'Data Beta seed'):
        subprocess.run(['timeout', '10', 'cliphist', 'store'], input=text.encode(), env=env, check=True, timeout=15)
    shell = tree / 'shell.qml'
    cases = []
    def ipc(member, *values, check=True):
        return subprocess.run(['timeout', '10', 'qs', '-p', str(shell), 'ipc', 'call', 'providerData', member, *values],
                              env=env, capture_output=True, text=True, check=check, timeout=15).stdout
    def state():
        return json.loads(ipc('state', check=False))
    def wait(predicate, seconds=10):
        end = time.monotonic() + seconds
        latest = None
        while time.monotonic() < end:
            try:
                latest = state()
                if predicate(latest):
                    return latest
            except json.JSONDecodeError:
                pass
            time.sleep(.03)
        raise AssertionError(json.dumps(latest, ensure_ascii=False))
    def prove(name, predicate):
        observed = wait(predicate)
        cases.append(dict(name=name, passed=True, observed=observed))
        (output / 'result.json').write_text(json.dumps(dict(complete=False, cases=cases), indent=2, ensure_ascii=False))
    with (output / 'run.log').open('x') as log:
        process = subprocess.Popen(['timeout', '--kill-after=5', '100', 'qs', '-p', str(shell)], cwd=tree, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            prove('initial-data-ready', lambda s: s['ready'] and s['clipboardReady'] and s['emojiReady'] and s['settingsReady'])
            ipc('query', '>clip Data ')
            prove('clipboard-initial', lambda s: len(s['rows']) == 2 and all(row['id'] for row in s['rows']))
            ipc('step', 'clip-cached')
            prove('clipboard-cached-during-refresh', lambda s: len(s['cachedDuring']) == 2 and all(r['id'].isdigit() for r in s['cachedDuring']))
            subprocess.run(['timeout', '10', 'cliphist', 'store'], input=b'Data Gamma fresh', env=env, check=True, timeout=15)
            ipc('step', 'clip-refresh')
            prove('clipboard-same-query-completion-selection', lambda s: len(s['rows']) == 3 and s['query'] == '>clip Data '
                  and s['selected'] == s['originalClipboardSelection'])
            # The image row stays hidden, so no row decodes it before the probe.
            ipc('query', '>clip no-such-entry')
            wait(lambda s: s['query'] == '>clip no-such-entry' and not any(r['id'].isdigit() for r in s['rows']))
            subprocess.run(['timeout', '10', 'cliphist', 'store'], input=png((40, 90, 160)), env=env, check=True, timeout=15)
            ipc('step', 'clip-refresh')
            wait(lambda s: s['clipboardItems'] == 4)
            ipc('step', 'image-decode')
            prove('clipboard-image-one-decode-per-item', lambda s: s['imageJobs'] == 1 and s['imageDecoded'] == 1 and s['imageCallbacks'] == 2)
            ipc('query', '>emoji cache-marker')
            ipc('step', 'emoji-data')
            prove('emoji-republish-after-loaded', lambda s: len(s['rows']) == 2 and s['query'] == '>emoji cache-marker')
            ipc('step', 'emoji-refresh')
            prove('emoji-cached-while-loading', lambda s: len(s['cachedDuring']) == 2 and s['cachedDuring'][0]['name'] == 'cache-marker first')
            ipc('step', 'emoji-ready')
            ipc('step', 'emoji-recent')
            wait(lambda s: not s['rows'])
            ipc('step', 'emoji-usage')
            prove('emoji-async-usage-reprojects-recent', lambda s: len(s['rows']) == 1 and s['rows'][0]['name'] == 'cache-marker first')
            ipc('step', 'settings-empty')
            wait(lambda s: not s['rows'])
            ipc('step', 'settings-data')
            prove('settings-index-completion', lambda s: len(s['rows']) == 1 and s['query'] == '>settings general')
            ipc('query', '>win Data Window')
            wait(lambda s: any(r['name'] == 'Data Window Before' for r in s['rows']))
            ipc('step', 'window-title')
            prove('windows-native-title-change', lambda s: any(r['name'] == 'Data Window After' for r in s['rows']) and s['query'] == '>win Data Window')
            ipc('query', '>async stable')
            wait(lambda s: s['rows'] and s['rows'][0]['name'] == 'Loading plugin')
            ipc('step', 'plugin-data')
            prove('plugin-completion-same-query', lambda s: len(s['rows']) == 2 and s['query'] == '>async stable')
            ipc('step', 'plugin-prepend')
            prove('plugin-data-selection-stable', lambda s: len(s['rows']) == 3 and s['selected'] == 'p2')
            ipc('step', 'plugin-refresh')
            prove('plugin-cached-during-refresh', lambda s: len(s['cachedDuring']) == 3)
            ipc('query', '>legacy stable')
            ipc('step', 'legacy-data')
            prove('legacy-plugin-callback-compatible', lambda s: len(s['rows']) == 1 and s['rows'][0]['id'] == 'legacy-ready')
            ipc('step', 'destroy-core')
            prove('persistent-plugin-detached', lambda s: not s['alive'] and s['pluginDetached'])
            before = state()['projections']
            ipc('step', 'publish-closed')
            time.sleep(.1)
            assert state()['projections'] == before
            ipc('step', 'recreate-core')
            wait(lambda s: s['ready'] and s['pluginAttached'])
            ipc('query', '>async stable')
            prove('persistent-plugin-readopted-with-data', lambda s: s['rows'] and s['rows'][0]['id'] == 'closed-data')
        finally:
            ipc('exitControl', check=False)
            process.wait(timeout=10)
    errors = [line for line in (output / 'run.log').read_text().splitlines() if re.search(r'ReferenceError|TypeError|SyntaxError|Binding loop|Cannot assign|Unable to assign', line)]
    result = dict(passed=not errors and process.returncode == 0, complete=True, cases=cases, errors=errors)
    (output / 'result.json').write_text(json.dumps(result, indent=2, ensure_ascii=False))
    print(json.dumps(dict(passed=result['passed'], cases=len(cases), errors=errors), indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
