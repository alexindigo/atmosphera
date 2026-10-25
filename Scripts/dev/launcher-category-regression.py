#!/usr/bin/env python3
"""Real-key scoped-search/category-bar consumers in both launcher hosts."""
import argparse
import importlib.util
import json
from pathlib import Path
import traceback

from launcher_workspace import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('keys', Path(__file__).with_name('launcher-key-owner-e2e.py'))
    keys = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(keys)
    keys.flow.boundary()
    out = ROOT / 'evidence' / args.label
    out.mkdir()
    entries = []
    cases = []
    try:
        for slug, category, name in [('inside', 'Graphics', 'Scope K4 Inside'), ('outside', 'Network', 'Scope K4 Outside')]:
            path = Path.home() / '.local/share/applications' / ('launcher-k4-scope-' + slug + '.desktop')
            assert not path.exists(), path
            path.write_text('[Desktop Entry]\nType=Application\nName=' + name + '\nExec=/usr/bin/true\nCategories=' + category + ';\n')
            entries.append(path)
        baseline = keys.prepare_input_baseline()
        (out / 'input-baseline.json').write_text(json.dumps(baseline, indent=2))
        for host in ('panel', 'overlay'):
            for mode in ('apps-list', 'apps-grid'):
                observations = []
                try:
                    keys.opened(host, mode)
                    keys.flow.wait(lambda: 'Graphics' in keys.state()['categories'], 10)
                    for _ in range(len(keys.state()['categories'])):
                        if keys.state()['category'] == 'Graphics':
                            break
                        keys.chord(15, 29)
                    keys.expect(lambda s: s['category'] == 'Graphics')
                    keys.type_text('Scope K4')
                    before = keys.expect(lambda s: s['query'] == 'Scope K4' and s['resultNames'] == ['Scope K4 Inside'])
                    observations.append(before)
                    assert before['categoryBar']['visible'] and before['categoryBar']['enabled']
                    assert before['categoryBar']['index'] == before['categories'].index('Graphics')
                    for _ in range(len(before['categories'])):
                        if keys.state()['category'] == 'all':
                            break
                        keys.chord(15, 29)
                    after = keys.expect(lambda s: s['category'] == 'all' and s['query'] == 'Scope K4'
                                        and set(s['resultNames']) == {'Scope K4 Inside', 'Scope K4 Outside'})
                    observations.append(after)
                    keys.type_text('zzzz')
                    empty = keys.expect(lambda s: s['query'] == 'Scope K4zzzz' and s['count'] == 0)
                    assert empty['categoryBar']['visible']
                    observations.append(empty)
                    keys.chord(30, 29)
                    keys.chord(14)
                    cleared = keys.expect(lambda s: s['query'] == '' and s['count'] > 0)
                    assert cleared['categoryBar']['visible']
                    observations.append(cleared)
                    row = dict(name=host + '/' + mode, passed=True)
                except Exception as error:
                    row = dict(name=host + '/' + mode, passed=False, error=repr(error), traceback=traceback.format_exc())
                row.update(observations=observations, final=keys.state())
                cases.append(row)
                (out / 'result.json').write_text(json.dumps(dict(complete=False, cases=cases), indent=2))
                print(row['name'], row['passed'], row.get('error', ''), flush=True)
    finally:
        keys.closed()
        for path in entries:
            path.unlink()
    result = dict(passed=all(r['passed'] for r in cases), complete=len(cases) == 4, cases=cases)
    (out / 'result.json').write_text(json.dumps(result, indent=2))
    return 0 if result['passed'] and result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
