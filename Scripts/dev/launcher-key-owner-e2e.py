#!/usr/bin/env python3
"""Key-table consumer checks on the assigned launcher VM's console, both hosts.

The guest-only probe supplies competing shortcuts, a focus challenger and a
single-view provider. Input always travels through uinput and real niri. The
activation spy replaces the selected callback for key-routing checks only;
launcher-flow-e2e.py separately proves actual application/window consumers.
"""
import argparse
from contextlib import contextmanager
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(os.environ.get('ATMOSPHERA_LAUNCHER_WORKSPACE', '/home/tester/Projects/atmosphera-launcher-keys'))
spec = importlib.util.spec_from_file_location('flow', Path(__file__).with_name('launcher-flow-e2e.py'))
flow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flow)
flow.ROOT = ROOT
flow.SOCKET = ROOT / 'runtime/input.sock'


def ipc(method, *args):
    return flow.command(['qs', '-c', 'atmosphera', 'ipc', 'call', 'launcherKeys', method, *args]).stdout.strip()


class BindingRestorationError(RuntimeError):
    """The settings state is unknown; dependent cases must not continue."""


@contextmanager
def temporary_bindings(overrides):
    previous = json.loads(ipc('getBindings', json.dumps({'names': list(overrides)})))
    try:
        ipc('bindings', json.dumps(overrides))
        yield
    finally:
        try:
            ipc('bindings', json.dumps(previous))
            actual = json.loads(ipc('getBindings', json.dumps({'names': list(previous)})))
            if actual != previous:
                raise RuntimeError(f'expected {previous!r}, observed {actual!r}')
        except Exception as error:
            raise BindingRestorationError('Temporary key binding restoration failed') from error


def state():
    return json.loads(ipc('state'))


def expect(predicate):
    """Observe native/IME asynchronous delivery at the consumer, never refocus."""
    latest = None
    def ready():
        nonlocal latest
        latest = state()
        return latest if predicate(latest) else None
    try:
        return flow.wait(ready)
    except AssertionError:
        raise AssertionError(json.dumps(latest, ensure_ascii=False)) from None


def chord(code, *mods):
    before = state()
    flow.keys(*[f'{m}:1' for m in mods], f'{code}:1', f'{code}:0', *[f'{m}:0' for m in reversed(mods)])
    if before['open'] and before['field']['focused'] and not before['field']['composing']:
        expect(lambda s: s['keySerial'] > before['keySerial'] or not s['open'])


def type_text(text):
    flow.command(['ydotool', 'type', '--key-delay', '2', '--', text])


def closed():
    if state()['open']:
        # The real compositor shortcut returns >provider modes to apps before
        # it closes apps. Respect that public toggle contract during resets.
        if state()['query'].startswith('>'):
            flow.keys(*flow.SHORTCUT)
            flow.wait(lambda: state()['open'] and state()['query'] == '')
        flow.keys(*flow.SHORTCUT)
        flow.wait(lambda: not state()['open'])
        time.sleep(.25)


def opened(host, mode):
    closed()
    ipc('configure', json.dumps(dict(host=host, mode=mode)))
    flow.keys(*flow.SHORTCUT)
    flow.wait(lambda: state()['open'] and state()['nativeActive'])
    prefix = {'emoji': '>emoji face ', 'clipboard': '>clip ', 'settings': '>settings ',
              'single': '>keyfixture ', 'session': 'reboot '}.get(mode, '')
    if prefix:
        type_text(prefix)
        expect(lambda s: s['query'] == prefix)
    flow.wait(lambda: state()['count'] > 0 and (mode != 'clipboard' or state()['clipboardId']))
    ipc('observe', 'false')
    return state(), prefix


def replace(text):
    chord(30, 29)
    type_text(text)
    flow.wait(lambda: state()['query'] == text)


def require(condition, details):
    assert condition, json.dumps(details, ensure_ascii=False)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--label', required=True)
    p.add_argument('--red', action='store_true', help='Changed-contract cases on the pre-change source')
    p.add_argument('--with-original', action='store_true', help='Also execute the original eight consumer cases in both hosts')
    args = p.parse_args()
    flow.boundary()
    os.environ['CLIPHIST_DB_PATH'] = str(ROOT / 'runtime/keytable-clipboard.db')
    if not args.red:
        for i in range(8):
            subprocess.run(['timeout', '10', 'cliphist', 'store'], input=f'K1 table clipboard {i}',
                           text=True, check=True, timeout=15)
    output = ROOT / 'evidence' / args.label
    output.mkdir()
    cases = []

    def case(name, body):
        try:
            details = body()
            passed, error = True, None
        except BindingRestorationError:
            raise
        except (AssertionError, RuntimeError, subprocess.SubprocessError) as exc:
            details = None
            passed, error = False, str(exc)
        snapshot = state()
        row = dict(name=name, passed=passed, error=error, final=snapshot, details=details)
        cases.append(row)
        (output / 'result.json').write_text(json.dumps(dict(passed=all(c['passed'] for c in cases), cases=cases), indent=2))
        print(name, 'PASS' if passed else 'FAIL', error or '', flush=True)

    try:
        for host in ('panel', 'overlay'):
            for mode in (('apps-grid',) if args.red else ('apps-list', 'apps-grid', 'emoji', 'clipboard', 'settings', 'session', 'single')):
                def editing():
                    _, prefix = opened(host, mode)
                    text = prefix + ('Launcher Flow Alpha' if mode.startswith('apps-') else 'red blue')
                    replace(text)
                    chord(102)  # Home edits; must not change selection.
                    expect(lambda s: s['field']['cursor'] == 0)
                    chord(107, 42)  # Shift+End selects native text.
                    expect(lambda s: s['field']['selected'] == text)
                    chord(106)  # Right collapses selection, including grids.
                    expect(lambda s: s['field']['cursor'] == len(text) and not s['field']['selected'])
                    chord(105)
                    expect(lambda s: s['field']['cursor'] == len(text) - 1)
                    chord(111)  # Delete edits one character, not a result action.
                    expect(lambda s: s['query'] == text[:-1])
                case(f'{host}/{mode}/native-home-selection-right-delete', editing)

                if not args.red:
                    def characters_and_backspace():
                        _, prefix = opened(host, mode)
                        text = prefix + 'red 42 !?'
                        replace(text)
                        require(state()['field']['text'] == text, state())
                        chord(14)
                        expect(lambda s: s['query'] == text[:-1])
                        chord(105)
                        expect(lambda s: s['field']['cursor'] == len(text) - 2)
                        chord(106)
                        expect(lambda s: s['field']['cursor'] == len(text) - 1)
                    case(f'{host}/{mode}/row-1-2-characters-backspace', characters_and_backspace)

                    def word_editing():
                        _, prefix = opened(host, mode)
                        text = prefix + 'red blue'
                        replace(text)
                        chord(105, 29)
                        expect(lambda s: s['field']['cursor'] == len(text) - 4)
                        chord(106, 29, 42)
                        expect(lambda s: s['field']['selected'] == 'blue')
                        chord(106)
                        expect(lambda s: s['field']['cursor'] == len(text) and not s['field']['selected'])
                        chord(14, 29)
                        expect(lambda s: s['query'] == text[:-4])
                        chord(105, 29)
                        expect(lambda s: s['field']['cursor'] == len(prefix))
                        chord(111, 29)
                        expect(lambda s: s['query'] == prefix)
                        replace(text)
                        chord(105, 42)
                        expect(lambda s: s['field']['selected'] == 'e')
                        chord(106, 42)
                        expect(lambda s: not s['field']['selected'])
                    case(f'{host}/{mode}/row-3-native-word-selection-delete', word_editing)

                    def clipboard_undo():
                        _, prefix = opened(host, mode)
                        text = prefix + 'red blue'
                        replace(text)
                        chord(30, 29)
                        expect(lambda s: s['field']['selected'] == text)
                        chord(46, 29)
                        flow.wait(lambda: flow.command(['wl-paste', '--no-newline']).stdout == text)
                        chord(45, 29)
                        expect(lambda s: s['query'] == '')
                        ipc('observe', 'true')
                        chord(47, 29)
                        flow.wait(lambda: state()['query'] == text)
                        require(state()['shortcutHits'] == 0, state())
                        chord(44, 29)
                        expect(lambda s: s['query'] == '')
                        chord(44, 29, 42)
                        expect(lambda s: s['query'] == text)
                        # Non-ASCII characters must use native committed text too.
                        subprocess.run(['timeout', '10', 'wl-copy', '--', 'é Ж 中文'], check=True, timeout=15)
                        chord(30, 29)
                        chord(47, 29)
                        flow.wait(lambda: state()['query'] == 'é Ж 中文')
                        require(state()['field']['text'] == 'é Ж 中文', state())
                    case(f'{host}/{mode}/row-4-clipboard-undo-redo-unicode', clipboard_undo)

                    def navigation():
                        before, _ = opened(host, mode)
                        step = before['columns'] if before['layout'] == 'grid' else 1
                        expected = min(step, before['count'] - 1) if before['count'] > step else 0
                        if before['single']:
                            expected = 0
                        chord(108)
                        expect(lambda s: s['index'] == expected)
                        chord(103)
                        expect(lambda s: s['index'] == 0)
                        require(state()['query'] == before['query'] and state()['field']['focused'], state())
                    case(f'{host}/{mode}/row-7-up-down', navigation)

                    def page_and_endpoints():
                        before, _ = opened(host, mode)
                        page = 1 if before['single'] else max(1, int(before['viewHeight'] // before['rowHeight'])) * (before['columns'] if before['layout'] == 'grid' else 1)
                        chord(109)
                        expect(lambda s: s['index'] == min(page, before['count'] - 1))
                        chord(104)
                        expect(lambda s: s['index'] == 0)
                        chord(107, 29)
                        expect(lambda s: s['index'] == before['count'] - 1)
                        chord(102, 29)
                        expect(lambda s: s['index'] == 0 and s['field']['cursor'] == before['field']['cursor'])
                    case(f'{host}/{mode}/row-8-9-visible-page-first-last', page_and_endpoints)

                def tab_items():
                    before, _ = opened(host, mode)
                    chord(15)
                    expected = 1 if before['count'] > 1 else 0
                    after = expect(lambda s: s['index'] == expected)
                    require(after['index'] == expected and after['category'] == before['category'], dict(before=before, after=after))
                    chord(15, 42)
                    expect(lambda s: s['index'] == 0)
                case(f'{host}/{mode}/tab-items', tab_items)

                if not args.red:
                    def categories():
                        before, _ = opened(host, mode)
                        chord(15, 29)
                        if before['showCategories']:
                            i = before['categories'].index(before['category'])
                            after = expect(lambda s: s['category'] == before['categories'][(i + 1) % len(before['categories'])])
                            require(after['category'] == before['categories'][(i + 1) % len(before['categories'])], dict(before=before, after=after))
                        else:
                            after = state()
                            require(after['category'] == before['category'] and after['index'] == before['index'], dict(before=before, after=after))
                        chord(15, 29, 42)
                        expect(lambda s: s['category'] == before['category'])
                    case(f'{host}/{mode}/row-11-categories', categories)

                    def removal():
                        before, _ = opened(host, mode)
                        chord(111, 42)
                        if mode == 'clipboard':
                            flow.wait(lambda: state()['count'] == before['count'] - 1)
                            lines = flow.command(['cliphist', 'list']).stdout.splitlines()
                            require(not any(line.split('\t', 1)[0] == str(before['clipboardId']) for line in lines), state())
                        else:
                            require(state()['query'] == before['query'] and state()['count'] == before['count'], state())
                    case(f'{host}/{mode}/row-12-remove-or-consumed-noop', removal)

                def focus_and_competition():
                    opened(host, mode)
                    stolen = json.loads(ipc('stealFocus'))
                    require(stolen['field']['focused'], stolen)
                    ipc('observe', 'true')
                    ipc('armActivation')
                    chord(28)
                    expect(lambda s: s['activations'] == 1 and s['shortcutHits'] == 0)
                    chord(96)
                    expect(lambda s: s['activations'] == 2 and s['shortcutHits'] == 0)
                    chord(1)
                    flow.wait(lambda: not state()['open'])
                    s = state()
                    require(s['closes'] == 1 and s['shortcutHits'] == 0, s)
                case(f'{host}/{mode}/focus-and-competing-shortcuts', focus_and_competition)

            if not args.red:
                def ime():
                    opened(host, 'apps-list')
                    ipc('observe', 'true')
                    ipc('armActivation')
                    try:
                        flow.command(['fcitx5-remote', '-s', 'pinyin'])
                        flow.command(['fcitx5-remote', '-o'])
                        require(flow.command(['fcitx5-remote', '-n']).stdout.strip() == 'pinyin', {'error': 'Pinyin input method unavailable'})
                        type_text('ni')
                        flow.wait(lambda: bool(state()['field']['preedit']))
                        composing = state()
                        require(composing['query'] == '' and composing['field']['composing'], composing)
                        chord(28)
                        flow.wait(lambda: not state()['field']['preedit'])
                        committed_enter = state()
                        require(committed_enter['open'] and committed_enter['query'] and committed_enter['activations'] == 0 and committed_enter['shortcutHits'] == 0, committed_enter)
                        flow.command(['fcitx5-remote', '-c'])
                        chord(30, 29)
                        chord(14)
                        expect(lambda s: s['query'] == '')
                        flow.command(['fcitx5-remote', '-s', 'pinyin'])
                        flow.command(['fcitx5-remote', '-o'])
                        type_text('hao')
                        flow.wait(lambda: bool(state()['field']['preedit']))
                        before_cancel = state()
                        chord(1)
                        flow.wait(lambda: not state()['field']['preedit'])
                        cancelled = state()
                        require(cancelled['open'] and cancelled['query'] == '' and cancelled['closes'] == 0 and cancelled['shortcutHits'] == 0, cancelled)
                        type_text('ni')
                        flow.wait(lambda: bool(state()['field']['preedit']))
                        chord(57)
                        flow.wait(lambda: bool(state()['query']))
                        chinese = state()
                        require(any(ord(c) > 127 for c in chinese['query']) and chinese['query'] == chinese['field']['text'], chinese)
                        return dict(composing=composing, committed_enter=committed_enter, before_cancel=before_cancel, cancelled=cancelled, chinese=chinese)
                    finally:
                        flow.command(['fcitx5-remote', '-s', 'keyboard-us'])
                        flow.command(['fcitx5-remote', '-c'])
                case(f'{host}/fcitx-pinyin-preedit-enter-escape-commit', ime)

                def custom_binding():
                    before, _ = opened(host, 'apps-list')
                    with temporary_bindings({'keyEnter': ['Ctrl+A']}):
                        ipc('armActivation')
                        chord(30, 29)
                        expect(lambda s: s['activations'] == 1 and not s['field']['selected'])
                case(f'{host}/custom-command-beats-editing', custom_binding)

                def unbound_and_printable_shortcuts():
                    opened(host, 'apps-list')
                    ipc('observe', 'true')
                    replace('a')
                    before = state()
                    chord(59)  # Unbound F1 is a consumed no-op, not shell help.
                    after = state()
                    require(after['shortcutHits'] == 0 and after['query'] == 'a' and after['index'] == before['index'], after)
                case(f'{host}/printable-and-unbound-shortcut-isolation', unbound_and_printable_shortcuts)

                def hidden_closed():
                    opened(host, 'apps-list')
                    replace('Launcher Flow')
                    ipc('hide', 'true')
                    before = state()
                    type_text('z')
                    chord(28)
                    time.sleep(.1)  # An absence assertion needs an observation interval.
                    require(state()['query'] == before['query'] and state()['activations'] == before['activations'], state())
                    ipc('hide', 'false')
                    require(state()['field']['focused'], state())
                    chord(1)
                    flow.wait(lambda: not state()['open'])
                    before = state()
                    type_text('z')
                    chord(28)
                    time.sleep(.1)
                    require(state() == before, dict(before=before, after=state()))
                case(f'{host}/hidden-closed-no-delivery', hidden_closed)

        if not args.red:
            def migration():
                result = json.loads(ipc('migrationCases'))
                require(all(row['pass'] for row in result['rows']), result)
                require(result['version'] == 62 and result['remove'] == ['Shift+Del'], result)
                return result
            case('remove-migration-default-custom-empty-idempotent', migration)

        if args.with_original:
            for host in ('panel', 'overlay'):
                closed()
                ipc('configure', json.dumps(dict(host=host, mode='apps-list')))
                rc = flow.run(args.label + '-original-' + host, extra_observer=state, native_handoff=host == 'overlay')
                case(host + '/original-eight-consumer-cases', lambda: require(rc == 0, dict(exit=rc)))
    finally:
        closed()
    result = dict(passed=all(c['passed'] for c in cases), cases=cases)
    (output / 'result.json').write_text(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
