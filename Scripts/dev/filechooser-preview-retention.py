#!/usr/bin/env python3
"""Post-GC retention and capability contract of actual FilePreview lifetimes."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from filechooser_isolation import ROOT, enter, profile_env
from filechooser_leaks import build_probe, checkpoint, instrument_choosers


def main():
    enter(runtime_seconds=480)
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--label', required=True)
    p.add_argument('--pdf-unavailable', action='store_true', help='exercise actual optional-import failure in a disposable copy')
    a = p.parse_args()
    source = a.source.resolve()
    assert source.is_relative_to(ROOT / 'sources')
    runtime, output = ROOT / 'runtime' / a.label, ROOT / 'evidence' / a.label
    runtime.mkdir(); output.mkdir()
    shell = runtime / 'shell'
    shutil.copytree(source, shell, symlinks=True)
    instrument_choosers(shell, output)
    if a.pdf_unavailable:
        optional = shell / 'Services/Files/OptionalPdfProbe.qml'
        assert optional.exists()
        optional.write_text('import F10IntentionallyMissingPdf 1.0\nimport QtQml\nQtObject {}\n')
        shutil.copy2(optional, output / 'unavailable-probe.qml')
    library = build_probe(source, runtime, output)
    address = Path(os.environ['FILECHOOSER_ISOLATION']) / 'run/native-heap.sock'
    probe = shell / 'preview-retention.qml'
    probe.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Files
ShellRoot {
  id: root
  property int completed: 0
  property int pending: 0
  property int failures: 0
  Component { id: factory; FilePreview {} }
  function next() {
    if (pending === 0) return;
    var preview = factory.createObject(root);
    if (!preview || !preview.pdfDetectionDone || preview.pdfAvailable !== EXPECTED_PDF || F10LeakLedger.live.previews !== 1) ++failures;
    if (preview) preview.destroy();
    --pending; ++completed; Qt.callLater(root.next);
  }
  IpcHandler {
    target: "f8Shell"
    function state(): string { return JSON.stringify({completed:root.completed,pending:root.pending,failures:root.failures,pid:Quickshell.processId}); }
    function batch(count: int): void { root.pending = count; root.next(); }
    function leakCounts(): string { return JSON.stringify(F10LeakLedger.snapshot()); }
    function leakCheckpoint(token: string): string {
      Logger.i("F10Leak", "GC_BEGIN_" + token); gc(); Logger.i("F10Leak", "GC_END_" + token);
      return JSON.stringify(F10LeakLedger.snapshot());
    }
    function quit(): void { Qt.quit(); }
  }
}
'''.replace('EXPECTED_PDF', 'false' if a.pdf_unavailable else 'true'))
    shutil.copy2(probe, output / probe.name)
    env = dict(profile_env(runtime / 'profile'), MALLOC_CONF='dirty_decay_ms:0,muzzy_decay_ms:0',
               QV4_MM_STATS='1', QV4_GC_TIMINGS='1',
               QT_LOGGING_RULES='qt.qml.gc.statistics=true;qt.qml.gc.allocatorStats=true')
    (runtime / 'profile/config/settings.json').write_text((source / 'Configs/defaults.json').read_text())
    cases, rows = [], []
    complete, failure = False, ''
    def check(name, condition, detail=None):
        cases.append({'case': name, 'pass': bool(condition), 'detail': detail})
        print(name, 'PASS' if condition else 'FAIL', flush=True)
        assert condition, name
    def ipc(target, member, *values, check=True):
        return subprocess.run(['timeout', '10', 'qs', '-p', str(probe), 'ipc', 'call', target, member, *map(str, values)],
                              env=env, capture_output=True, text=True, check=check, timeout=15).stdout.strip()
    def state():
        return json.loads(ipc('f8Shell', 'state'))
    log_path = output / 'subject.log'
    with log_path.open('w') as log:
        app = subprocess.Popen(['timeout', '400', sys.executable, '-B', str(source / 'Scripts/dev/filechooser-no-thp.py'),
                                'env', 'LD_PRELOAD=' + str(library), 'FILECHOOSER_NATIVE_SOCKET=' + str(address),
                                'qs', '-p', str(probe)], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            end = time.monotonic() + 30
            while not address.exists() or not ipc('f8Shell', 'state', check=False).startswith('{'):
                assert app.poll() is None and time.monotonic() < end, 'cold start'
                time.sleep(.1)
            pid = state()['pid']
            for count in ([1] if a.pdf_unavailable else range(200, 1201, 200)):
                ipc('f8Shell', 'batch', 1 if a.pdf_unavailable else 200)
                end = time.monotonic() + 40
                while state()['pending']:
                    assert app.poll() is None and time.monotonic() < end
                    time.sleep(.03)
                check(f'{count}-actual-previews-PDF-detected', state() == {'completed': count, 'pending': 0, 'failures': 0, 'pid': pid}, state())
                time.sleep(.3)
                row = checkpoint(ipc, log_path, address, output, count, pid)
                row['previews'] = count
                check(f'{count}-preview-objects-released', row['chooser_live']['previews'] == 0
                      and row['chooser_totals']['created']['previews'] == row['chooser_totals']['destroyed']['previews'] == count)
                rows.append(row)
                (output / 'memory.json').write_text(json.dumps(rows, indent=2))
            if not a.pdf_unavailable:
                native = rows[-1]['native']['allocated_bytes'] - rows[0]['native']['allocated_bytes']
                js = rows[-1]['js_live_bytes'] - rows[0]['js_live_bytes']
                check('1000-preview-native-retention-bounded', native < 1024 * 1024,
                      {'measured': 1000, 'warmup': 200, 'growth_bytes': native, 'limit_bytes': 1024 * 1024, 'js_growth_bytes': js})
            ipc('f8Shell', 'quit'); app.wait(timeout=15)
            check('cold-subject-exit', app.returncode == 0)
            complete = True
        except Exception as error:
            failure = repr(error)
            raise
        finally:
            if app.poll() is None:
                ipc('f8Shell', 'quit'); app.wait(timeout=15)
            (output / 'result.json').write_text(json.dumps({'passed': complete and all(c['pass'] for c in cases),
                'complete': complete, 'failure': failure, 'cases': cases, 'memory': rows}, indent=2))


if __name__ == '__main__':
    main()
