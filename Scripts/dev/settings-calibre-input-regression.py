#!/usr/bin/env python3
"""Actual Calibre native page: retain original invalid-record source bytes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'plugins', 'installed', 'original-case', 'output', 'work-root'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    assert str(args.work_root.resolve()).startswith('/home/tester/Projects/atcq/')
    assert subprocess.check_output(['timeout', '10', 'sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid'], timeout=15).decode().strip() == '12f17a02-25e9-474c-9dae-fea092c2d2be'
    args.output.mkdir(parents=True, exist_ok=False)
    args.work_root.mkdir(parents=True, exist_ok=False)
    case = json.loads(args.original_case.read_text())
    assert case['plugin'] == 'calibre-provider'
    seed = dict(case['scenario']['seed'], opaque=dict(keep=True))
    original = (json.dumps(seed)+'\n').encode()
    (args.output/'original-user.json').write_bytes(original)
    probe = args.installed/'i5-calibre-invalid.qml'
    with probe.open('xb') as stream:
        stream.write((args.source/'Scripts/dev/fixtures/plugin-calibre-invalid.qml').read_bytes())
    cases = []
    try:
        for name in ('negative-write', 'preserved'):
            root = args.work_root/name
            config = root/'c'
            plugin = config/'plugins/calibre-provider'
            shutil.copytree(args.plugins/'calibre-provider', plugin)
            (config/'settings/plugins').mkdir(parents=True)
            (root/'cache').mkdir()
            (root/'state').mkdir()
            (config/'settings.json').write_text('{"settingsVersion":62}')
            (config/'plugins.json').write_text('{"version":5,"states":{},"sources":[]}')
            target = config/'settings/plugins/calibre-provider.json'
            target.write_bytes(original)
            before = target.stat()
            for leg in (('write',) if name == 'negative-write' else ('open-cancel-clean-save', 'cold-open-cancel-clean-save')):
                env = dict(os.environ, TMPDIR='/home/tester/Projects/atcq/tmp', QML_DISABLE_DISK_CACHE='1',
                           ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(root/'cache'),
                           ATMOSPHERA_STATE_DIR=str(root/'state'), I5_CALIBRE_MANIFEST=(plugin/'manifest.json').read_text(),
                           I5_CALIBRE_NEGATIVE='1' if name == 'negative-write' else '0')
                result = subprocess.run(['timeout', '30', 'qs', '-p', str(probe), '--no-color'], env=env,
                                        capture_output=True, text=True, timeout=35)
                text = result.stdout+result.stderr
                (args.output/(name+'-'+leg+'.log')).write_text(text)
                if name == 'negative-write':
                    assert result.returncode == 2 and 'clean source may not replace original invalid raw records' in text, text[-6000:]
                    assert target.read_bytes() != original and json.loads(target.read_bytes())['recentlyOpenedFiles'] == []
                else:
                    assert result.returncode == 0 and 'I5_CALIBRE_INVALID: PASS' in text, text[-6000:]
                    assert not any(error in text for error in ('TypeError:', 'ReferenceError:', 'SyntaxError:'))
                    after = target.stat()
                    assert target.read_bytes() == original
                    assert (after.st_ino, after.st_mtime_ns, after.st_mode) == (before.st_ino, before.st_mtime_ns, before.st_mode)
                cases.append(dict(id=name+'-'+leg, status='PASS', rawPreserved=name == 'preserved'))
        report = dict(status='PASS', cases=cases, originalSha256=hashlib.sha256(original).hexdigest(),
                      purpose='invalid original records stay byte-identical; valid numeric trimming remains in full catalog')
        (args.output/'result.json').write_text(json.dumps(report, indent=2)+'\n')
        print('SETTINGS_CALIBRE_INPUT: PASS (original raw bytes, native page Cancel/clean save/cold, rejecting write control)')
    finally:
        probe.unlink()


if __name__ == '__main__':
    main()
