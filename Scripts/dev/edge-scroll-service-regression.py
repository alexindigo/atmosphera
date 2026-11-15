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
        check(actions.length===pulses,"pulse/action agreement");
        console.log("PASS hold range and corners");
        console.log("EDGE_SCROLL_SERVICE: PASS");
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
