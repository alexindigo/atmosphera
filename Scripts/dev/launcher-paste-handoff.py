#!/usr/bin/env python3
"""Held native keyboard + destroyed producer: actual destination paste proof."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

from launcher_workspace import ROOT
from launcher_paste_support import png, profile_environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--legacy', action='store_true')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('flow', Path(__file__).with_name('launcher-flow-e2e.py'))
    flow = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(flow)
    flow.boundary()
    output, runtime = ROOT / 'evidence' / args.label, ROOT / 'runtime' / args.label
    output.mkdir()
    tree = runtime / 'tree'
    shutil.copytree(args.source, tree, symlinks=True)
    (tree / 'shell.qml').write_text((Path(__file__).parent / 'fixtures/launcher-paste-held.qml').read_text())
    clipboard = tree / 'Services/Keyboard/ClipboardService.qml'
    text = clipboard.read_text()
    marker = '    id: pasteProc\n'
    assert text.count(marker) == 1
    clipboard.write_text(text.replace(marker, marker + '    onExited: code => console.info("HELD_PASTE_EXIT|" + JSON.stringify({at: Date.now(), code: code}))\n'))
    target = output / 'target'
    target.mkdir()
    def target_state():
        try:
            return json.loads((target / 'state.json').read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return None
    cases = []
    target_env = dict(os.environ, GDK_BACKEND='wayland', GTK_IM_MODULE='wayland')
    with (target / 'run.log').open('x') as target_log:
        target_process = subprocess.Popen(['timeout', '--kill-after=5', '180', 'python3', '-u', '-B',
            str(Path(__file__).parent / 'fixtures/launcher-paste-target.py'), str(target)], env=target_env,
            stdout=target_log, stderr=subprocess.STDOUT)
        try:
            flow.wait(lambda: target_state() and target_state()['active'], 10)
            window = flow.wait(lambda: next((w for w in flow.windows() if w['title'] == 'Launcher Paste Target'), None))
            for kind in (('text',) if args.legacy else ('text', 'clipboard', 'image')):
                flow.command(['niri', 'msg', 'action', 'focus-window', '--id', str(window['id'])])
                flow.wait(lambda: target_state()['active'])
                count = len(target_state()['records'])
                payload = 'Held paste survives producer destruction: ' + kind
                raw = png((12, 34, 56))
                db = runtime / (kind + '.db')
                env = profile_environment(runtime / (kind + '-profile'), tree)
                env.update(CLIPHIST_DB_PATH=str(db), PASTE_KIND=kind, PASTE_TEXT=payload, PASTE_TARGET_ID=str(window['id']))
                subprocess.run(['timeout', '10', 'cliphist', 'store'], input=raw if kind == 'image' else payload.encode(), env=env, check=True, timeout=15)
                listing = subprocess.run(['timeout', '10', 'cliphist', 'list'], env=env, check=True, capture_output=True, text=True, timeout=15).stdout
                env['PASTE_CLIP_ID'] = listing.splitlines()[0].split('\t', 1)[0]
                shell = tree / 'shell.qml'
                def ipc(member, check=True):
                    return flow.command(['qs', '-p', shell, 'ipc', 'call', 'heldPaste', member], check=check)
                def state():
                    return json.loads(ipc('state').stdout)
                log_path = output / (kind + '.log')
                with log_path.open('x') as log:
                    process = subprocess.Popen(['timeout', '--kill-after=5', '30', 'qs', '-p', str(shell), '--no-color'],
                                               env=env, cwd=tree, stdout=log, stderr=subprocess.STDOUT)
                    try:
                        flow.wait(lambda: ipc('state', check=False).stdout.strip(), 10)
                        flow.wait(lambda: state()['active'] and state()['hadKeyboard'] and state()['clipboardReady'] and state()['uiFocused'], 10)
                        flow.press(28)
                        flow.wait(lambda: state()['closing'] and state()['producerDestroyed'] and state()['uiDestroyed'])
                        held = state()
                        assert held['active'] and held['holdKeyboard']
                        time.sleep(.15)
                        assert len(target_state()['records']) == count
                        if not args.legacy:
                            assert held['queued'] == 1
                        flow.wait(lambda: not state()['holdKeyboard'])
                        if args.legacy:
                            time.sleep(.6)
                        else:
                            flow.wait(lambda: len(target_state()['records']) == count + 1, 10)
                        released = state()
                        records = target_state()['records'][count:]
                        exits = [json.loads(x.split('HELD_PASTE_EXIT|', 1)[1]) for x in log_path.read_text().splitlines() if 'HELD_PASTE_EXIT|' in x]
                        assert len(exits) == 1 and exits[0]['code'] == 0, exits
                        if args.legacy:
                            passed = False  # A successful old process still loses the destination paste.
                            assert not records and exits[0]['at'] < released['releaseRequestedAt']
                        else:
                            assert len(records) == 1 and records[0]['active_at_key'] and records[0]['focused_at_key']
                            assert records[0]['key_at'] >= released['nativeReleasedAt'] >= released['releaseRequestedAt']
                            if kind == 'image':
                                assert records[0]['sha256'] == hashlib.sha256(raw).hexdigest()
                            else:
                                assert records[0]['text'] == payload
                            passed = True
                        cases.append(dict(kind=kind, passed=passed, held=held, released=released, consumer=records, process_exits=exits))
                    finally:
                        ipc('exitControl', check=False)
                        process.wait(timeout=10)
        finally:
            (target / 'exit-request').write_text('exit')
            target_process.wait(timeout=10)
    result = dict(passed=all(r['passed'] for r in cases), complete=True, legacy=args.legacy, cases=cases)
    (output / 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
