#!/usr/bin/env python3
"""Guest-only native draft and full-profile receipt consumers."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

from guest_profile import activate_profile, protect_owned_process
from probe_files import ProbeFiles
from workspace_guard import require_disk_backed_paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--plugins', type=Path, required=True)
    parser.add_argument('--guest-profile', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    modes = ('ordinary', 'reset', 'draft', 'overlay', 'profile', 'profile-plugin')
    parser.add_argument('--modes', nargs='+', choices=modes, default=modes)
    args = parser.parse_args()
    source, plugins, out = args.source.resolve(), args.plugins.resolve(), args.output.resolve()
    profile = activate_profile(args.guest_profile)
    require_disk_backed_paths(source, plugins, out, os.environ['TMPDIR'])
    out.mkdir(parents=True, exist_ok=False)
    fixture = source/'Scripts/dev/fixtures/settings-scoped-receipts.qml'
    lease = ProbeFiles(source, fixture)
    rows = []

    def launch(env, log):
        child = subprocess.Popen(['dbus-run-session', '--', 'qs', '-p', str(lease.probe), '--no-color'],
                                 env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 start_new_session=True)
        guard = None
        try:
            guard = protect_owned_process(child)
            body, _ = child.communicate(timeout=45)
            log.write_bytes(body)
            return child.returncode, body.decode()
        finally:
            if child.poll() is None:
                if guard:
                    guard.terminate()
                body, _ = child.communicate()
                log.write_bytes(body)

    try:
        for mode in args.modes:
            work = out/mode
            config = work/'c'
            (config/'settings').mkdir(parents=True)
            (work/'tmp').mkdir()
            (config/'settings.json').write_text('{"settingsVersion":62}')
            (config/'plugins.json').write_text('{"version":5,"sources":[],"states":{}}')
            bindings = b'{"environment":"macos","unknown":"bindings-retained"}\n'
            (config/'settings/bindings.json').write_bytes(bindings)
            (config/'settings/ui.json').write_text('{"fontDefaultScale":1.4,"unknown":"ui-retained"}\n')
            if mode == 'overlay':
                (config/'settings/bar.json').write_text('{"widgets":{"left":[{"id":"plugin:shell-profiles","opaque":{"wide":18446744073709551615}}]}}')
            shutil.copytree(plugins/'shell-profiles', config/'plugins/shell-profiles')
            runtime = profile.child_environment('sr-')
            env = dict(os.environ, **runtime, QT_QPA_PLATFORM='wayland', QML_DISABLE_DISK_CACHE='1',
                       ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_SETTINGS_FILE=str(config/'settings.json'),
                       ATMOSPHERA_CACHE_DIR=str(work/'cache'), ATMOSPHERA_STATE_DIR=str(work/'state'),
                       XDG_CONFIG_HOME=str(work/'xdg'), XDG_CACHE_HOME=str(work/'cache'),
                       XDG_STATE_HOME=str(work/'state'), XDG_DATA_HOME=str(work/'data'),
                       TMPDIR=str(work/'tmp'), SCOPED_RECEIPT_MODE=mode)
            try:
                code, text = launch(env, work/'engine.log')
                raw = json.loads((config/'settings/ui.json').read_text())
                assert raw.get('unknown') == 'ui-retained'
                assert (config/'settings/bindings.json').read_bytes() == bindings
                assert not (config/'profiles/blocked').exists()
                if mode == 'overlay' and code == 0:
                    row = json.loads((config/'settings/bar.json').read_text())['widgets']['left'][0]
                    assert row == {'id': 'plugin:shell-profiles', 'opaque': {'wide': 18446744073709551615}}
                default = json.loads((source/'Configs/defaults.json').read_text())['ui']['fontDefaultScale']
                expected = default if mode == 'reset' else 1.8 if mode == 'draft' and code == 0 else 1.6
                assert raw.get('fontDefaultScale', default) == expected
                cold_code, cold = launch(dict(env, SCOPED_RECEIPT_MODE='cold',
                                             SCOPED_RECEIPT_EXPECT=str(expected)), work/'cold.log')
                assert cold_code == 0 and 'SCOPED_RECEIPT: COLD_PASS' in cold
                passed = code == 0 and 'SCOPED_RECEIPT: PASS '+mode in text
                rows.append(dict(mode=mode, status='PASS' if passed else 'FAIL', exit=code,
                                 coldPassed=True, bindingBytesRetained=True, profileNotCopied=True))
                print(json.dumps(rows[-1]), flush=True)
            finally:
                shutil.rmtree(Path(runtime['XDG_RUNTIME_DIR']))
            (out/'result.json').write_text(json.dumps(rows, indent=2)+'\n')
    finally:
        lease.close()
        profile.verify()
    return int(any(row['status'] != 'PASS' for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
