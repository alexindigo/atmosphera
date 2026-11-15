#!/usr/bin/env python3
"""Drive the production QML timing controller with a fake clock, in the VM."""
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
  property var actions: []
  property int pulses: 0
  EdgeScrollController {
    id: controller
    autoTick: false
    holdMs: 400
    gates: ({setting:true,niri:true,framed:true,barVisible:true,overview:false,hideOnOverview:false})
    clock: function() { return test.now; }
    actionSink: function(zone) { test.actions.push(zone.key); }
    onStepped: test.pulses++
  }
  function check(ok, message) { if(!ok) throw new Error(message); }
  function at(time) { now=time; controller.tick(); }
  function count(n) { check(actions.length===n && pulses===n, "wrong action/pulse count " + actions.length + "/" + n); }
  Timer {
    interval: 0; running:true
    onTriggered: {
      try {
        const outer={key:"A:right",screenName:"A",edge:"right",inner:false};
        const inner={key:"B:left",screenName:"B",edge:"left",inner:true};
        controller.enter(outer,0);
        at(200); count(0); check(controller.progress===0.5,"outer half ramp");
        at(399); count(0); at(400); count(1); check(controller.progress===0,"repeat restarts ramp");
        at(799); count(1); at(800); count(2);
        controller.leave(outer.key); at(2000); count(2); check(!controller.activeZone && controller.progress===0,"leave cancellation");
        console.log("PASS first step, repeat and leave");
        controller.enter(inner,0); at(2400); count(2); check(controller.progress===1,"inner ramp stays informational");
        at(2599); count(2); at(2600); count(3); at(2999); count(3); at(3000); count(4);
        controller.buttonsChanged(1); at(4000); count(4); check(!controller.activeZone,"button press cancellation");
        controller.enter(outer,1); at(5000); count(4); controller.buttonsChanged(0);
        controller.enter(outer,0); at(5200); controller.enter(inner,0); at(5599); count(4); at(5799); count(4); at(5800); count(5);
        console.log("PASS inner delay, held button and zone switch");
        // Every gating combination uses the actual production enabled binding.
        for(let mask=0;mask<64;++mask) {
          const gates={setting:!!(mask&1),niri:!!(mask&2),framed:!!(mask&4),barVisible:!!(mask&8),overview:!!(mask&16),hideOnOverview:!!(mask&32)};
          controller.cancel(); controller.gates=gates;
          const allowed=gates.setting && gates.niri && gates.framed && gates.barVisible && !(gates.overview && gates.hideOnOverview);
          check(controller.enabled===allowed,"gate " + mask);
          const before=actions.length;
          controller.enter(outer,0); at(now+400);
          check(actions.length===before+(allowed?1:0),"gated action " + mask);
          controller.gates={setting:false,niri:true,framed:true,barVisible:true,overview:false,hideOnOverview:false};
          check(!controller.activeZone && controller.progress===0,"gating change did not cancel");
        }
        console.log("PASS 64 gate combinations and immediate cancellation");
        controller.gates={setting:true,niri:true,framed:true,barVisible:true,overview:false,hideOnOverview:false};
        for(let hold of [200,1000]) {
          controller.holdMs=hold;
          controller.enter(outer,0);
          const before=actions.length;
          at(now+hold-1); check(actions.length===before,"early step at hold " + hold);
          at(now+1); check(actions.length===before+1,"missing step at hold " + hold);
          controller.cancel();
        }
        controller.enter(null,0); at(now+2000); check(!controller.activeZone,"corner/null zone activated");
        const sourceA={}, sourceB={};
        controller.holdMs=400;
        controller.enter(outer,0,sourceA); at(now+200);
        controller.enter(outer,0,sourceB);
        controller.leave(outer.key,sourceA);
        check(controller.activeZone && controller.progress===0.5,"stale surface leave or restarted hold");
        const before=actions.length;
        at(now+200); check(actions.length===before+1,"surface handoff lost step");
        controller.leave(outer.key,sourceB); check(!controller.activeZone,"current surface leave ignored");
        // A leave/re-enter on the same surface is not a handoff.
        controller.enter(outer,0,sourceA); at(now+200);
        controller.leave(outer.key,sourceA); controller.enter(outer,0,sourceA);
        check(controller.progress===0,"same-surface re-entry retained old hold");
        const reentrySteps=actions.length;
        at(now+399); check(actions.length===reentrySteps,"same-surface re-entry stepped early");
        at(now+1); check(actions.length===reentrySteps+1,"same-surface re-entry missing step");
        // Surface ownership can change in either event order within one turn.
        // Keep the original enter-before-leave assertions above as well.
        for (const leaveFirst of [false,true]) {
          controller.cancel();
          controller.enter(outer,0,sourceA); at(now+200);
          if (leaveFirst) controller.leave(outer.key,sourceA);
          controller.enter(outer,0,sourceB);
          if (!leaveFirst) controller.leave(outer.key,sourceA);
          check(controller.activeZone && controller.progress===0.5,"handoff order restarted hold: " + leaveFirst);
          const steps=actions.length;
          at(now+199); check(actions.length===steps,"handoff stepped early: " + leaveFirst);
          at(now+1); check(actions.length===steps+1,"handoff lost deadline: " + leaveFirst);
        }
        const steps=actions.length;
        Qt.callLater(function() {
          try {
            check(controller.activeZone,"deferred leave cancelled replacement surface");
            at(now+400); check(actions.length===steps+1,"handoff lost repeat after event turn");
            controller.leave(outer.key,sourceB);
            check(!controller.activeZone && controller.progress===0,"real leave did not cancel promptly");
            at(now+1000); check(actions.length===steps+1,"real leave fired a pending step");
            Qt.callLater(function() {
              try {
                check(!controller.activeZone && controller.progress===0,"real leave survived event turn");
                controller.enter(outer,0,sourceA);
                at(now+399); check(actions.length===steps+1,"real leave retained old hold");
                at(now+1); check(actions.length===steps+2,"fresh hold after real leave missing");
                check(actions.length===pulses,"pulse/action agreement");
                console.log("PASS hold range, corners and surface handoff");
                console.log("PASS both surface handoff orders, deferred ownership and prompt real leave");
                console.log("EDGE_SCROLL_SERVICE: PASS");
              } catch(error) { console.error("EDGE_SCROLL_SERVICE: FAIL " + error); }
              Qt.quit();
            });
          } catch(error) {
            console.error("EDGE_SCROLL_SERVICE: FAIL " + error);
            Qt.quit();
          }
        });
        return;
      } catch(error) { console.error("EDGE_SCROLL_SERVICE: FAIL " + error); }
      Qt.quit();
    }
  }
}
'''


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2]
    require_disk_backed_paths(root, os.environ['TMPDIR'])
    # Root-local fixture lets Quickshell generate the production qs imports.
    with tempfile.NamedTemporaryFile(mode='w', suffix='.qml', prefix='edge-service-', dir=root) as fixture:
        fixture.write(QML)
        fixture.flush()
        result = subprocess.run(['qs', '-p', fixture.name, '--no-color'], text=True, capture_output=True,
                                timeout=120, env=dict(os.environ, QT_QPA_PLATFORM='wayland'))
    print(result.stdout + result.stderr)
    assert result.returncode == 0 and 'EDGE_SCROLL_SERVICE: PASS' in result.stdout + result.stderr
    assert not any(error in result.stdout + result.stderr for error in ['TypeError:', 'ReferenceError:', 'SyntaxError:'])
