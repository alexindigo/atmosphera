#!/usr/bin/env python3
"""Native full-shell save/reload/typing budget. Assigned niri VM only.

Uses the I1 dispatcher + poll/ppoll instrument, not awake/aboutToBlock or a
heartbeat-only proxy. Only actual waits >=50us split continuous busy batches.
Every span is retained (including wall and thread CPU); scheduler time is not
subtracted to turn a violation green. Startup is reported separately.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import signal
import select
import struct
import subprocess
import sys
import time
import traceback

from guest_profile import activate_profile, profile_argument
from gui_timing_capture import ConsoleCapture
from qml_probe import inject_probe, probe_owner_path
from workspace_guard import require_disk_backed_paths

HERE = Path(__file__).resolve().parent


def watch_keys(stop_file):
    """Read-only I1 evdev protocol; stop cooperatively, never grab the device."""
    blocks = Path('/proc/bus/input/devices').read_text().split('\n\n')
    nodes = [re.search(r'event\d+', b).group(0) for b in blocks
             if 'ydotoold virtual device' in b and re.search(r'event\d+', b)]
    assert nodes, 'no real ydotoold input device'
    event = struct.Struct('llHHi')
    files = [open('/dev/input/' + n, 'rb', buffering=0) for n in nodes]
    print(json.dumps(dict(nodes=nodes)), flush=True)
    deadline = time.monotonic() + 1200
    while not stop_file.exists() and time.monotonic() < deadline:
        ready, _, _ = select.select(files, [], [], .1)
        for stream in ready:
            data = stream.read(event.size * 64)
            assert len(data) % event.size == 0
            for offset in range(0, len(data), event.size):
                sec, usec, kind, code, value = event.unpack_from(data, offset)
                if kind == 1:
                    print(json.dumps(dict(at=sec*1000+usec/1000, code=code, value=value)), flush=True)
    for stream in files:
        stream.close()


def physical_text(rows):
    mapping = {code: char for codes, chars in [(range(2, 12), '1234567890'),
               (range(16, 26), 'qwertyuiop'), (range(30, 39), 'asdfghjkl'),
               (range(44, 51), 'zxcvbnm')] for code, char in zip(codes, chars)}
    mapping.update({57: ' ', 12: '-', 52: '.'})
    shifted = set()
    result = ''
    for row in rows:
        code, value = row['code'], row['value']
        assert value != 2, 'kernel repeated a physical key'
        if code in (42, 54):
            if value:
                shifted.add(code)
            else:
                shifted.discard(code)
        elif value == 1:
            assert code in mapping, ('unexpected physical key', row)
            char = mapping[code]
            result += '>' if shifted and char == '.' else char.upper() if shifted else char
    assert not shifted, 'unreleased physical shift'
    return result


def command(argv, env=None, seconds=20, check=True, **kwargs):
    return subprocess.run(['timeout', str(seconds), *map(str, argv)], env=env,
                          capture_output=True, check=check, timeout=seconds + 5, **kwargs)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def trace_report(path, windows):
    """I1's conservative continuous-batch definition, with strict coverage."""
    rows = [line.split() for line in path.read_text().splitlines()]
    assert rows and all(len(r) == 6 for r in rows), 'missing/truncated native trace'
    pids = {int(r[1]) for r in rows if r[0] == 'E' and r[1] == r[2]}
    assert len(pids) == 1, ('missing/ambiguous GUI dispatch owner', pids)
    pid = pids.pop()
    events = [(r[0], int(r[3]), int(r[4]), int(r[5])) for r in rows
              if int(r[1]) == pid and r[1] == r[2]]
    assert all(a[1] <= b[1] and a[2] <= b[2] for a, b in zip(events, events[1:])), 'nonmonotonic native clocks'
    spans, waits = [], []
    start = waiting = None
    depth = 0
    pending_poll = None
    for kind, wall, cpu, arg in events:
        if kind == 'E':
            assert depth == 0, 'nested/duplicate outer dispatcher entry'
            depth = 1
            if start is None:
                start = wall, cpu
        elif kind == 'X':
            assert depth == 1 and pending_poll is None, 'unmatched dispatcher exit'
            depth = 0
        elif kind in ('W', 'P'):
            assert depth == 1 and pending_poll is None, 'uncovered/overlapping poll'
            pending_poll = kind
            if kind == 'W':
                waiting = wall, cpu
        elif kind in ('R', 'Q'):
            assert pending_poll == ('W' if kind == 'R' else 'P'), 'unmatched poll return'
            pending_poll = None
            if waiting is not None:
                if wall - waiting[0] >= 50_000:
                    if start is not None:
                        spans.append(dict(startNs=start[0], endNs=waiting[0],
                                          wallMs=(waiting[0]-start[0])/1e6,
                                          cpuMs=(waiting[1]-start[1])/1e6))
                    waits.append(dict(startNs=waiting[0], endNs=wall,
                                      wallMs=(wall-waiting[0])/1e6,
                                      cpuMs=(cpu-waiting[1])/1e6))
                    start = wall, cpu
                waiting = None
        else:
            assert kind == 'I', ('unknown native event', kind)
    terminal = depth == 1 and pending_poll == 'W' and events[-1][0] == 'W'
    assert depth == 0 or terminal, 'incomplete native dispatcher outside terminal wait'
    if start:
        end = waiting if terminal else events[-1][1:3]
        spans.append(dict(startNs=start[0], endNs=end[0],
                          wallMs=(end[0]-start[0])/1e6, cpuMs=(end[1]-start[1])/1e6))
    assert spans and waits and any(e[0] == 'P' for e in events), 'missing dispatch/blocking/ready-poll coverage'
    for span in spans:
        span['windows'] = [w['id'] for w in windows if span['endNs'] >= w['startNs'] and span['startNs'] <= w['endNs']]
    measured = [s for s in spans if s['windows']]
    assert measured, 'no native spans cover the workload'
    for w in windows:
        assert events[0][1] <= w['startNs'] < w['endNs'] <= events[-1][1], 'workload outside trace'
        assert any(s for s in measured if w['id'] in s['windows']), ('missing workload coverage', w)
    return dict(pid=pid, dispatcherKinds=sorted({e[3] for e in events if e[0] == 'E'}),
                dispatchEntries=sum(e[0] == 'E' for e in events), blockingPolls=len(waits),
                zeroPolls=sum(e[0] == 'P' for e in events), terminalOpenPoll=terminal,
                maximumBusyMs=max(s['wallMs'] for s in measured),
                wholeRunMaximumBusyMs=max(s['wallMs'] for s in spans), spans=spans, waits=waits)


def wait_for(predicate, seconds=45):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(.05)
    raise AssertionError('consumer deadline exceeded')


def inventory(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file() and not p.is_symlink()}


def verify_drain(trace, pid):
    receipt = json.loads(Path(str(trace)+'.async-'+str(pid)+'.json').read_text())
    assert receipt['pid'] == pid and receipt['dropped'] == 0
    assert receipt['published'] == receipt['drained']
    assert receipt['published'] == sum(receipt[k] for k in ('traceRecords', 'scopeRecords', 'diagnosticRecords'))
    assert receipt['queuePeak'] <= receipt['capacity']
    for sink, path in [('trace', trace), ('scope', trace.with_suffix('.scopes'))]:
        if not receipt[sink+'Records']:
            continue
        body = path.read_bytes()
        assert len(body) == receipt[sink+'Bytes']
        assert body.count(b'\n') == receipt[sink+'Records']
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'output', 'work-root'):
        parser.add_argument('--' + name, type=Path, required=True)
    profile_argument(parser)
    parser.add_argument('--restore-niri-config', type=Path, required=True,
                        help='explicit known initial niri config, restored in finally')
    parser.add_argument('--max-busy-ms', type=float, default=16)
    parser.add_argument('--max-heartbeat-lateness-ms', type=float, default=16)
    parser.add_argument('--rounds', type=int, default=100)
    parser.add_argument('--expect-old-stall', action='store_true', help='positive control: require a native >16ms save/burst stall')
    parser.add_argument('--profile', action='store_true', help='diagnostic QML profile; overhead is not acceptance evidence')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    assert not profile.console.records, 'preserve the existing console: this full-shell owner requires an idle assigned guest'
    restore_config = args.restore_niri_config.resolve(strict=True)
    assert restore_config.is_relative_to(profile.home)
    restore_hash = hashlib.sha256(restore_config.read_bytes()).hexdigest()
    source, out, work = (p.resolve() for p in (args.source, args.output, args.work_root))
    require_disk_backed_paths(source, out, work, os.environ.get('TMPDIR'))
    assert args.rounds > 0 and args.max_busy_ms > 0 and args.max_heartbeat_lateness_ms > 0
    assert out != work and not out.is_relative_to(work) and not work.is_relative_to(out)
    assert not source.is_relative_to(work) and not work.is_relative_to(source)
    assert work.is_relative_to(profile.workspace) and out.is_relative_to(profile.workspace)
    out.mkdir(parents=True, exist_ok=False)
    work.mkdir(parents=True, exist_ok=False)
    result = dict(status='FAIL', profile=profile.record(), source=str(source), rounds=args.rounds,
                  positiveControl=args.expect_old_stall, windows=[], typing=[], checks={}, errors=[])
    env = dict(os.environ, **profile.child_environment('gt-'))
    private_runtime = Path(env['XDG_RUNTIME_DIR'])
    for key, leaf in [('XDG_CONFIG_HOME', 'xdg'), ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state'), ('XDG_DATA_HOME', 'data')]:
        (work / leaf).mkdir()
        env[key] = str(work / leaf)
    for key in ('QT_IM_MODULE', 'GTK_IM_MODULE', 'FCITX_QT_USE_SYNC', 'LD_PRELOAD'):
        env.pop(key, None)
    shell = work / 's'
    shutil.copytree(source, shell, ignore=shutil.ignore_patterns('.git', '__pycache__', '*.bak'))
    # Fixtures are always from this runner's version, including old-owner legs.
    for name in ('settings-gui-timing.qml', 'launcher-key-owner-probe.qml'):
        shutil.copy2(HERE / 'fixtures' / name, shell / 'Scripts/dev/fixtures' / name)
    body = probe_owner_path(shell)
    text = body.read_text()
    injected = '\n      property var _guiTiming: Qt.createComponent(Quickshell.shellDir + "/Scripts/dev/fixtures/settings-gui-timing.qml").createObject(shellRoot)\n'
    body.write_text(inject_probe(text, injected))
    result['sourceFiles'] = inventory(source)
    result['instrumentedFiles'] = {str(body.relative_to(shell)): hashlib.sha256(body.read_bytes()).hexdigest()}
    config = work / 'c'
    (config / 'settings/plugins').mkdir(parents=True)
    (work / 'tmp').mkdir()
    env.update(ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(work/'cache'),
               ATMOSPHERA_STATE_DIR=str(work/'state'), ATMOSPHERA_SETTINGS_FILE=str(config/'settings.json'),
               CLIPHIST_DB_PATH=str(work/'cliphist.db'), TMPDIR=str(work/'tmp'),
               QML_DISABLE_DISK_CACHE='1', LANG='C.UTF-8')
    defaults = json.loads((source / 'Configs/defaults.json').read_text())
    defaults['settingsVersion'] = 62
    defaults['general']['showChangelogOnStartup'] = False
    defaults['appLauncher'].update(pinnedApps=[], viewMode='list', overviewLayer=False)
    defaults['bindings']['environment'] = 'none'
    write_json(config/'settings.json', defaults)
    legacy = (config/'settings.json').read_bytes()
    sections = [k for k, v in defaults.items() if isinstance(v, dict)]
    assert len(sections) == 29
    for section in sections:
        write_json(config/'settings'/f'{section}.json', {})
    (config/'plugins.json').write_text('{"version":5,"sources":[],"states":{}}\n')
    native = work / 'dispatch.so'
    # The real user-manager bus is required by the unmodified bindings helper.
    # Its default-none startup is non-mutating to remappers on this idle guest;
    # refuse rather than altering an existing managed remapper lifetime.
    assert not Path('/etc/keyd/atmosphera').exists()
    assert command(['systemctl', '--user', 'show', 'xremap-atmosphera.service', '-p', 'LoadState', '--value'], env).stdout.strip() == b'not-found'
    assert command(['busctl', '--user', 'status', 'app.atmosphera.Shell'], env, check=False).returncode != 0
    compile_result = command(['g++', '-shared', '-fPIC', '-O2', '-pthread', '-o', native,
                              HERE/'fixtures/settings-gui-dispatch.cpp',
                              HERE/'fixtures/settings-gui-log.cpp', '-ldl'], env, 45)
    (out/'compile.log').write_bytes(compile_result.stdout + compile_result.stderr)
    symbols = command(['nm', '-D', '/usr/lib/libQt6Core.so.6'], env).stdout.decode()
    assert all(s in symbols for s in ('_ZN20QEventDispatcherGlib13processEventsE6QFlagsIN10QEventLoop17ProcessEventsFlagEE',
                                      '_ZN20QEventDispatcherUNIX13processEventsE6QFlagsIN10QEventLoop17ProcessEventsFlagEE'))
    process = log = observer = observer_log = typing_process = profiler = profiler_log = None
    input_unit = 'atcq-i6-input-' + hashlib.sha256(str(work).encode()).hexdigest()[:8]
    input_started = False

    def ipc(target, method, *values, check=True):
        response = command(['qs', '-p', shell, 'ipc', 'call', target, method, *map(str, values)], env, 30, check)
        with (out/'ipc.jsonl').open('a') as journal:
            journal.write(json.dumps(dict(target=target, method=method, exit=response.returncode,
                                          bytes=len(response.stdout), stderr=response.stderr.decode()))+'\n')
        return response.stdout.decode().strip()

    def status():
        return json.loads(ipc('guiTiming', 'status'))

    def launch(name, traced=True):
        nonlocal process, log
        launch_env = dict(env)
        if traced:
            launch_env.update(LD_PRELOAD=str(native), ATMOSPHERA_GUI_TRACE=str(out/(name+'.trace')))
        # Use the pinned real session bus so full-shell side effects reach the
        # actual user manager, rather than a private bus's failed activation.
        debug = ['--debug', '3799'] if args.profile and traced else []
        process = subprocess.Popen(['timeout', '1200', 'qs', '-p', str(shell), '--no-color', '--log-times', *debug],
                                   env=launch_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        log = ConsoleCapture(process.stdout, out/(name+'.log'))
        wait_for(lambda: 'target guiTiming' in command(['qs', '-p', shell, 'ipc', 'show'], env, 5, False).stdout.decode(), 60)
        wait_for(lambda: status()['loaded'])

    def stop():
        nonlocal process, log
        if process and process.poll() is None:
            ipc('guiTiming', 'quit', check=False)
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=10)
        if log:
            result.setdefault('consoleCapture', []).append(log.finish())
            log = None
        if process:
            result.setdefault('exits', []).append(process.returncode)
        process = None

    def keys(*codes):
        command(['ydotool', 'key', '--key-delay', '0', *codes], env)

    try:
        # Revalidate the instrument on this Qt/dispatcher family before relying
        # on its workload result. No heartbeat substitute can make this green.
        sensitivity = work / 'sensitivity.qml'
        sensitivity.write_text('import QtQml\nimport Quickshell\nShellRoot { Timer { interval: 100; running: true; onTriggered: { const t=Date.now(); while(Date.now()-t<80) {} Qt.quit(); } } }\n')
        for dispatcher in ('glib', 'unix'):
            trace = out/('sensitivity-'+dispatcher+'.trace')
            sensitivity_env = dict(env, LD_PRELOAD=str(native), ATMOSPHERA_GUI_TRACE=str(trace))
            if dispatcher == 'unix':
                sensitivity_env['QT_NO_GLIB'] = '1'
            response = command(['qs', '-p', sensitivity, '--no-color'], sensitivity_env, 20)
            (out/('sensitivity-'+dispatcher+'.log')).write_bytes(response.stdout+response.stderr)
            # Full trace bounds form the control window (startup is harmless
            # here: the deliberate handler must still appear as >=75ms CPU).
            events = [line.split() for line in trace.read_text().splitlines()]
            bounds = [int(r[3]) for r in events if r[0] in ('E', 'X')]
            proof = trace_report(trace, [dict(id='80ms-control', startNs=min(bounds), endNs=max(bounds))])
            verify_drain(trace, proof['pid'])
            assert any(s['cpuMs'] >= 75 for s in proof['spans']), ('insensitive native instrument', dispatcher)
            write_json(out/('sensitivity-'+dispatcher+'.json'), proof)
        result['checks']['nativeSensitivity'] = True
        launch('full-shell')
        time.sleep(8)
        initial = status()
        result['initial'] = initial
        assert all(initial['counts'][i] > 0 for i in (0, 1, 3))
        if args.profile:
            profiler_log = (out/'qmlprofiler.log').open('xb')
            def trace_limit():
                resource.setrlimit(resource.RLIMIT_FSIZE, (512*1024**2, 512*1024**2))
            profiler = subprocess.Popen(['/usr/lib/qt6/bin/qmlprofiler', '--interactive', '--verbose',
                                         '--attach', '127.0.0.1', '-p', '3799', '-o', str(out/'trace.qtd'),
                                         '--include', 'javascript,binding,handlingsignal,debugmessages'],
                                        env=env, stdin=subprocess.PIPE, stdout=profiler_log,
                                        stderr=subprocess.STDOUT, text=True, preexec_fn=trace_limit)
            time.sleep(4)
        command(['sudo', '-n', 'systemd-run', '--unit='+input_unit, '--collect',
                 '-p', 'RuntimeMaxSec=1800', '--setenv=TMPDIR='+str(work/'tmp'),
                 '/usr/bin/ydotoold', '--socket-path='+str(work/'input.sock'), '--socket-own=1000:1000'], env)
        input_started = True
        env['YDOTOOL_SOCKET'] = str(work/'input.sock')
        wait_for(lambda: (work/'input.sock').exists())
        time.sleep(1)
        observer_log = (out/'physical-keys.jsonl').open('xb')
        observer = subprocess.Popen(['sudo', '-n', 'env', 'TMPDIR='+str(work/'tmp'), 'timeout', '1200',
                                     'python3', '-B', str(Path(__file__).resolve()), '--watch-keys', str(work/'stop-observer')],
                                    env=env, stdout=observer_log, stderr=subprocess.PIPE)
        wait_for(lambda: (out/'physical-keys.jsonl').stat().st_size > 0)
        ipc('guiTiming', 'start')
        measured_start = time.monotonic_ns()
        for number in range(args.rounds):
            started = time.monotonic_ns()
            before = len(status()['completions'])
            # Twenty clipboard queries, both hosts, physically delivered while
            # this burst's saves/replies/notifications remain outstanding.
            if number < 20:
                host = 'panel' if number % 2 == 0 else 'overlay'
                text = '>clip panel copy-only ' + host + ' ' + str(number)
                command(['cliphist', 'store'], env, input=text.encode())
                ipc('launcherKeys', 'configure', json.dumps(dict(host=host, mode='apps-list')))
                ipc('launcher', 'toggle')
                wait_for(lambda: json.loads(ipc('launcherKeys', 'state'))['nativeActive'])
                ipc('launcherKeys', 'observe', 'false')
                type_start = time.time_ns()/1e6
                typing_process = subprocess.Popen(['timeout', '30', 'ydotool', 'type', '--key-delay', '2', '--', text],
                                                 env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                burst_start = time.monotonic_ns()
                ipc('guiTiming', 'burst', number)
                burst_return = time.monotonic_ns()
                typing_process.communicate(timeout=35)
                assert typing_process.returncode == 0
                typing_process = None
                type_end = time.time_ns()/1e6
                # Same retained I1 observation interval on both trees. The old
                # positive control records wrong Qt text rather than requiring
                # the known-broken owner to satisfy the candidate assertion.
                time.sleep(1.8)
                observed = json.loads(ipc('launcherKeys', 'state'))
                raw_keys = [json.loads(line) for line in (out/'physical-keys.jsonl').read_text().splitlines()]
                raw_keys = [r for r in raw_keys if 'at' in r and type_start <= r['at'] <= type_end]
                assert physical_text(raw_keys) == text, ('physical text differs', raw_keys)
                assert len(raw_keys) > 0
                result['typing'].append(dict(round=number, host=host, expected=text, observed=observed,
                                            physical=raw_keys, startEpochMs=type_start, endEpochMs=type_end,
                                            burstStartNs=burst_start, burstReturnNs=burst_return))
                if not args.expect_old_stall:
                    assert observed['query'] == text, ('Qt text differs from exact physical text', observed)
                ipc('guiTiming', 'closeLauncher')
                wait_for(lambda: not json.loads(ipc('launcherKeys', 'state'))['open'])
            else:
                ipc('guiTiming', 'burst', number)
            current = wait_for(lambda: s if len((s := status())['completions']) >= before+2 and s['audioCount'] == 1000 else None)
            assert all(r['status'] != 'failed' for r in current['completions']), current['completions']
            expected_first = 'i6-'+str(number)+'-'+('999' if number % 2 else '0')
            wait_for(lambda: status()['audioFirst'] == expected_first)
            raw = json.loads((config/'settings/audio.json').read_text())
            expected_audio = ['i6-'+str(number)+'-'+str(i) for i in range(1000)]
            if number % 2:
                expected_audio.reverse()
            assert raw['mprisBlacklist'] == expected_audio
            ipc('guiTiming', 'noop')
            wait_for(lambda: len(status()['completions']) >= before+3)
            # Unchanged watch noise on every source, plus actual atomic external
            # replacement/deletion and re-creation on an otherwise clean path.
            for section in sections:
                p = config/'settings'/f'{section}.json'
                if p.exists():
                    os.utime(p, None)
            bar = config/'settings/bar.json'
            value = json.loads(bar.read_text())
            value['widgetSpacing'] = 10 + number % 3
            replacement = bar.with_suffix('.replacement')
            write_json(replacement, value)
            replacement.replace(bar)
            wait_for(lambda: status()['spacing'] == value['widgetSpacing'])
            if number % 10 == 0:
                bar.unlink()
                wait_for(lambda: status()['spacing'] == defaults['bar']['widgetSpacing'])
                write_json(replacement, value)
                replacement.replace(bar)
                wait_for(lambda: status()['spacing'] == value['widgetSpacing'])
            time.sleep(.05)
            result['windows'].append(dict(id='round-'+str(number), startNs=started, endNs=time.monotonic_ns()))
            write_json(out/'progress.json', dict(round=number, target=args.rounds, lastConsumer=status()))
            print('GUI_TIMING round '+str(number+1)+'/'+str(args.rounds), flush=True)
        typed = result['typing'][-1]['expected']
        ipc('guiTiming', 'input', typed)
        wait_for(lambda: json.loads((config/'settings/audio.json').read_text()).get('preferredPlayer') == typed)
        wait_for(lambda: any(r['label'] == 'input-persistence' and r['status'] != 'failed' for r in status()['completions']))
        time.sleep(.1)
        measured_end = time.monotonic_ns()
        result['heartbeat'] = json.loads(ipc('guiTiming', 'stop'))
        result['windows'].append(dict(id='complete-workload', startNs=measured_start, endNs=measured_end))
        result['final'] = status()
        assert result['final']['notifications'] == args.rounds and result['final']['gcCount'] == args.rounds
        assert (config/'settings.json').read_bytes() == legacy
        result['checks']['legacyUnchanged'] = True
        if profiler:
            profiler.stdin.write('flush\n'); profiler.stdin.flush()
            wait_for(lambda: (out/'trace.qtd').exists(), 30)
            time.sleep(2)
            profiler.stdin.write('quit\n'); profiler.stdin.close()
            profiler.wait(timeout=30)
            assert profiler.returncode == 0
            profiler_log.close()
            profiler = None
        stop()
        native_report = trace_report(out/'full-shell.trace', result['windows'])
        result['traceDrain'] = verify_drain(out/'full-shell.trace', native_report['pid'])
        result['checks']['traceDrainLossless'] = True
        write_json(out/'native.json', native_report)
        violations = [s for s in native_report['spans'] if s['windows'] and s['wallMs'] > args.max_busy_ms]
        result['native'] = {k: v for k, v in native_report.items() if k not in ('spans', 'waits')}
        result['busyViolations'] = violations
        launch('cold-restart', traced=False)
        cold = wait_for(lambda: s if (s := status())['audioCount'] == 1000 and s['preferredPlayer'] == typed else None)
        assert cold['spacing'] == result['final']['spacing'] and cold['audioFirst'] == result['final']['audioFirst']
        result['coldConsumer'] = cold
        result['checks']['diskConsumerRestartAndExactText'] = True
        stop()
        result['checks']['100Rounds'] = args.rounds == 100
        result['checks']['noBusyViolation'] = not violations
        result['checks']['heartbeatBudget'] = result['heartbeat']['ticks'] > 0 and result['heartbeat']['worstLate'] <= args.max_heartbeat_lateness_ms
        if args.expect_old_stall:
            assert violations, 'old-owner positive control did not reproduce native stall'
            result['status'] = 'CONTROL_REPRODUCED'
        else:
            assert not args.profile and all(result['checks'].values()), result['checks']
            result['status'] = 'PASS'
    except Exception as error:
        result['errors'].append(repr(error))
        (out/'failure.txt').write_text(traceback.format_exc())
        print('GUI_TIMING failure: '+repr(error), flush=True)
    finally:
        try:
            if profiler and profiler.poll() is None:
                profiler.terminate()
                profiler.wait(timeout=10)
                profiler_log.close()
            if typing_process and typing_process.poll() is None:
                typing_process.terminate()
                typing_process.wait(timeout=10)
            if observer:
                (work/'stop-observer').touch()
                observer.wait(timeout=10)
                assert observer.returncode == 0, observer.stderr.read().decode()
                observer_log.close()
            stop()
            if (out/'full-shell.trace').exists() and result['windows'] and 'native' not in result:
                proof = trace_report(out/'full-shell.trace', result['windows'])
                write_json(out/'native.json', proof)
                result['native'] = {k: v for k, v in proof.items() if k not in ('spans', 'waits')}
                result['busyViolations'] = [s for s in proof['spans'] if s['windows'] and s['wallMs'] > args.max_busy_ms]
            command(['niri', 'msg', 'action', 'load-config-file', '--path', restore_config],
                    dict(os.environ, **profile.session_environment()))
            assert hashlib.sha256(restore_config.read_bytes()).hexdigest() == restore_hash
            result['checks']['niriConfigRestored'] = True
            if input_started:
                command(['sudo', '-n', 'systemctl', 'stop', input_unit], env)
            profile.console.verify()
            assert not Path('/etc/keyd/atmosphera').exists()
            assert command(['systemctl', '--user', 'show', 'xremap-atmosphera.service', '-p', 'LoadState', '--value'], env).stdout.strip() == b'not-found'
            result['checks']['originalConsolePreserved'] = True
            # This profile's private runtime contains only owned IPC files and
            # symlinks; keep evidence/work inputs, retire its empty socket root.
            shutil.rmtree(private_runtime)
            result['checks']['cleanup'] = True
        except Exception as error:
            result['errors'].append('cleanup: '+repr(error))
            result['status'] = 'FAIL'
        write_json(out/'result.json', result)
    print('SETTINGS_GUI_TIMING: '+result['status'], flush=True)
    return 0 if result['status'] in ('PASS', 'CONTROL_REPRODUCED') else 1


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--watch-keys':
        watch_keys(Path(sys.argv[2]))
    else:
        raise SystemExit(main())
