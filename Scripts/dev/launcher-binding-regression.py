#!/usr/bin/env python3
"""Fault-inject binding scopes against the real guest settings/native editor."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys

from launcher_workspace import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('keys', Path(__file__).with_name('launcher-key-owner-e2e.py'))
    keys = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(keys)
    keys.flow.boundary()
    with keys.configured_settings():
        output = ROOT / 'evidence' / args.label
        output.mkdir()
        original_ipc, original_chord, original_expect = keys.ipc, keys.chord, keys.expect
        base = json.loads((Path.home() / '.config/atmosphera/settings.json').read_text())['general']['keybinds']['keyEnter']
        def saved_binding():
            path = Path.home() / '.config/atmosphera/settings/general.json'
            try:
                return json.loads(path.read_text()).get('keybinds', {}).get('keyEnter', base)
            except (FileNotFoundError, json.JSONDecodeError):
                return base
        def observed():
            return json.loads(original_ipc('getBindings', json.dumps({'names': ['keyEnter']})))['keyEnter']
        rows = []
        initial = observed()
        try:
            for prior in (['Return', 'Enter'], ['Ctrl+Return']):
                with keys.temporary_bindings({'keyEnter': prior}):
                    baseline = keys.prepare_input_baseline()
                    (output / ('input-baseline-' + str(len(rows)) + '.json')).write_text(json.dumps(baseline, indent=2))
                    for stage in ('armActivation', 'chord', 'assertion'):
                        keys.opened('panel', 'apps-list')
                        def injected_ipc(method, *values):
                            if stage == 'armActivation' and method == 'armActivation':
                                raise RuntimeError('injected armActivation failure')
                            return original_ipc(method, *values)
                        def injected_chord(*values):
                            if stage == 'chord':
                                raise RuntimeError('injected chord failure')
                            return original_chord(*values)
                        def injected_expect(predicate):
                            if stage == 'assertion':
                                raise AssertionError('injected assertion failure')
                            return original_expect(predicate)
                        injected = False
                        try:
                            with keys.temporary_bindings({'keyEnter': ['Ctrl+A']}):
                                # Exercise rollback after the override reached disk too.
                                keys.flow.wait(lambda: saved_binding() == ['Ctrl+A'])
                                keys.ipc, keys.chord = injected_ipc, injected_chord
                                keys.ipc('armActivation')
                                keys.chord(30, 29)
                                keys.expect = injected_expect
                                keys.expect(lambda s: s['activations'] == 1)
                        except (RuntimeError, AssertionError) as error:
                            if isinstance(error, keys.BindingRestorationError):
                                raise
                            assert 'injected' in str(error), repr(error)
                            injected = True
                        finally:
                            keys.ipc, keys.chord, keys.expect = original_ipc, original_chord, original_expect
                        assert injected and observed() == prior
                        keys.flow.wait(lambda: saved_binding() == prior)
                        keys.opened('panel', 'apps-list')
                        keys.type_text('abc')
                        keys.expect(lambda s: s['query'] == 'abc')
                        keys.chord(30, 29)
                        keys.expect(lambda s: s['field']['selected'] == 'abc' and s['activations'] == 0)
                        keys.ipc('armActivation')
                        keys.chord(28, *([29] if prior == ['Ctrl+Return'] else []))
                        keys.expect(lambda s: s['activations'] == 1)
                        rows.append(dict(prior=prior, stage=stage, passed=True, restored=observed(),
                                         persisted=saved_binding(), next_case=keys.state()))
                        (output / 'result.json').write_text(json.dumps(dict(complete=False, cases=rows), indent=2))
            # A cleanup error has its own type: the harness must abort instead of
            # treating unknown settings state as an ordinary failed consumer case.
            writes = 0
            def failed_cleanup(method, *values):
                nonlocal writes
                if method == 'bindings':
                    writes += 1
                    if writes == 2:
                        raise RuntimeError('injected restore failure')
                return original_ipc(method, *values)
            keys.ipc = failed_cleanup
            continuation = False
            try:
                with keys.temporary_bindings({'keyEnter': ['Ctrl+A']}):
                    pass
                continuation = True
            except keys.BindingRestorationError:
                pass
            finally:
                keys.ipc = original_ipc
                original_ipc('bindings', json.dumps({'keyEnter': initial}))
            assert not continuation and observed() == initial
            keys.flow.wait(lambda: saved_binding() == initial)
            rows.append(dict(name='cleanup-error-prevents-continuation', passed=True, restored=observed()))
        finally:
            keys.ipc, keys.chord, keys.expect = original_ipc, original_chord, original_expect
            keys.closed()
        result = dict(passed=True, complete=True, cases=rows, original=initial, final=observed(), persisted=saved_binding())
        (output / 'result.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(dict(passed=True, cases=len(rows), final=result['final'], persisted=result['persisted']), indent=2))
        return 0


if __name__ == '__main__':
    raise SystemExit(main())
