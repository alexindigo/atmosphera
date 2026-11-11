#!/usr/bin/env python3
"""Actual Quickshell engine reload with production Settings save IO outstanding.

Assigned guest only. The surrounding gate owns the source/install workspace.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
from native_settings_controls import prepare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'installed', 'output', 'work-root'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    args.work_root.mkdir(parents=True, exist_ok=False)
    build, contract = prepare(args.source)
    config = args.work_root/'config'
    (config/'settings').mkdir(parents=True)
    legacy = config/'settings.json'
    legacy.write_text('{"settingsVersion":62,"opaque":{"wide":18446744073709551615}}')
    before = (legacy.read_bytes(), legacy.stat().st_ino, legacy.stat().st_mtime_ns, legacy.stat().st_mode)
    (config/'plugins.json').write_text('{"version":5,"states":{},"sources":[]}')
    target = config/'settings/ui.json'
    target.write_text('{"fontDefaultScale":1,"opaque":{"keep":[false,0,null,""]}}')
    marker, gate, schedule = (args.work_root/name for name in ('held','release','schedule.json'))
    os.mkfifo(gate, 0o600)
    schedule.write_text(json.dumps(dict(rules=[dict(file=str(target),phase='rename',marker=str(marker),gate=str(gate))])))
    entry = args.installed/'i5-engine-lifetime.qml'
    with entry.open('xb') as stream:
        stream.write((args.source/'Scripts/dev/fixtures/settings-engine-lifetime.qml').read_bytes())
    # Unix IPC sockets have a short pathname ceiling. Keep this owned runtime
    # disk-backed without appending the full descriptive gate/work-root name.
    runtime = Path(tempfile.mkdtemp(prefix='el-', dir=os.environ['TMPDIR']))
    env = dict(os.environ,QML_IMPORT_PATH=str(build),LD_PRELOAD=str(build/'libatmosphera_native_io.so'),
        ATCQ_NATIVE_SCHEDULE=str(schedule),ATMOSPHERA_CONFIG_DIR=str(config),
        ATMOSPHERA_CACHE_DIR=str(args.work_root/'cache'),ATMOSPHERA_STATE_DIR=str(args.work_root/'state'),
        XDG_RUNTIME_DIR=str(runtime),QML_DISABLE_DISK_CACHE='1')
    process = ipc = None
    released = False
    def release():
        nonlocal released
        descriptor = os.open(gate,os.O_WRONLY|os.O_NONBLOCK)
        try: os.write(descriptor,b'0\n')
        finally: os.close(descriptor)
        released = True
    try:
        with (args.output/'reload.log').open('x') as log:
            process = subprocess.Popen(['qs','-p',str(entry),'--no-color'],env=env,
                stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
            deadline = time.monotonic()+20
            while not marker.exists():
                assert process.poll() is None and time.monotonic()<deadline,'native rename hold not reached'
                time.sleep(.02)
            assert json.loads(target.read_text())['fontDefaultScale'] == 1
            with (args.output/'reload-ipc.log').open('x') as ipc_log:
                ipc = subprocess.Popen(['timeout','15','qs','-p',str(entry),'ipc','call','engineLifetime','reloadPending'],
                    env=env,stdout=ipc_log,stderr=subprocess.STDOUT)
                deadline = time.monotonic()+10
                while 'ENGINE_LIFETIME: RELOAD_PENDING' not in (args.output/'reload.log').read_text():
                    assert process.poll() is None and time.monotonic()<deadline,'pending native reload not observed'
                    time.sleep(.02)
                assert json.loads(target.read_text())['fontDefaultScale'] == 1
                release()
                assert ipc.wait(timeout=20) == 0
            assert process.wait(timeout=25) == 0
        text = (args.output/'reload.log').read_text()
        assert text.count('ENGINE_LIFETIME: ENGINE_READY') == 2,text[-6000:]
        assert 'ENGINE_LIFETIME: CONSUMER_CLOSE_PASS' in text
        assert not any(token in text for token in ('ENGINE_LIFETIME_ASSERT:','TypeError:','ReferenceError:','SyntaxError:','Failed to load configuration'))
        expected = dict(fontDefaultScale=1.25,opaque=dict(keep=[False,0,None,'']))
        assert json.loads(target.read_text()) == expected
        cold_env = dict(env,I5_ENGINE_COLD='1')
        cold_env.pop('LD_PRELOAD'); cold_env.pop('ATCQ_NATIVE_SCHEDULE')
        cold = subprocess.run(['timeout','25','qs','-p',str(entry),'--no-color'],env=cold_env,
            capture_output=True,text=True,timeout=30)
        text = cold.stdout+cold.stderr; (args.output/'cold.log').write_text(text)
        assert cold.returncode == 0 and 'ENGINE_LIFETIME: CONSUMER_CLOSE_PASS' in text,text[-6000:]
        assert not any(token in text for token in ('ENGINE_LIFETIME_ASSERT:','TypeError:','ReferenceError:','SyntaxError:'))
        assert json.loads(target.read_text()) == expected
        assert before == (legacy.read_bytes(),legacy.stat().st_ino,legacy.stat().st_mtime_ns,legacy.stat().st_mode)
        (args.output/'result.json').write_text(json.dumps(dict(status='PASS',controls=contract,
            cases=['native-save-held','reload-during-pending-save','new-engine-consumer','separate-cold-consumer','async-close'],
            rawUnknownPreserved=True,legacyUnchanged=True,runtimeRoot=str(runtime),entrySha256=hashlib.sha256(entry.read_bytes()).hexdigest()),indent=2)+'\n')
        print('SETTINGS_ENGINE_LIFETIME: PASS')
    finally:
        if marker.exists() and not released:
            release()
        if ipc is not None and ipc.poll() is None:
            ipc.wait(timeout=20)
        if process is not None and process.poll() is None:
            assert Path('/proc/'+str(process.pid)).stat().st_uid == os.getuid()
            assert b'i5-engine-lifetime.qml' in Path('/proc/'+str(process.pid)+'/cmdline').read_bytes()
            os.killpg(process.pid,signal.SIGTERM); process.wait(timeout=10)
        entry.unlink()


if __name__ == '__main__':
    main()
