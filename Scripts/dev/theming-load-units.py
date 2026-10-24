#!/usr/bin/env python3
"""Exercise real colour/widget/icon consumers under guest-only transport faults."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from filechooser_isolation import ROOT, enter, guest, profile_env
from theming_oracle import install_file_oracle


def main():
    """Run the isolated fault matrix once, retaining consumer/log/disk outcomes."""
    enter()
    guest()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    assert source.is_relative_to(ROOT / 'sources')
    runtime, output = ROOT / 'runtime' / args.label, ROOT / 'evidence' / args.label
    assert not runtime.exists() and not output.exists()
    output.mkdir(); runtime.mkdir()
    try:
        shell = runtime / 'shell'
        shutil.copytree(source, shell, symlinks=True)
        probe = shell / 'load-test.qml'
        probe.write_text((source / 'Scripts/dev/fixtures/theming-load-failures.qml').read_text())
        install_file_oracle(source, shell)
        # Fault instrumentation belongs only to this disposable runtime. No
        # production command, Python fallback or acceptance predicate is changed.
        service = shell / 'Services/Theming/ColorSchemeService.qml'
        text = service.read_text()
        marker = '["timeout", "10", "python3", "-B", Quickshell.shellDir + "/Scripts/python/src/theming/normalize-scheme.py"]'
        assert text.count(marker) == 1
        service.write_text(text.replace(marker, '[JSON.parse(request.key).dark._fault === "start" ? "/nonexistent-mstandout-normalizer" : "timeout", "10", "python3", "-B", Quickshell.shellDir + "/Scripts/python/src/theming/normalize-scheme.py"]'))
        script = shell / 'Scripts/python/src/theming/normalize-scheme.py'
        shutil.copy2(script, script.with_name('.normalize-original.py'))
        script.write_text('''import io,json,os,runpy,sys,time
from pathlib import Path
from lib.scheme import normalize_scheme
raw=sys.stdin.read(); data=json.loads(raw); mode=data.get('dark',data).get('_fault','')
with open(os.environ['THEME_TEST_WORKER_LOG'],'a') as log: log.write(json.dumps({'fault':mode,'save':'--save' in sys.argv,'tag':data.get('dark',data).get('_tag','')})+'\\n')
if mode=='exit' or (mode=='save-fail' and '--save' in sys.argv): sys.exit(9)
if mode=='timeout': time.sleep(12)
if mode=='slow': time.sleep(.4)
if mode=='bad-json': print('{invalid'); sys.exit(0)
if mode=='bad-snapshot': print('{}'); sys.exit(0)
if mode=='wrong-authored':
 result=normalize_scheme(data); result['dark']['mPrimary']='#123456'; print(json.dumps(result)); sys.exit(0)
sys.stdin=io.StringIO(raw)
runpy.run_path(str(Path(__file__).with_name('.normalize-original.py')),run_name='__main__')
''')
        palettes = {key: json.loads((source / f'Assets/ColorScheme/{name}/{name}.json').read_text()) for key, name in (('a', 'MacOS'), ('b', 'Catppuccin'), ('c', 'Ayu'))}
        profile = runtime / 'profile'
        for name in ('config', 'cache', 'state', 'data', 'tmp'):
            (profile / name).mkdir(parents=True)
        defaults = json.loads((source / 'Configs/defaults.json').read_text())
        defaults['general']['showChangelogOnStartup'] = False
        defaults['colorSchemes']['useWallpaperColors'] = False
        defaults['colorSchemes']['predefinedScheme'] = ''
        (profile / 'config/settings.json').write_text(json.dumps(defaults))
        initial = dict(palettes['a']['dark'], _fault='exit', _tag='first-load')
        initial.pop('mStandout'); initial.pop('mOnStandout')
        (profile / 'config/colors.json').write_text(json.dumps(initial))
        worker_log = output / 'worker.jsonl'
        env = dict(profile_env(profile), THEME_TEST_PALETTES=json.dumps(palettes), THEME_TEST_WORKER_LOG=str(worker_log))
        result = subprocess.run(['timeout', '--kill-after=5', '100', 'qs', '-p', str(probe)], cwd=shell, env=env, capture_output=True, text=True, timeout=110)
        log = result.stdout + result.stderr
        (output / 'run.log').write_text(log)
        cases = [json.loads(line.split('THEME_LOAD_CASE|', 1)[1]) for line in log.splitlines() if 'THEME_LOAD_CASE|' in line]
        reads = [json.loads(line.split('THEMING_FILE_READ|', 1)[1]) for line in log.splitlines() if 'THEMING_FILE_READ|' in line]
        errors = [line for line in log.splitlines() if re.search(r'TypeError|ReferenceError|Cannot assign|Binding loop|Failed to load configuration|is not a type|Unable to assign', line)]
        workers = [json.loads(line) for line in worker_log.read_text().splitlines()] if worker_log.exists() else []
        no_authored_worker = not any(row['tag'] == 'complete-without-worker' for row in workers)
        save_failed = any(row['save'] and row['fault'] == 'save-fail' for row in workers) and not (profile / 'config/colorschemes/Custom/Custom.json').exists()
        warnings_visible = log.count('Colour load rejected; keeping last good colours:') >= 8 and 'Invalid colours JSON' in log
        passed = result.returncode == 0 and 'THEME_LOAD_COMPLETE|' in log and len(cases) >= 16 and all(row['pass'] for row in cases) and not errors and no_authored_worker and save_failed and warnings_visible
        receipt = dict(passed=passed, exit=result.returncode, cases=cases, file_reads=reads, errors=errors, no_authored_worker=no_authored_worker, failed_save_not_written=save_failed, warnings_visible=warnings_visible)
        (output / 'result.json').write_text(json.dumps(receipt, indent=2))
        print(json.dumps(receipt, indent=2))
        return 0 if passed else 1
    finally:
        shutil.rmtree(runtime)


if __name__ == '__main__':
    raise SystemExit(main())
