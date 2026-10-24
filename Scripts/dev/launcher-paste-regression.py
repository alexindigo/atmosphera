#!/usr/bin/env python3
"""Real clipboard text/image and generic emoji auto-paste in both hosts, including a
bystander window and a destination that closes before the paste."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
import traceback

from launcher_workspace import ROOT
from launcher_paste_support import png


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('keys', Path(__file__).with_name('launcher-key-owner-e2e.py'))
    keys = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(keys)
    keys.flow.boundary()
    os.environ['CLIPHIST_DB_PATH'] = str(ROOT / 'runtime/keytable-clipboard.db')
    output = ROOT / 'evidence' / args.label
    output.mkdir()
    target = output / 'target'
    target.mkdir()
    prior = json.loads(keys.flow.command(['qs', '-c', 'atmosphera', 'ipc', 'call', 'state', 'all']).stdout)['settings']['appLauncher']['autoPasteClipboard']
    try:
        baseline = keys.prepare_input_baseline()
        (output / 'input-baseline.json').write_text(json.dumps(baseline, indent=2))
    except BaseException:
        keys.ipc('autoPaste', 'true' if prior else 'false')
        raise
    env = dict(os.environ, GDK_BACKEND='wayland', GTK_IM_MODULE='wayland')
    rows = []
    def target_state():
        try:
            return json.loads((target / 'state.json').read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return None
    def observations():
        return json.loads(keys.ipc('pasteObservations'))
    with (target / 'run.log').open('x') as log:
        process = subprocess.Popen(['timeout', '--kill-after=5', '240', 'python3', '-u', '-B',
                                    str(Path(__file__).parent / 'fixtures/launcher-paste-target.py'), str(target)],
                                   env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            keys.closed()
            keys.flow.wait(lambda: target_state() and target_state()['active'], 10)
            window = keys.flow.wait(lambda: next((w for w in keys.flow.windows() if w['title'] == 'Launcher Paste Target'), None))
            aborted = False
            for host in ('panel', 'overlay'):
                for kind in ('emoji', 'clipboard-text', 'clipboard-image'):
                    try:
                        keys.closed()
                        keys.flow.command(['niri', 'msg', 'action', 'focus-window', '--id', str(window['id'])])
                        keys.flow.wait(lambda: target_state()['active'] and target_state()['focused']
                                       and observations()['focusedId'] == window['id'])
                        keys.flow.keys('29:1', '30:1', '30:0', '29:0', '14:1', '14:0')
                        keys.flow.wait(lambda: target_state()['text'] == '')
                        before_count = len(target_state()['records'])
                        text = 'K4 clipboard payload ' + host
                        raw = png((255, 0, 0) if host == 'panel' else (0, 0, 255))
                        if kind != 'emoji':
                            subprocess.run(['timeout', '10', 'cliphist', 'store'], input=raw if kind == 'clipboard-image' else text.encode(),
                                           env=os.environ, check=True, timeout=15)
                            clip_id = keys.flow.command(['cliphist', 'list']).stdout.splitlines()[0].split('\t', 1)[0]
                        keys.opened(host, 'emoji' if kind == 'emoji' else 'apps-list')
                        if kind != 'emoji':
                            keys.type_text('>clip ' + (text if kind == 'clipboard-text' else ''))
                            keys.expect(lambda s: str(s['clipboardId']) == clip_id)
                        selected = keys.state()
                        expected = selected['autoPasteText'] if kind == 'emoji' else text
                        if kind == 'emoji':
                            assert expected
                        keys.ipc('autoPaste', 'true')
                        session = json.loads(keys.ipc('observePasteSession'))
                        assert session['targetId'] == window['id'] and session['sourceActive'] and session['hadKeyboard'], session
                        keys.chord(28)
                        keys.expect(lambda s: not s['open'])
                        keys.flow.wait(lambda: len(target_state()['records']) == before_count + 1, 10)
                        actual = target_state()['records'][-1]
                        assert actual['active_at_key'] and actual['focused_at_key'], actual
                        if kind == 'clipboard-image':
                            assert actual['kind'] == 'image' and actual['sha256'] == hashlib.sha256(raw).hexdigest()
                            assert actual['width'] == actual['height'] == 2
                        else:
                            assert actual['text'] == actual['consumer_text'] == expected, actual
                        owner = observations()
                        assert len(owner['events']) == 1 and not owner['events'][0]['sourceActive'] and owner['events'][0]['sourceVisible'], owner
                        assert actual['key_at'] >= owner['events'][0]['at'], dict(actual=actual, owner=owner)
                        keys.flow.wait(lambda: observations()['pending'] == 0)
                        time.sleep(.15)
                        assert len(target_state()['records']) == before_count + 1
                        rows.append(dict(name=host + '/' + kind, passed=True, selected=selected,
                                         session=session, owner=owner, consumer=actual, expected_text=expected))
                    except Exception as error:
                        rows.append(dict(name=host + '/' + kind, passed=False, error=repr(error), traceback=traceback.format_exc(),
                                         launcher=keys.state(), owner=observations(), target=target_state()))
                        aborted = True
                    (output / 'result.json').write_text(json.dumps(dict(complete=False, cases=rows), indent=2, ensure_ascii=False))
                    print(rows[-1]['name'], rows[-1]['passed'], rows[-1].get('error', ''), flush=True)
                    if aborted:
                        break
                if aborted:
                    break
        finally:
            keys.ipc('autoPaste', 'true' if prior else 'false')
            keys.closed()
            (target / 'exit-request').write_text('exit')
            process.wait(timeout=10)
    # The destination is the window niri has focused when the launcher opens,
    # also when it opened after a bystander (no explicit focus action). If
    # that window closes before the paste, the payload is only copied.
    if len(rows) == 6 and all(r['passed'] for r in rows):
        for host in ('panel', 'overlay'):
            folders = {name: output / (host + '-' + name) for name in ('bystander', 'target', 'second-target')}
            processes, logs = {}, []
            def window_state(name):
                try:
                    return json.loads((folders[name] / 'state.json').read_text())
                except (FileNotFoundError, json.JSONDecodeError):
                    return None
            def start(name, title):
                folders[name].mkdir()
                log = (folders[name] / 'run.log').open('x')
                logs.append(log)
                processes[name] = subprocess.Popen(['timeout', '--kill-after=5', '180', 'python3', '-u', '-B',
                                                    str(Path(__file__).parent / 'fixtures/launcher-paste-target.py'), str(folders[name]), title],
                                                   env=env, stdout=log, stderr=subprocess.STDOUT)
                keys.flow.wait(lambda: window_state(name) and window_state(name)['active'] and window_state(name)['focused'], 10)
                return keys.flow.wait(lambda: next((w for w in keys.flow.windows() if w['title'] == title and w['is_focused']), None), 10)
            def paste_case(name, target, close_target):
                checks = {}
                # Real native focus only; the shell's view is what is under test.
                keys.flow.wait(lambda: any(w['id'] == target['id'] and w['is_focused'] for w in keys.flow.windows()), 10)
                subprocess.run(['timeout', '10', 'wl-copy', '--', 'K4 focus sentinel ' + host], env=os.environ, check=True, timeout=15)
                keys.opened(host, 'emoji')
                payload = keys.state()['autoPasteText']
                assert payload
                keys.ipc('autoPaste', 'true')
                session = json.loads(keys.ipc('observePasteSession'))
                checks['captured_focused_window'] = session['targetId'] == target['id']
                before = {n: len(window_state(n)['records']) for n in processes}
                if close_target:
                    keys.flow.command(['niri', 'msg', 'action', 'close-window', '--id', str(target['id'])])
                    keys.flow.wait(lambda: all(w['id'] != target['id'] for w in keys.flow.windows()), 10)
                    processes.pop('target').wait(timeout=10)
                keys.chord(28)
                keys.expect(lambda s: not s['open'])
                try:
                    keys.flow.wait(lambda: observations()['pending'] == 0 and observations()['sessions'] == 0, 10)
                except AssertionError:
                    pass
                time.sleep(.3)  # An absence assertion needs an observation interval.
                owner = observations()
                checks['queue_retired'] = owner['pending'] == 0 and owner['sessions'] == 0
                copied = keys.flow.command(['wl-paste', '--no-newline'], check=False).stdout
                checks['clipboard_payload'] = copied == payload
                received = {n: window_state(n)['records'][before[n]:] for n in processes}
                if close_target:
                    checks['nobody_received'] = all(not r for r in received.values())
                else:
                    delivered = received.pop('second-target')
                    checks['target_received_once'] = (len(delivered) == 1 and delivered[0]['text'] == delivered[0]['consumer_text'] == payload
                                                      and delivered[0]['active_at_key'] and delivered[0]['focused_at_key'])
                    checks['bystander_received_nothing'] = all(not r for r in received.values())
                rows.append(dict(name='bystander/' + host + '/' + name, passed=all(checks.values()), checks=checks, session=session,
                                 target_id=target['id'], bystander_id=bystander['id'], received=received, payload=payload,
                                 clipboard=copied, owner=owner))
            try:
                try:
                    keys.closed()
                    bystander = start('bystander', 'Launcher Paste Bystander')
                    target = start('target', 'Launcher Paste Target')
                    paste_case('closed-target-copies-only', target, True)
                    second = start('second-target', 'Launcher Paste Second Target')
                    paste_case('opened-after-bystander-receives', second, False)
                except Exception as error:
                    rows.append(dict(name='bystander/' + host, passed=False, error=repr(error), traceback=traceback.format_exc(),
                                     launcher=keys.state(), owner=observations()))
            finally:
                keys.ipc('autoPaste', 'true' if prior else 'false')
                keys.closed()
                for name in processes:
                    (folders[name] / 'exit-request').write_text('exit')
                for process in processes.values():
                    process.wait(timeout=10)
                for log in logs:
                    log.close()
            (output / 'result.json').write_text(json.dumps(dict(complete=False, cases=rows), indent=2, ensure_ascii=False))
            for row in rows[-2:]:
                print(row['name'], row['passed'], row.get('checks', row.get('error', '')), flush=True)

    # An empty desktop has no paste destination. Preserve the copy operation
    # rather than leaving a committed job permanently waiting for a null ID.
    if len(rows) >= 6 and all(r['passed'] for r in rows[:6]):
        try:
            keys.flow.wait(lambda: not keys.flow.windows() and observations()['focusedId'] is None)
            aborted = False
            for host in ('panel', 'overlay'):
                for kind in ('emoji', 'clipboard-text', 'clipboard-image'):
                    try:
                        text = 'K4 copy-only payload ' + host
                        raw = png((34 if host == 'panel' else 35, 67, 89))
                        if kind != 'emoji':
                            subprocess.run(['timeout', '10', 'cliphist', 'store'], input=raw if kind == 'clipboard-image' else text.encode(),
                                           env=os.environ, check=True, timeout=15)
                            clip_id = keys.flow.command(['cliphist', 'list']).stdout.splitlines()[0].split('\t', 1)[0]
                        keys.opened(host, 'emoji' if kind == 'emoji' else 'apps-list')
                        if kind != 'emoji':
                            keys.type_text('>clip ' + (text if kind == 'clipboard-text' else ''))
                            keys.expect(lambda s: str(s['clipboardId']) == clip_id)
                        expected = keys.state()['autoPasteText'] if kind == 'emoji' else text
                        expected_bytes = raw if kind == 'clipboard-image' else expected.encode()
                        keys.ipc('autoPaste', 'true')
                        session = json.loads(keys.ipc('observePasteSession'))
                        assert session['targetId'] is None and session['sourceActive']
                        keys.chord(28)
                        keys.expect(lambda s: not s['open'])
                        def copied():
                            command = ['wl-paste', '--no-newline']
                            if kind == 'clipboard-image':
                                command.extend(['--type', 'image/png'])
                            result = subprocess.run(['timeout', '5', *command], env=os.environ, capture_output=True, timeout=10)
                            return result.returncode == 0 and result.stdout == expected_bytes
                        keys.flow.wait(copied)
                        keys.flow.wait(lambda: observations()['pending'] == 0 and observations()['sessions'] == 0)
                        rows.append(dict(name='copy-only/' + host + '/' + kind, passed=True, session=session,
                                         clipboard_sha256=hashlib.sha256(expected_bytes).hexdigest(), owner=observations()))
                    except Exception as error:
                        rows.append(dict(name='copy-only/' + host + '/' + kind, passed=False,
                                         error=repr(error), traceback=traceback.format_exc(), owner=observations()))
                        aborted = True
                    (output / 'result.json').write_text(json.dumps(dict(complete=False, cases=rows), indent=2, ensure_ascii=False))
                    print(rows[-1]['name'], rows[-1]['passed'], rows[-1].get('error', ''), flush=True)
                    if aborted:
                        break
                if aborted:
                    break
        finally:
            keys.ipc('autoPaste', 'true' if prior else 'false')
            keys.closed()
    result = dict(passed=len(rows) == 16 and all(r['passed'] for r in rows), complete=len(rows) == 16, cases=rows)
    (output / 'result.json').write_text(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
