#!/usr/bin/env python3
"""Guest-only regression: file chooser save and path cases through xdg-desktop-portal (M20).

usage: filechooser-portal-regression.py --source TREE --work DIR --output DIR

Run in the Qt612 niri VM (arch-niri-atmosphera-qt612-color on ark.home), never on
the host. --work must not exist: the script copies TREE to WORK/shell, writes the
shell profile to WORK/profile and a fixture folder to WORK/fc/downloads. TREE is
never modified. --output must not exist and receives result.json.

Preconditions (not started here): ydotoold answering on
/run/user/1000/.ydotool_socket, no qs running, xdg-desktop-portal active,
at least 64 MiB free on /run/user/1000. The script never calls sudo.

The script starts its own test shell as the transient unit fcreg-<output
basename>-shell, restarts xdg-desktop-portal once the shell owns
org.freedesktop.impl.portal.desktop.atmosphera, and stops every unit it started
in a finally block. xdg-desktop-portal is left running.

Cases (M16 cases 1-7, 9 and 10; case 8, the double-click, is a manual check
recorded in the M16/M19 evidence and is not run here):
  1  SaveFile, fixture folder, plain.html; Enter in the name field -> 0, .../plain.html
  2  SaveFile, 日本語.html -> .../%E6%97%A5%E6%9C%AC%E8%AA%9E.html
  3  SaveFile, a#b?c%20d e.html -> .../a%23b%3Fc%2520d%20e.html
  4  SaveFile, .hidden.html; Enter -> overwrite bar (no response for 5 s); Replace -> 0
  5  SaveFile, existing-dir; Enter -> inline error (no response for 5 s); Escape -> 1, no uris
  6  SaveFile, current_file existing.html; Enter -> overwrite bar; Replace -> 0, existing.html
  7  SaveFile, unterminated current_folder (no NUL), plain.html -> 0, exactly file:///home/tester/plain.html
  9  OpenFile, navigate to the fixture folder, select existing.html, Select -> 0
  10 SaveFiles, a.txt and b.txt added with Enter, Save All -> 0, two uris

Keys and pointer input go through ydotool (pointer coordinates are the
screenshot pixels halved). wtype is not used. Each saved file is written with
known content as a browser would, read back, and removed when the script created
it. A case whose target already exists before it starts fails with a
precondition note and is not run.

Exit: 0 when every case and the cleanup pass; 1 when a case or the cleanup fails;
3 on a setup or precondition failure (the run is not evaluated).
"""
import argparse
from dataclasses import dataclass, field
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
import urllib.parse
import uuid

HOME = '/home/tester'
RUNTIME = '/run/user/1000'
YDOTOOL_SOCKET = f'{RUNTIME}/.ydotool_socket'
MIN_FREE_BYTES = 64 * 1024 * 1024
PORTAL_IMPL = 'org.freedesktop.impl.portal.desktop.atmosphera'
BUS = 'org.freedesktop.portal.Desktop'
OBJ = '/org/freedesktop/portal/desktop'
FC_IFACE = 'org.freedesktop.portal.FileChooser'
REQ_IFACE = 'org.freedesktop.portal.Request'
SELF = Path(__file__).resolve()

CALL_TIMEOUT = 40   # seconds, inside the portal-call child
DIALOG_WAIT = 4     # seconds after the call starts before the first input
QUIET = 5           # seconds a dialog must stay open after Enter (overwrite bar, inline error)
SETTLE = 40         # seconds allowed for the call to end after the steps

ENTER = ('28:1', '28:0')
ESCAPE = ('1:1', '1:0')
CTRL_A = ('29:1', '30:1', '30:0', '29:0')

# Screenshot pixels (1280x800). ydotool absolute coordinates are half of these.
PX = {
    'name': (500, 711),
    'location': (650, 144),
    'replace': (1020, 663),
    'open_tile': (425, 240),
    'open_select': (1010, 714),
    'open_cancel': (902, 714),
    'save_cancel': (942, 711),
    'multi_accept': (1017, 711),
    'multi_cancel': (917, 711),
}
CANCEL_FOR = {'SaveFile': 'save_cancel', 'OpenFile': 'open_cancel', 'SaveFiles': 'multi_cancel'}

FIXTURE_EXISTING = b'M20 fixture existing.html\n'
FIXTURE_HIDDEN = b'M20 fixture .hidden.html\n'


class SetupError(RuntimeError):
    """Setup or precondition failure: the run is not evaluated (exit 3)."""


class StepError(RuntimeError):
    """An input step could not be performed; the case fails."""


def sh(argv, timeout=60):
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout)


def ydo(*args):
    r = sh(['ydotool', *args], timeout=30)
    if r.returncode:
        raise StepError(f"ydotool {' '.join(args)}: exit {r.returncode} {(r.stderr or r.stdout).strip()}")


def click(name):
    x, y = PX[name]
    ydo('mousemove', '--absolute', '-x', str(x // 2), '-y', str(y // 2))
    time.sleep(0.3)
    ydo('click', '0xC0')
    time.sleep(1)


def press(keys):
    ydo('key', *keys)
    time.sleep(0.5)


def unit_active(unit):
    return sh(['systemctl', '--user', 'is-active', '--quiet', unit]).returncode == 0


def wait_end(unit, seconds):
    """True when the unit has ended within `seconds`, False when it is still running."""
    end = time.monotonic() + seconds
    while unit_active(unit):
        if time.monotonic() >= end:
            return False
        time.sleep(0.5)
    return True


def stays_open(unit, seconds):
    return not wait_end(unit, seconds)


def qs_running():
    return sh(['pgrep', '-x', 'qs']).returncode == 0


def atmosphera_owner():
    out = sh(['busctl', '--user', '--no-legend', 'list']).stdout
    return any(line.split()[:1] == [PORTAL_IMPL] for line in out.splitlines())


def shot(ctx, cid, name):
    r = sh(['grim', str(ctx.output / f'{cid}-{name}.png')], timeout=30)
    if r.returncode:
        ctx.notes.append(f'grim {cid}-{name} failed: {r.stderr.strip()}')


def preflight(source, work, output):
    if not (source / 'shell.qml').is_file() or not (source / 'Configs/defaults.json').is_file():
        raise SetupError(f'{source} is not a shell tree (shell.qml / Configs/defaults.json missing)')
    if work.exists():
        raise SetupError(f'work dir already exists: {work}')
    if output.exists():
        raise SetupError(f'output dir already exists: {output}')
    if os.path.expanduser('~') != HOME:
        raise SetupError(f'HOME is {os.path.expanduser("~")}, expected {HOME}')
    free = os.statvfs(RUNTIME)
    if free.f_bavail * free.f_frsize < MIN_FREE_BYTES:
        raise SetupError(f'{RUNTIME} has less than 64 MiB free; clear stale quickshell runtime first')
    if qs_running():
        raise SetupError('a qs process is already running in the guest; stop it first')
    if sh(['systemctl', '--user', 'is-active', '--quiet', 'xdg-desktop-portal']).returncode:
        raise SetupError('xdg-desktop-portal is not active')
    try:
        ydo('mousemove', '-x', '0', '-y', '0')
    except StepError as e:
        raise SetupError(f'ydotoold is not answering on {YDOTOOL_SOCKET} ({e}); start the m20 ydotoold unit first')


@dataclass
class Ctx:
    source: Path
    work: Path
    output: Path
    base: str
    shell_unit: str
    notes: list = field(default_factory=list)
    units: list = field(default_factory=list)

    @property
    def profile(self):
        return self.work / 'profile'

    @property
    def dl(self):
        return self.work / 'fc' / 'downloads'


def setup_work(ctx):
    ctx.work.mkdir(parents=True)
    shutil.copytree(ctx.source, ctx.work / 'shell', symlinks=True)
    for name in ('config', 'cache', 'state'):
        (ctx.profile / name).mkdir(parents=True)
    settings = json.loads((ctx.source / 'Configs/defaults.json').read_text())
    settings['general']['showChangelogOnStartup'] = False
    (ctx.profile / 'config' / 'settings.json').write_text(json.dumps(settings))
    ctx.dl.mkdir(parents=True)
    (ctx.dl / 'existing.html').write_bytes(FIXTURE_EXISTING)
    (ctx.dl / '.hidden.html').write_bytes(FIXTURE_HIDDEN)
    (ctx.dl / 'existing-dir').mkdir()


def start_shell(ctx):
    p = ctx.profile
    argv = ['systemd-run', '--user', f'--unit={ctx.shell_unit}', '--collect',
            f'--setenv=ATMOSPHERA_CONFIG_DIR={p}/config/',
            f'--setenv=ATMOSPHERA_CACHE_DIR={p}/cache/',
            f'--setenv=ATMOSPHERA_STATE_DIR={p}/state/',
            '/usr/bin/qs', '-p', str(ctx.work / 'shell' / 'shell.qml')]
    r = sh(argv)
    if r.returncode:
        raise SetupError(f'could not start {ctx.shell_unit}: {r.stderr.strip()}')
    deadline = time.monotonic() + 60
    while not atmosphera_owner():
        if time.monotonic() >= deadline:
            raise SetupError(f'{PORTAL_IMPL} did not appear on the session bus')
        time.sleep(1)
    # The portal reads its backends at start: restart it once the shell owns the name.
    r = sh(['systemctl', '--user', 'restart', 'xdg-desktop-portal'])
    if r.returncode:
        raise SetupError(f'xdg-desktop-portal restart failed: {r.stderr.strip()}')
    time.sleep(3)
    if not atmosphera_owner():
        raise SetupError(f'{PORTAL_IMPL} vanished after the portal restart')


def stop_everything(ctx):
    """Stop every unit this run started; report whether qs is still running."""
    for unit in [*ctx.units, ctx.shell_unit]:
        sh(['systemctl', '--user', 'stop', unit], timeout=60)
    deadline = time.monotonic() + 20
    while qs_running() and time.monotonic() < deadline:
        time.sleep(1)
    return qs_running()


def run(args):
    source = args.source.resolve()
    work = args.work.resolve()
    output = args.output.resolve()
    ctx = Ctx(source, work, output, output.name, f'fcreg-{output.name}-shell')
    result = {'label': ctx.base, 'source': str(source), 'work': str(work),
              'shell_unit': ctx.shell_unit, 'setup_error': None, 'cases': [],
              'cleanup': {}, 'passed': False}
    started = False
    try:
        preflight(source, work, output)
        output.mkdir(parents=True)
        started = True
        setup_work(ctx)
        start_shell(ctx)
        for c in build_cases(ctx):
            try:
                rec = run_case(ctx, c)
            except (StepError, OSError, ValueError, KeyError) as e:
                rec = {'case': c.cid, 'title': c.title, 'method': c.method, 'passed': False,
                       'checks': {}, 'notes': [f'case crashed: {type(e).__name__}: {e}']}
                sh(['systemctl', '--user', 'stop', f'fcreg-{ctx.base}-c{c.cid}'], timeout=60)
            result['cases'].append(rec)
            print(f"case {c.cid} {'PASS' if rec['passed'] else 'FAIL'}", flush=True)
    except SetupError as e:
        result['setup_error'] = str(e)
        print(f'setup failed: {e}', file=sys.stderr)
    finally:
        if started:
            qs_left = stop_everything(ctx)
            result['cleanup'] = {'units_stopped': [*ctx.units, ctx.shell_unit], 'qs_running_after_stop': qs_left}
            journal = sh(['journalctl', '--user', '-u', ctx.shell_unit, '--no-pager', '-o', 'cat'], timeout=120)
            (output / 'shell-journal.txt').write_text(journal.stdout)
        result['notes'] = ctx.notes
        if started:
            result['passed'] = (result['setup_error'] is None and bool(result['cases'])
                                and all(c.get('passed') for c in result['cases'])
                                and not result['cleanup'].get('qs_running_after_stop'))
            (output / 'result.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    if result['setup_error']:
        return 3
    return 0 if result['passed'] else 1


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    if argv[:1] == ['--portal-call']:
        return portal_call(argv[1:])
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--source', type=Path, required=True)
    ap.add_argument('--work', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args(argv)
    os.environ.update(XDG_RUNTIME_DIR=RUNTIME, WAYLAND_DISPLAY='wayland-1', YDOTOOL_SOCKET=YDOTOOL_SOCKET)

    def on_term(_signum, _frame):
        raise SystemExit(143)
    signal.signal(signal.SIGTERM, on_term)
    return run(args)


@dataclass
class Case:
    cid: str
    title: str
    method: str
    args: dict            # folder / file / name / no_nul, as portal-call options
    flow: object          # function(ctx, case, unit, rec, state) performing the inputs
    response: int
    uris: object          # exact expected uri list, or None when no uris are expected
    quiet: object = None  # True: no response for QUIET seconds after the first accept
    must_not_exist: list = field(default_factory=list)
    content: object = None  # 'save' (write and read back) or 'read' (fixture bytes)
    fixture: bytes = b''


def start_call(ctx, c):
    unit = f'fcreg-{ctx.base}-c{c.cid}'
    out = ctx.output / f'{c.cid}-call.json'
    argv = ['systemd-run', '--user', f'--unit={unit}', '--collect', '--property=RuntimeMaxSec=150',
            sys.executable, '-B', str(SELF), '--portal-call', c.method,
            '--title', f'M20 {ctx.base} case {c.cid}', '--out', str(out), '--timeout', str(CALL_TIMEOUT)]
    for key, flag in (('folder', '--current-folder'), ('file', '--current-file'), ('name', '--current-name')):
        if c.args.get(key) is not None:
            argv += [flag, str(c.args[key])]
    if c.args.get('no_nul'):
        argv.append('--no-nul')
    r = sh(argv)
    if r.returncode:
        raise StepError(f'could not start the call unit {unit}: {r.stderr.strip()}')
    ctx.units.append(unit)
    return unit, out


def close_dialog(ctx, c, unit, rec):
    """Close a dialog that is still open: Escape, then Cancel, then stop the call unit."""
    rec['notes'].append('dialog still open after the steps: closing it')
    if not unit_active(unit):
        return
    press(ESCAPE)
    if wait_end(unit, 3):
        return
    click(CANCEL_FOR[c.method])
    if wait_end(unit, 10):
        return
    sh(['systemctl', '--user', 'stop', unit], timeout=60)
    wait_end(unit, 10)


def uri_path(uri):
    return Path(urllib.parse.unquote(urllib.parse.urlsplit(uri).path))


def check_content(c, uris, rec):
    """Consumer side: the uri must name a file we can write and read back (or the fixture bytes)."""
    ok = True
    for uri in uris:
        path = uri_path(uri)
        try:
            if c.content == 'read':
                ok = ok and path.read_bytes() == c.fixture
            else:
                existed = c.pre_existed[str(path)]
                original = path.read_bytes() if existed else None
                payload = f'M20 case {c.cid} {path.name}\n'.encode()
                path.write_bytes(payload)
                ok = ok and path.read_bytes() == payload
                if existed:
                    path.write_bytes(original)  # keep the fixture for later cases
                else:
                    path.unlink()
        except OSError as e:
            rec['notes'].append(f'content check failed for {path}: {e}')
            ok = False
    return ok


def run_case(ctx, c):
    rec = {'case': c.cid, 'title': c.title, 'method': c.method, 'notes': [], 'checks': {}, 'passed': False}
    ctx.cases_rec = rec
    for path in c.must_not_exist:
        if path.exists() or path.is_symlink():
            rec['notes'].append(f'precondition: {path} already exists; not overwritten or removed')
            return rec
    c.pre_existed = {str(uri_path(u)): uri_path(u).exists() for u in (c.uris or [])}
    state = {'quiet': None}
    unit, out = start_call(ctx, c)
    time.sleep(DIALOG_WAIT)
    if unit_active(unit):
        shot(ctx, c.cid, 'dialog-open')
        try:
            c.flow(ctx, c, unit, rec, state)
        except StepError as e:
            rec['notes'].append(f'step failed: {e}')
    else:
        rec['notes'].append('the call ended before any input (no dialog)')
    settled = wait_end(unit, SETTLE)
    if not settled:
        close_dialog(ctx, c, unit, rec)
    data = json.loads(out.read_text()) if out.exists() else {}
    timed_out = bool(data.get('meta', {}).get('timed_out'))
    if timed_out:
        rec['notes'].append('the portal call timed out; Escape sent to close any leftover dialog')
        press(ESCAPE)
    response = data.get('response')
    uris = (data.get('results') or {}).get('uris')
    checks = rec['checks']
    checks['settled'] = settled and not timed_out
    checks['response'] = response == c.response
    if c.uris is None:
        checks['no_uris'] = not uris
    else:
        checks['uris'] = sorted(uris or []) == sorted(c.uris)
        if checks['uris'] and c.content is not None:
            checks['content'] = check_content(c, uris, rec)
    if c.quiet is not None:
        checks['quiet_5s'] = state['quiet'] is c.quiet
    rec['observed'] = {'response': response, 'uris': uris, 'timed_out': timed_out, 'quiet_5s': state['quiet']}
    rec['expect'] = {'response': c.response, 'uris': c.uris, 'quiet_5s': c.quiet}
    rec['args'] = c.args
    rec['passed'] = bool(checks) and all(checks.values())
    return rec


def navigate(ctx, c, unit, folder):
    click('location')
    press(CTRL_A)
    ydo('type', folder)
    press(ENTER)
    time.sleep(2)


def flow_enter(ctx, c, unit, rec, state):
    """Name field pre-filled by the caller; click it and press Enter."""
    if unit_active(unit):
        click('name')
        press(ENTER)


def flow_enter_replace(ctx, c, unit, rec, state):
    """Enter must stop the save at the overwrite bar; Replace then settles it."""
    if not unit_active(unit):
        return
    click('name')
    press(ENTER)
    state['quiet'] = stays_open(unit, QUIET)
    if state['quiet']:
        shot(ctx, c.cid, 'overwrite-bar')
        click('replace')


def flow_enter_error(ctx, c, unit, rec, state):
    """Enter on a directory name must show an inline error; Escape then cancels (response 1)."""
    if not unit_active(unit):
        return
    click('name')
    press(ENTER)
    state['quiet'] = stays_open(unit, QUIET)
    if state['quiet']:
        shot(ctx, c.cid, 'inline-error')
        press(ESCAPE)


def flow_open(ctx, c, unit, rec, state):
    """OpenFile: navigate to the fixture folder, select existing.html, press Select."""
    navigate(ctx, c, unit, str(ctx.dl))
    shot(ctx, c.cid, 'after-navigate')
    if unit_active(unit):
        click('open_tile')
        shot(ctx, c.cid, 'selected')
    if unit_active(unit):
        click('open_select')


def flow_saveall(ctx, c, unit, rec, state):
    """SaveFiles: add a.txt and b.txt with Enter (Add to list), then Save All."""
    for name in ('a.txt', 'b.txt'):
        if unit_active(unit):
            click('name')
            ydo('type', name)
            press(ENTER)
            time.sleep(1)
    if unit_active(unit):
        shot(ctx, c.cid, 'target-list')
        click('multi_accept')


def build_cases(ctx):
    dl = ctx.dl
    uri = lambda p: f'file://{p}'  # noqa: E731  (fixture paths are plain ASCII)
    home_plain = Path(HOME) / 'plain.html'
    return [
        Case('1', 'SaveFile plain name', 'SaveFile', dict(folder=str(dl), name='plain.html'),
             flow_enter, 0, [uri(dl / 'plain.html')], must_not_exist=[dl / 'plain.html'], content='save'),
        Case('2', 'SaveFile Japanese name', 'SaveFile', dict(folder=str(dl), name='日本語.html'),
             flow_enter, 0, [f'file://{dl}/%E6%97%A5%E6%9C%AC%E8%AA%9E.html'],
             must_not_exist=[dl / '日本語.html'], content='save'),
        Case('3', 'SaveFile reserved characters', 'SaveFile', dict(folder=str(dl), name='a#b?c%20d e.html'),
             flow_enter, 0, [f'file://{dl}/a%23b%3Fc%2520d%20e.html'],
             must_not_exist=[dl / 'a#b?c%20d e.html'], content='save'),
        Case('4', 'SaveFile existing hidden file, overwrite bar', 'SaveFile',
             dict(folder=str(dl), name='.hidden.html'), flow_enter_replace, 0,
             [uri(dl / '.hidden.html')], quiet=True, content='save'),
        Case('5', 'SaveFile existing directory name', 'SaveFile', dict(folder=str(dl), name='existing-dir'),
             flow_enter_error, 1, None, quiet=True),
        Case('6', 'SaveFile current_file, overwrite bar', 'SaveFile', dict(file=str(dl / 'existing.html')),
             flow_enter_replace, 0, [uri(dl / 'existing.html')], quiet=True, content='save'),
        Case('7', 'SaveFile unterminated current_folder falls back to HOME', 'SaveFile',
             dict(folder=str(dl), name='plain.html', no_nul=True), flow_enter, 0,
             ['file:///home/tester/plain.html'], must_not_exist=[home_plain], content='save'),
        Case('9', 'OpenFile select existing.html', 'OpenFile', {}, flow_open, 0,
             [uri(dl / 'existing.html')], content='read', fixture=FIXTURE_EXISTING),
        Case('10', 'SaveFiles a.txt and b.txt', 'SaveFiles', dict(folder=str(dl)), flow_saveall, 0,
             [uri(dl / 'a.txt'), uri(dl / 'b.txt')], must_not_exist=[dl / 'a.txt', dl / 'b.txt'],
             content='save'),
    ]


def portal_call(argv):
    """Child mode, run as a transient unit: one FileChooser call, like a browser.

    Same wire format as tools/guest-side/portal-call.py (M15): byte-array options
    end with one NUL unless --no-nul; the Request.Response subscription is made on
    the predicted request path before the call. Writes {method, options_hex,
    response, results, meta} to --out. Exit 0 on a response, 3 on timeout.
    """
    import gi
    gi.require_version('Gio', '2.0')
    gi.require_version('GLib', '2.0')
    from gi.repository import Gio, GLib

    p = argparse.ArgumentParser(prog='filechooser-portal-regression.py --portal-call')
    p.add_argument('method', choices=['SaveFile', 'OpenFile', 'SaveFiles'])
    p.add_argument('--title', required=True)
    p.add_argument('--current-folder')
    p.add_argument('--current-file')
    p.add_argument('--current-name')
    p.add_argument('--no-nul', action='store_true')
    p.add_argument('--out', required=True)
    p.add_argument('--timeout', type=int, default=CALL_TIMEOUT)
    a = p.parse_args(argv)

    def byte_arg(text):
        data = os.fsencode(text)
        return data if a.no_nul else data + b'\0'

    token = 'm20_' + uuid.uuid4().hex
    opts = {'handle_token': GLib.Variant('s', token)}
    options_hex = {'handle_token': token}
    if a.current_folder is not None:
        b = byte_arg(a.current_folder)
        opts['current_folder'] = GLib.Variant('ay', b)
        options_hex['current_folder'] = b.hex()
    if a.current_file is not None:
        b = byte_arg(a.current_file)
        opts['current_file'] = GLib.Variant('ay', b)
        options_hex['current_file'] = b.hex()
    if a.current_name is not None:
        opts['current_name'] = GLib.Variant('s', a.current_name)
        options_hex['current_name'] = a.current_name

    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    sender = conn.get_unique_name()[1:].replace('.', '_')
    predicted = f'{OBJ}/request/{sender}/{token}'
    wanted = {predicted}
    loop = GLib.MainLoop()
    out = {'method': a.method, 'options_hex': options_hex, 'response': None, 'results': None,
           'meta': {'predicted_request_path': predicted, 'timed_out': False}}

    def jsonable(x):
        if isinstance(x, bytes):
            return {'hex': x.hex(), 'text': x.decode('utf-8', 'surrogateescape')}
        if isinstance(x, (list, tuple)):
            return [jsonable(i) for i in x]
        if isinstance(x, dict):
            return {k: jsonable(v) for k, v in x.items()}
        return x

    def on_response(_conn, _sender, path, _iface, _signal, params):
        if path not in wanted:
            return
        code, results = params.unpack()
        out['response'] = code
        out['results'] = jsonable(results)
        out['meta']['response_path'] = path
        loop.quit()

    def on_timeout():
        out['meta']['timed_out'] = True
        loop.quit()
        return False

    conn.signal_subscribe(None, REQ_IFACE, 'Response', None, None,
                          Gio.DBusSignalFlags.NONE, on_response)
    reply = conn.call_sync(BUS, OBJ, FC_IFACE, a.method,
                           GLib.Variant('(ssa{sv})', ('', a.title, opts)),
                           GLib.VariantType('(o)'), Gio.DBusCallFlags.NONE, -1, None)
    handle = reply.unpack()[0]
    wanted.add(handle)
    out['meta']['returned_handle'] = handle
    out['meta']['handle_matches_prediction'] = handle == predicted
    GLib.timeout_add_seconds(a.timeout, on_timeout)
    loop.run()
    Path(a.out).write_text(json.dumps(out, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: out[k] for k in ('method', 'response')}), flush=True)
    return 3 if out['meta']['timed_out'] else 0


if __name__ == '__main__':
    sys.exit(main())
