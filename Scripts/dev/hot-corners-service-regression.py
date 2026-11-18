#!/usr/bin/env python3
"""Drive the production hot corner dwell controller with a fake clock, in the VM."""
import os
from pathlib import Path
import subprocess
import tempfile
from workspace_guard import require_disk_backed_paths


QML = r'''
import QtQuick
import Quickshell
import qs.Services.UI
ShellRoot {
  id: test
  property real now: 0
  property var runs: []
  readonly property string stored: "printf '%s\\n' \"a b\" $HOME 'c'\"d\" >> /dev/null; echo \\$x"
  readonly property var tl: ({kind:"corner",corner:"topLeft",screenName:"A",key:"A:corner:topLeft",rect:{x:0,y:0,width:5,height:5}})
  readonly property var br: ({kind:"corner",corner:"bottomRight",screenName:"A",key:"A:corner:bottomRight",rect:{x:995,y:795,width:5,height:5}})
  readonly property var tr2: ({kind:"corner",corner:"topRight",screenName:"B",key:"B:corner:topRight",rect:{x:995,y:0,width:5,height:5}})
  HotCornersController {
    id: controller
    autoTick: false
    gateOpen: true
    delayMs: 200
    commands: ({topLeft: test.stored, topRight: "echo tr", bottomLeft: "", bottomRight: "echo br"})
    clock: function() { return test.now; }
    runSink: function(zone, command) { test.runs.push({key: zone.key, command: command, at: test.now}); }
  }
  function check(ok, message) { if (!ok) throw new Error(message); }
  function advance(ms) { now += ms; controller.tick(); }
  function count(n, message) { check(runs.length === n, (message || "") + " wrong run count " + runs.length + "/" + n); }
  function reset() { controller.cancel(); controller.gateOpen = true; }
  Timer {
    interval: 0; running: true
    onTriggered: {
      const sA = {}, sB = {};
      try {
        // Row 1: a new corner starts the dwell; nothing runs before delayMs.
        controller.enter(tl, 0, sA); advance(199); count(0, "row 1 early");
        check(controller.dwelling, "row 1 not dwelling");
        advance(1); count(1, "row 1 fire");
        // Exact stored string reaches the sink, verbatim.
        check(runs[0].command === stored && runs[0].key === tl.key, "row 3 sink got " + JSON.stringify(runs[0]));
        // Row 4: staying in the corner never repeats.
        advance(5000); controller.enter(tl, 0, sA); advance(5000); count(1, "row 4 repeat");
        check(controller.activeZone && !controller.dwelling, "row 3 not disarmed after firing");
        console.log("PASS rows 1, 3, 4: dwell, one exact run, no repeat while held");
        reset();
        // Row 2: a second source on the same corner keeps the running dwell.
        controller.enter(tl, 0, sA); advance(100);
        controller.enter(tl, 0, sB); advance(99); count(1, "row 2 restarted"); advance(1); count(2, "row 2 fire");
        // Row 3: disarmed until every source has left.
        controller.leave(tl.key, sA); advance(1000); count(2, "row 3 one source left");
        controller.enter(tl, 0, sA); advance(1000); count(2, "row 3 re-entry while other source present");
        controller.leave(tl.key, sA); controller.leave(tl.key, sB);
        check(!controller.activeZone, "row 5 last leave not prompt");
        console.log("PASS rows 2, 3: second source keeps the dwell; disarmed until every source left");
        Qt.callLater(function() {
          try {
            // Row 5: the last leave re-arms; a new visit dwells afresh.
            controller.enter(tl, 0, sA); advance(199); count(2, "row 5 early"); advance(1); count(3, "row 5 re-armed");
            reset();
            controller.enter(br, 0, sA); advance(150); controller.leave(br.key, sA);
            check(!controller.activeZone, "row 5 leave during dwell");
            Qt.callLater(function() {
              try {
                advance(1000); count(3, "row 5 cancelled dwell ran");
                controller.enter(br, 0, sA); advance(199); count(3, "row 5 fresh dwell early"); advance(1); count(4, "row 5 fresh dwell");
                check(runs[3].command === "echo br", "row 5 command");
                console.log("PASS row 5: last leave cancels and re-arms");
                reset();
                // Row 6: entering with a button held never dwells; disarmed until leave.
                controller.enter(br, 1, sA); advance(2000); count(4, "row 6 entered pressed");
                controller.buttonsChanged(0); controller.enter(br, 0, sA); advance(2000); count(4, "row 6 release re-armed");
                // Row 6: a press during the dwell cancels it, disarmed until leave.
                reset();
                controller.enter(br, 0, sA); advance(150); controller.buttonsChanged(1); advance(1000); count(4, "row 6 press");
                controller.buttonsChanged(0); controller.enter(br, 0, sA); advance(1000); count(4, "row 6 press re-armed");
                controller.enter(br, 1, sA); advance(1000); count(4, "row 6 pressed enter");
                controller.leave(br.key, sA);
                Qt.callLater(function() {
                  try {
                    controller.enter(br, 0, sA); advance(200); count(5, "row 6 leave re-arms");
                    console.log("PASS row 6: held or pressed buttons cancel and disarm until leave");
                    // Row 7: gate closes, delay changes, the active corner's command changes.
                    reset();
                    controller.enter(tl, 0, sA); advance(150); controller.gateOpen = false;
                    check(!controller.activeZone, "row 7 gate did not cancel");
                    advance(1000); count(5, "row 7 gate");
                    controller.enter(tl, 0, sA); advance(1000); count(5, "row 7 locked enter");
                    controller.gateOpen = true;
                    controller.enter(tl, 0, sA); advance(150); controller.delayMs = 300;
                    check(!controller.activeZone, "row 7 delay did not cancel");
                    advance(1000); count(5, "row 7 delay");
                    controller.enter(tl, 0, sA); advance(299); count(5, "row 7 new delay early"); advance(1); count(6, "row 7 new delay");
                    controller.delayMs = 200;
                    controller.enter(tr2, 0, sA); advance(150);
                    controller.commands = ({topLeft: test.stored, topRight: "echo tr", bottomLeft: "", bottomRight: "echo other"});
                    check(controller.activeZone && controller.dwelling, "row 7 other corner's change cancelled");
                    controller.commands = ({topLeft: test.stored, topRight: "echo tr changed", bottomLeft: "", bottomRight: "echo other"});
                    check(!controller.activeZone, "row 7 active command change did not cancel");
                    advance(1000); count(6, "row 7 command");
                    controller.enter(tr2, 0, sA); advance(200); count(7, "row 7 changed command");
                    check(runs[6].command === "echo tr changed", "row 7 new command not used");
                    console.log("PASS row 7: gate, delay and active command changes cancel");
                    // Empty corner command, corner switch, screen removal, surface handoff.
                    reset();
                    const bl = {kind:"corner",corner:"bottomLeft",screenName:"A",key:"A:corner:bottomLeft",rect:{x:0,y:795,width:5,height:5}};
                    controller.enter(bl, 0, sA); advance(1000); count(7, "empty command ran");
                    controller.enter(tl, 0, sA); advance(100); controller.enter(br, 0, sA); advance(150); count(7, "switch kept old dwell"); advance(50); count(8, "switched corner");
                    check(runs[7].key === br.key, "switched corner key");
                    reset();
                    controller.enter(tl, 0, sA); advance(100); controller.leaveScreen("A");
                    check(!controller.activeZone, "leaveScreen"); advance(1000); count(8, "leaveScreen ran");
                    controller.enter(tl, 0, sA); advance(200); count(9, "handoff setup");
                    controller.leave(tl.key, sA); controller.enter(tl, 0, sB);
                    Qt.callLater(function() {
                      try {
                        check(controller.activeZone && !controller.dwelling, "replacement surface lost disarm");
                        advance(2000); count(9, "replacement surface repeated");
                        console.log("PASS empty corner, corner switch, screen removal and replacement-surface handoff");
                        console.log("HOT_CORNERS_SERVICE: PASS");
                      } catch (error) { console.error("HOT_CORNERS_SERVICE: FAIL " + error); }
                      Qt.quit();
                    });
                  } catch (error) { console.error("HOT_CORNERS_SERVICE: FAIL " + error); Qt.quit(); }
                });
              } catch (error) { console.error("HOT_CORNERS_SERVICE: FAIL " + error); Qt.quit(); }
            });
          } catch (error) { console.error("HOT_CORNERS_SERVICE: FAIL " + error); Qt.quit(); }
        });
        return;
      } catch (error) { console.error("HOT_CORNERS_SERVICE: FAIL " + error); }
      Qt.quit();
    }
  }
}
'''


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2]
    require_disk_backed_paths(root, os.environ['TMPDIR'])
    with tempfile.NamedTemporaryFile(mode='w', suffix='.qml', prefix='hot-corners-service-', dir=root) as fixture:
        fixture.write(QML)
        fixture.flush()
        result = subprocess.run(['qs', '-p', fixture.name, '--no-color'], text=True, capture_output=True,
                                timeout=120, env=dict(os.environ, QT_QPA_PLATFORM='wayland'))
    print(result.stdout + result.stderr)
    assert result.returncode == 0 and 'HOT_CORNERS_SERVICE: PASS' in result.stdout + result.stderr
    assert not any(error in result.stdout + result.stderr for error in ['TypeError:', 'ReferenceError:', 'SyntaxError:'])
