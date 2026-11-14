#!/usr/bin/env python3
"""A changed protected console must not strand this runner's captured child."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--guest-profile', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--case', choices=('model', 'client'), default='model')
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location('model_regression', source / 'Scripts/dev/settings-model-regression.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    activate = module.activate_profile
    popen = subprocess.Popen
    children = []
    log = output / 'case/engine.log'

    def changed_console(path):
        profile = activate(path)
        verify = profile.console.verify

        def verify_console(*values, **keywords):
            if log.exists() and log.stat().st_size > 1024 * 1024:
                raise module.ProfileBlocked('injected captured console disappearance')
            return verify(*values, **keywords)

        profile.console.verify = verify_console
        return profile

    def launch(argv, **keywords):
        if Path(argv[0]).name in ('qs', 'quickshell') and '-p' in argv:
            # The actual child is ours and has a new session, just like the
            # fixture. Its log bound triggers cleanup after capture has settled.
            argv = [sys.executable, '-B', '-c',
                    'import sys,time;time.sleep(.3);print("x"*1048577,flush=True);time.sleep(60)']
            child = popen(argv, **keywords)
            children.append(child)
            return child
        return popen(argv, **keywords)

    command = ['model-regression', '--guest-profile', str(args.guest_profile), '--source', str(source),
               '--output', str(output / 'case'), '--case', 'all']
    try:
        if args.case == 'client':
            profile = activate(args.guest_profile)
            def unavailable(*unused, **keywords):
                raise module.ProfileBlocked('injected captured console disappearance')
            profile.console.verify = unavailable
            client_spec = importlib.util.spec_from_file_location('client_harness', source / 'Scripts/dev/bindings-deployment-regression.py')
            client = importlib.util.module_from_spec(client_spec)
            client_spec.loader.exec_module(client)
            with patch.object(client.subprocess, 'Popen', launch):
                try:
                    client.run(['qs', '-p', str(output / 'inert.qml')], timeout=.1)
                except subprocess.TimeoutExpired:
                    pass
                else:
                    raise AssertionError('required client deadline did not occur')
            if len(children) != 1 or children[0].poll() is None:
                raise AssertionError('owned client remains live')
            print('SETTINGS_MODEL_CLEANUP_SELFTEST: PASS (changed console, bounded owned client cleanup)')
            return
        with patch.object(sys, 'argv', command), patch.object(module, 'activate_profile', changed_console), \
                patch.object(module.subprocess, 'Popen', launch):
            code = module.main()
        result = json.loads((output / 'case/result.json').read_text())
        if code != 1 or not result['timed_out'] or not result['owned_child_group_gone']:
            raise AssertionError('interrupted-console cleanup did not finish with a recorded failure')
        if not any('guest/console identity changed' in error for error in result['errors']):
            raise AssertionError('protected-console failure was not recorded separately')
        if len(children) != 1 or children[0].poll() is None:
            raise AssertionError('owned child remains live')
        print('SETTINGS_MODEL_CLEANUP_SELFTEST: PASS (changed console, bounded owned cleanup, durable result)')
    finally:
        # The old runner leaks this synthetic child. Preserve the red result,
        # but never let the rejecting control contaminate subsequent VM work.
        for child in children:
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=5)


if __name__ == '__main__':
    main()
