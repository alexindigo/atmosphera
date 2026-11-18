#!/usr/bin/env python3
"""Guest-only input-context and actual shell secure-demand controls.

The focused-input fixture reuses each entry root's application pragmas.
Native lock/PAM acceptance remains the separate lifecycle proof.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from locker_test_support import require_guest


FOCUS = '''
import QtQuick
import Quickshell
ShellRoot {
  FloatingWindow {
    width: 320; height: 100; visible: true
    TextInput { anchors.fill: parent; focus: true; echoMode: TextInput.Password }
  }
  Timer { interval: 1500; running: true; onTriggered: Qt.quit() }
}
'''

DEMANDS = '''
import QtQuick
import Quickshell
import qs.Services.Keyboard
import qs.Services.Locker
ShellRoot {
  id: root
  property int tick: 0
  property var rows: []
  function check(name, expected) {
    rows.push({name: name, expected: expected, actual: InputMethodService.secureModeActive});
  }
  Timer {
    interval: 50; running: true; repeat: true
    onTriggered: {
      root.tick++;
      if (root.tick === 1) {
        InputMethodService.enterSecureMode("preview");
        root.check("preview holds", true);
        LockerService.locked = true;
      } else if (root.tick === 2) {
        InputMethodService.exitSecureMode("preview");
        root.check("preview exit retains real lock", true);
        InputMethodService.exitSecureMode("preview");
        root.check("duplicate old exit retains real lock", true);
        LockerService.locked = false;
      } else if (root.tick === 3) {
        root.check("last owner restores", false);
        LockerService.locked = true;
        InputMethodService.enterSecureMode("preview");
        LockerService.locked = false;
      } else if (root.tick === 4) {
        root.check("lock exit retains preview", true);
        InputMethodService.exitSecureMode("preview");
        root.check("preview final release", false);
        console.log("IME_DEMAND_RESULT " + JSON.stringify(root.rows));
        Qt.quit();
      }
    }
  }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    results = []
    for config in ('atmosphera-emergency-lock', 'atmosphera-lockscreen'):
        entry = source / 'Quickshell' / config / 'shell.qml'
        pragmas = '\n'.join(line for line in entry.read_text().splitlines() if line.startswith('//@ pragma'))
        directory = work / config
        directory.mkdir()
        (directory / 'shell.qml').write_text(pragmas + '\n' + FOCUS)
        for inherited in ('fcitx', 'ibus'):
            env = dict(os.environ, QT_IM_MODULE=inherited, QT_IM_MODULES=inherited,
                       QT_LOGGING_RULES='qt.qpa.wayland.debug=true;qt.xkb.compose.debug=true')
            process = subprocess.run(['qs', '-p', str(directory), '--no-color'], env=env,
                check=False, text=True, capture_output=True, timeout=15)
            log = process.stdout + process.stderr
            (directory / (inherited + '.log')).write_text(log)
            contexts = re.findall(r'using input method: ([^\n]+)', log)
            passed = bool(contexts) and all('QComposeInputContext' in value for value in contexts)
            results.append(dict(config=config, inherited=inherited, contexts=contexts,
                                passed=passed and process.returncode == 0))

    shell = work / 'demands'
    for directory in ('Services/Keyboard', 'Services/Locker', 'Services/Compositor', 'Services/UI', 'Commons'):
        (shell / directory).mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source / 'Services/Keyboard/InputMethodService.qml', shell / 'Services/Keyboard/InputMethodService.qml')
    (shell / 'Services/Locker/LockerService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool locked: false }\n')
    for directory in ('Services/Compositor', 'Services/UI'):
        (shell / directory / 'Stub.qml').write_text('import QtQuick\nQtObject {}\n')
    (shell / 'Commons/Logger.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
        'function i(a,b) {} function w(a,b,c,d) {} }\n')
    (shell / 'shell.qml').write_text(DEMANDS)
    process = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(shell), '--no-color'],
        env=dict(os.environ, QT_QPA_PLATFORM='offscreen'), check=False,
        text=True, capture_output=True, timeout=15)
    log = process.stdout + process.stderr
    (work / 'demands.log').write_text(log)
    lines = [line.split('IME_DEMAND_RESULT ', 1)[1] for line in log.splitlines() if 'IME_DEMAND_RESULT ' in line]
    rows = json.loads(lines[0]) if len(lines) == 1 else []
    results.append(dict(case='scoped-demands', rows=rows,
        passed=bool(rows) and all(row['actual'] == row['expected'] for row in rows) and process.returncode == 0))
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    print(json.dumps(results, indent=2))
    return 0 if all(row['passed'] for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
