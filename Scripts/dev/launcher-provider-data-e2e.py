#!/usr/bin/env python3
"""Real query/selection/copy after background history completion, both hosts."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess

from launcher_workspace import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('keys', Path(__file__).with_name('launcher-key-owner-e2e.py'))
    keys = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(keys)
    keys.flow.boundary()
    with keys.probe_session():
        os.environ['CLIPHIST_DB_PATH'] = str(ROOT / 'runtime/keytable-clipboard.db')
        out = ROOT / 'evidence' / args.label
        out.mkdir()
        rows = []
        try:
            for host in ('panel', 'overlay'):
                query = 'Data UI ' + args.label + ' ' + host
                for suffix in ('Alpha', 'Beta'):
                    subprocess.run(['timeout', '10', 'cliphist', 'store'], input=(query + ' ' + suffix).encode(), env=os.environ, check=True, timeout=15)
                keys.opened(host, 'apps-list')
                keys.type_text('>clip ' + query)
                keys.expect(lambda s: s['count'] == 2 and s['clipboardId'])
                keys.chord(108)
                selected = keys.expect(lambda s: s['index'] == 1)
                subprocess.run(['timeout', '10', 'cliphist', 'store'], input=(query + ' Gamma').encode(), env=os.environ, check=True, timeout=15)
                after = keys.flow.wait(lambda: keys.state() if keys.state()['count'] == 3 else None, 12)
                assert after['clipboardId'] == selected['clipboardId'] and after['query'] == '>clip ' + query, after
                keys.chord(28)
                keys.expect(lambda s: not s['open'])
                keys.flow.wait(lambda: keys.flow.command(['wl-paste', '--no-newline']).stdout == selected['selected'])
                rows.append(dict(host=host, passed=True, before=selected, after=after, copied=selected['selected']))
                (out / 'result.json').write_text(json.dumps(dict(complete=False, cases=rows), indent=2))
        finally:
            keys.closed()
        result = dict(passed=True, complete=True, cases=rows)
        (out / 'result.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(dict(passed=True, cases=len(rows)), indent=2))
        return 0


if __name__ == '__main__':
    raise SystemExit(main())
