#!/usr/bin/env python3
"""Exercise the actual searchable picker in a private shell in the assigned VM."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from presentation_harness import add_execution_arguments, check_execution_paths, run_harness, write_receipt
from qml_probe import bootstrap_fixture


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--workspace', type=Path, required=True)
    add_execution_arguments(parser)
    args = parser.parse_args()
    source, work = args.source.resolve(), args.workspace.resolve()
    check_execution_paths(parser, work, source=source)
    assert Path.home() == Path('/home/tester')
    assert subprocess.check_output(['sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid'], text=True).strip().lower() == os.environ['ACTION_TEST_VM_UUID'].lower()
    assert subprocess.check_output(['systemd-detect-virt', '--vm'], text=True).strip() in ('qemu', 'kvm')
    work.mkdir()
    shell = work / 'shell'
    shutil.copytree(source, shell, ignore=shutil.ignore_patterns('.git', '.envrc', '.qmlls.ini', '__pycache__', '*.bak'))
    # Count actual rebuilds in the disposable copy, not a property transition
    # that could stay true across many full scans.
    widget = shell / 'Widgets/NSearchableComboBox.qml'
    text = widget.read_text()
    anchor = 'function filterModel() {'
    assert text.count(anchor) == 1
    widget.write_text(text.replace(anchor, 'property int __proofFilters: 0\n  ' + anchor + '\n    __proofFilters++;'))
    fixture = source / 'Scripts/dev/fixtures/searchable-combo.qml'
    (shell / 'shell.qml').write_text(bootstrap_fixture(fixture.read_text()))
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software',
               ATMOSPHERA_DEBUG='0', ATMOSPHERA_UPGRADELOG_URL='http://127.0.0.1:9')
    for key, leaf in (('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state')):
        (work / leaf).mkdir()
        env[key] = str(work / leaf)
    config = work / 'config/atmosphera'
    config.mkdir()
    (config / 'settings.json').write_text((source / 'Configs/defaults.json').read_text())
    env.update(ATMOSPHERA_CONFIG_DIR=str(config) + '/', ATMOSPHERA_SETTINGS_FILE=str(config / 'settings.json'))
    execution = run_harness(['dbus-run-session', '--', 'qs', '-p', str(shell), '--no-color'], work, env, args.budget)
    log = (work / 'shell.log').read_text(errors='replace')
    cases = [json.loads(line.split('COMBO_CASE ', 1)[1]) for line in log.splitlines() if 'COMBO_CASE ' in line]
    errors = [line for line in log.splitlines() if re.search(r'Failed to load configuration|TypeError:|ReferenceError:|SyntaxError:|is not a type|is unavailable', line)]
    expected = ['registry-ready-publication', 'stale-no-match', 'explicit-run', 'clamped-navigation', 'changed-navigation', 'wheel-default',
                'move-identity', 'replacement-invalidates', 'pending-rejects', 'bulk-refresh', 'literal-preview',
                 'footer-identity', 'empty-navigation', 'same-index-replacement', 'data-change-identity',
                 'action-selection-supersedes-editor', 'action-clear-supersedes-editor',
                 'action-unsuperseded-editor', 'action-run-supersedes-editor',
                 'action-locale-grouped', 'action-locale-plain', 'action-invalid-restored']
    passed = (execution['exit_code'] == 0 and execution['cleanup_complete'] and not errors
              and [row['name'] for row in cases] == expected and all(row['passed'] for row in cases)
              and 'COMBO_DONE' in log)
    receipt = dict(passed=passed, cases=cases, qml_errors=errors, source_sha256={
        rel: hashlib.sha256((source / rel).read_bytes()).hexdigest() for rel in
        ('Widgets/NSearchableComboBox.qml', 'Widgets/NActionPicker.qml', 'Scripts/dev/fixtures/searchable-combo.qml', 'Scripts/dev/searchable-combo-proof.py')})
    write_receipt(work, receipt, execution)
    print(json.dumps(receipt, indent=2))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
