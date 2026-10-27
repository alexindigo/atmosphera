#!/usr/bin/env python3
"""A committed paste never fires late (decisions #3), both hosts, real GTK windows.

The destination is focused when the launcher opens; niri's layout focus moves
to a bystander while the launcher still owns the keyboard, so the release
hands the keyboard to the bystander. Each job has a 2 s deadline from the launcher's
native keyboard release: refocusing the destination before it pastes once;
after it, or once a new launcher session starts, the job only copies and no
key is sent. With focus never returning, the copy still happens — driven by
the deadline alone (the QML timer may fire somewhat after it; a paste is
never sent once the deadline has passed, whoever runs the queue).
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
import traceback

from launcher_workspace import ROOT

DEADLINE_MS = 2000


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('keys', Path(__file__).with_name('launcher-key-owner-e2e.py'))
    keys = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(keys)
    flow = keys.flow
    flow.boundary()
    with keys.configured_settings():
        output = ROOT / 'evidence' / args.label
        output.mkdir()
        prior = json.loads(flow.command(['qs', '-c', 'atmosphera', 'ipc', 'call', 'state', 'all']).stdout)['settings']['appLauncher']['autoPasteClipboard']
        env = dict(os.environ, GDK_BACKEND='wayland', GTK_IM_MODULE='wayland')
        fixture = Path(__file__).parent / 'fixtures/launcher-paste-target.py'
        rows = []

        def observations():
            return json.loads(keys.ipc('pasteObservations'))

        def clipboard():
            return flow.command(['wl-paste', '--no-newline'], check=False).stdout

        try:
            baseline = keys.prepare_input_baseline()
            (output / 'input-baseline.json').write_text(json.dumps(baseline, indent=2))
            assert not flow.windows(), 'Preserve unexpected windows; run on an empty console desktop'
            for host in ('panel', 'overlay'):
                folders = {name: output / (host + '-' + name) for name in ('bystander', 'target')}
                processes, logs = {}, []

                def state(name):
                    try:
                        return json.loads((folders[name] / 'state.json').read_text())
                    except (FileNotFoundError, json.JSONDecodeError):
                        return None

                def start(name, title):
                    folders[name].mkdir()
                    log = (folders[name] / 'run.log').open('x')
                    logs.append(log)
                    processes[name] = subprocess.Popen(['timeout', '--kill-after=5', '300', 'python3', '-u', '-B', str(fixture),
                                                        str(folders[name]), title], env=env, stdout=log, stderr=subprocess.STDOUT)
                    flow.wait(lambda: state(name) and state(name)['active'], 10)
                    return flow.wait(lambda: next((w for w in flow.windows() if w['title'] == title and w['is_focused']), None), 10)

                def focus(window):
                    flow.command(['niri', 'msg', 'action', 'focus-window', '--id', str(window['id'])])

                def native_focused(window):
                    return any(w['id'] == window['id'] and w['is_focused'] for w in flow.windows())

                def records():
                    return {name: list(state(name)['records']) for name in processes}

                def commit(target, bystander):
                    """Open with the target focused, move native focus away, Enter."""
                    keys.closed()
                    focus(target)
                    flow.wait(lambda: native_focused(target) and state('target')['active'], 10)
                    sentinel = 'K5 deadline sentinel ' + host + ' ' + str(time.time_ns())
                    subprocess.run(['timeout', '10', 'wl-copy', '--', sentinel], env=os.environ, check=True, timeout=15)
                    flow.wait(lambda: clipboard() == sentinel)
                    keys.opened(host, 'emoji')
                    payload = keys.state()['autoPasteText']
                    assert payload
                    keys.ipc('autoPaste', 'true')
                    session = json.loads(keys.ipc('observePasteSession'))
                    # niri reports no focused window while the launcher layer owns
                    # the keyboard; this moves its layout focus, which receives the
                    # keyboard on release.
                    focus(bystander)
                    time.sleep(.2)
                    launcher = keys.state()
                    assert launcher['open'] and launcher['nativeActive'], launcher
                    before = records()
                    keys.chord(28)
                    keys.expect(lambda s: not s['open'])
                    released = flow.wait(lambda: observations()['events'], 10)[0]['at']
                    flow.wait(lambda: native_focused(bystander) and state('bystander')['active'], 5)
                    return dict(payload=payload, session=session, launcher_after_refocus=launcher, before=before, released_at=released)

                def until(released, ms):
                    remaining = released + ms - time.time() * 1000
                    if remaining > 0:
                        time.sleep(remaining / 1000)

                def received(before):
                    now = records()
                    return {name: now[name][len(before[name]):] for name in now}

                def case(name, body):
                    try:
                        details = body()
                        checks = details.pop('checks')
                        row = dict(name=host + '/' + name, passed=all(checks.values()), checks=checks, **details)
                    except Exception as error:
                        row = dict(name=host + '/' + name, passed=False, error=repr(error), traceback=traceback.format_exc(),
                                   owner=observations(), launcher=keys.state())
                    rows.append(row)
                    (output / 'result.json').write_text(json.dumps(dict(complete=False, cases=rows), indent=2, ensure_ascii=False))
                    print(row['name'], row['passed'], row.get('checks', row.get('error')), flush=True)

                try:
                    bystander = start('bystander', 'Launcher Deadline Bystander')
                    target = start('target', 'Launcher Deadline Target')

                    def expires_without_focus_event():
                        c = commit(target, bystander)
                        # Native focus stays on the bystander: only the deadline can act.
                        copied = flow.wait(lambda: clipboard() == c['payload'] and observations()['pending'] == 0, 4)
                        copied_at = time.time() * 1000
                        at_copy = dict(owner=observations(), received=received(c['before']),
                                       bystander_focused=native_focused(bystander))
                        time.sleep(.5)  # An absence assertion needs an observation interval.
                        after = dict(owner=observations(), clipboard=clipboard(), received=received(c['before']))
                        return dict(checks=dict(
                            captured_target=c['session']['targetId'] == target['id'],
                            copied_after_deadline=bool(copied) and copied_at >= c['released_at'] + DEADLINE_MS,
                            focus_never_returned=at_copy['bystander_focused'],
                            retired=after['owner']['pending'] == 0 and after['owner']['sessions'] == 0,
                            nothing_pasted=all(not v for v in after['received'].values()),
                            clipboard_kept=after['clipboard'] == c['payload']), commit=c, copied_after_ms=copied_at - c['released_at'],
                            at_copy=at_copy, after=after)
                    case('expires-without-focus-event-copies-only', expires_without_focus_event)

                    def late_refocus():
                        c = commit(target, bystander)
                        until(c['released_at'], DEADLINE_MS + 100)
                        refocused_at = time.time() * 1000
                        focus(target)
                        flow.wait(lambda: native_focused(target) and state('target')['active'], 10)
                        time.sleep(.8)  # An absence assertion needs an observation interval.
                        after = dict(owner=observations(), clipboard=clipboard(), received=received(c['before']))
                        return dict(checks=dict(
                            captured_target=c['session']['targetId'] == target['id'],
                            refocused_after_deadline=refocused_at >= c['released_at'] + DEADLINE_MS,
                            nothing_pasted_after_refocus=all(not v for v in after['received'].values()),
                            retired=after['owner']['pending'] == 0 and after['owner']['sessions'] == 0,
                            clipboard_payload=after['clipboard'] == c['payload']), commit=c,
                            refocused_after_ms=refocused_at - c['released_at'], after=after)
                    case('late-refocus-copies-only', late_refocus)

                    def refocus_within():
                        c = commit(target, bystander)
                        until(c['released_at'], 800)
                        pending = observations()
                        focus(target)
                        flow.wait(lambda: len(received(c['before'])['target']) >= 1, 5)
                        time.sleep(.8)
                        got = received(c['before'])
                        owner = observations()
                        delivered = got['target']
                        return dict(checks=dict(
                            waiting_before_refocus=pending['pending'] == 1,
                            target_received_once=len(delivered) == 1 and delivered[0]['text'] == c['payload']
                            and delivered[0]['consumer_text'].endswith(c['payload'])
                            and delivered[0]['active_at_key'] and delivered[0]['focused_at_key'],
                            paste_before_deadline=delivered[0]['key_at'] < c['released_at'] + DEADLINE_MS if delivered else False,
                            bystander_received_nothing=not got['bystander'],
                            retired=owner['pending'] == 0 and owner['sessions'] == 0), commit=c, received=got, owner=owner)
                    case('refocus-within-deadline-pastes-once', refocus_within)

                    def two_jobs():
                        c = commit(target, bystander)
                        until(c['released_at'], 1000)
                        second_text = 'K5 second job ' + host
                        second = json.loads(keys.ipc('queuePasteText', second_text))
                        until(c['released_at'], DEADLINE_MS + 400)
                        between = dict(owner=observations(), clipboard=clipboard(), received=received(c['before']))
                        focus(target)
                        flow.wait(lambda: len(received(c['before'])['target']) >= 1, 5)
                        time.sleep(.8)
                        got = received(c['before'])
                        owner = observations()
                        delivered = got['target']
                        return dict(checks=dict(
                            second_enqueued_later=second['at'] >= c['released_at'] + 900,
                            first_copied_at_its_deadline=between['clipboard'] == c['payload'] and between['owner']['pending'] == 1,
                            nothing_pasted_between=all(not v for v in between['received'].values()),
                            second_pasted_once=len(delivered) == 1 and delivered[0]['text'] == second_text
                            and delivered[0]['consumer_text'].endswith(second_text)
                            and delivered[0]['active_at_key'] and delivered[0]['focused_at_key'],
                            bystander_received_nothing=not got['bystander'],
                            retired=owner['pending'] == 0 and owner['sessions'] == 0), commit=c, second=second,
                            between=between, received=got, owner=owner)
                    case('two-jobs-separate-deadlines', two_jobs)

                    def new_session():
                        c = commit(target, bystander)
                        until(c['released_at'], 300)
                        waiting = observations()
                        flow.keys(*flow.SHORTCUT)  # the real launcher shortcut starts a new session
                        copied = flow.wait(lambda: clipboard() == c['payload'] and observations()['pending'] == 0, 5)
                        copied_at = time.time() * 1000
                        during = dict(owner=observations(), clipboard=clipboard(), received=received(c['before']), copied_at=copied_at)
                        flow.wait(lambda: keys.state()['open'], 10)
                        keys.closed()
                        focus(target)
                        flow.wait(lambda: native_focused(target) and state('target')['active'], 10)
                        time.sleep(.8)
                        got = received(c['before'])
                        owner = observations()
                        return dict(checks=dict(
                            waiting_before_new_session=waiting['pending'] == 1,
                            copied_when_new_session_started=bool(copied) and during['owner']['pending'] == 0,
                            before_deadline=copied_at < c['released_at'] + DEADLINE_MS,
                            nothing_pasted=all(not v for v in got.values()),
                            retired=owner['pending'] == 0 and owner['sessions'] == 0), commit=c, waiting=waiting,
                            during=during, received=got, owner=owner)
                    case('new-session-copies-only', new_session)
                finally:
                    keys.ipc('autoPaste', 'true' if prior else 'false')
                    keys.closed()
                    for name in processes:
                        (folders[name] / 'exit-request').write_text('exit')
                    for process in processes.values():
                        process.wait(timeout=10)
                    for log in logs:
                        log.close()
        finally:
            keys.ipc('autoPaste', 'true' if prior else 'false')
            keys.closed()
        result = dict(passed=len(rows) == 10 and all(r['passed'] for r in rows), complete=len(rows) == 10, cases=rows)
        (output / 'result.json').write_text(json.dumps(result, indent=2, ensure_ascii=False))
        return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
