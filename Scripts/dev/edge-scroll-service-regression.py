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
  property var outcomes: []
  property bool autoComplete: true
  readonly property var outer: ({key:"A:right",screenName:"A",edge:"right",inner:false})
  readonly property var inner: ({key:"B:left",screenName:"B",edge:"left",inner:true})
  EdgeScrollController {
    id: controller
    autoTick: false
    gates: ({setting:true,niri:true,framed:true,barVisible:true,overview:false,hideOnOverview:false})
    clock: function() { return test.now; }
    actionSink: function(zone, requestId) {
      test.actions.push({key:zone.key,id:requestId,at:test.now});
      if (test.autoComplete) controller.resolveNavigation(requestId,"moved");
    }
    onNavigationFinished: (zone,outcome) => test.outcomes.push({key:zone.key,outcome:outcome})
  }
  function check(ok, message) { if(!ok) throw new Error(message); }
  function advance(ms) { now+=ms; controller.tick(); }
  function count(n) { check(actions.length===n,"wrong request count " + actions.length + "/" + n); }
  function timing(zone, first, repeat) {
    controller.cancel();
    const before=actions.length;
    controller.enter(zone,0);
    advance(first/2); count(before); check(controller.progress===0.5,"first ramp denominator " + first);
    advance(first/2-1); count(before); check(controller.progress<1,"first ramp saturated early");
    advance(1); count(before+1); check(controller.progress===0,"repeat ramp reset");
    advance(repeat/2); check(controller.progress===0.5,"repeat ramp denominator " + repeat);
    advance(repeat/2-1); count(before+1); advance(1); count(before+2);
    advance(repeat*4); count(before+3); // no catch-up bursts
    controller.leave(zone.key); advance(2000); count(before+3);
    check(!controller.activeZone && controller.progress===0,"leave cancellation");
  }
  Timer {
    interval: 0; running:true
    onTriggered: {
      try {
        check(controller.holdMs===600 && controller.repeatMs===900,"defaults must be 600/900");
        timing(outer,600,900); timing(inner,800,900);
        controller.holdMs=650; timing(outer,650,975); timing(inner,850,975);
        controller.holdMs=400; timing(outer,400,600);
        console.log("PASS default 600/900, seam 800/900, custom 650/975, explicit 400/600, phase ramps and no catch-up");
        for(let hold of [200,1000]) {
          controller.holdMs=hold; timing(outer,hold,Math.round(hold*1.5));
        }
        controller.holdMs=600;
        controller.enter(outer,0); advance(300); controller.buttonsChanged(1);
        const before=actions.length; advance(2000); count(before);
        controller.enter(outer,1); advance(2000); count(before);
        controller.buttonsChanged(0);
        controller.enter(outer,0); advance(300); controller.enter(inner,0);
        advance(799); count(before); advance(1); count(before+1);
        console.log("PASS held button, stationary press and zone-switch cancellation");
        for(let mask=0;mask<64;++mask) {
          const gates={setting:!!(mask&1),niri:!!(mask&2),framed:!!(mask&4),barVisible:!!(mask&8),overview:!!(mask&16),hideOnOverview:!!(mask&32)};
          controller.cancel(); controller.gates=gates;
          const allowed=gates.setting && gates.niri && gates.framed && gates.barVisible && !(gates.overview && gates.hideOnOverview);
          check(controller.enabled===allowed,"gate " + mask);
          const requests=actions.length;
          controller.enter(outer,0); advance(600);
          check(actions.length===requests+(allowed?1:0),"gated request " + mask);
          controller.gates={setting:false,niri:true,framed:true,barVisible:true,overview:false,hideOnOverview:false};
          check(!controller.activeZone && controller.progress===0,"gate did not cancel");
        }
        console.log("PASS all 64 gate combinations and immediate cancellation");
        controller.gates={setting:true,niri:true,framed:true,barVisible:true,overview:false,hideOnOverview:false};
        autoComplete=false;
        const finished=outcomes.length;
        controller.enter(outer,0); advance(600);
        const pending=actions[actions.length-1].id, requests=actions.length;
        check(outcomes.length===finished,"attempt asserted success");
        advance(3000); count(requests); // one outstanding request, never a backlog
        controller.resolveNavigation(pending+1,"moved"); check(outcomes.length===finished,"uncorrelated result accepted");
        controller.resolveNavigation(pending,"boundary");
        check(outcomes.length===finished+1 && outcomes[outcomes.length-1].outcome==="boundary","boundary result lost");
        controller.resolveNavigation(pending,"moved"); check(outcomes.length===finished+1,"duplicate result accepted");
        advance(1); count(requests+1);
        const stale=actions[actions.length-1].id;
        controller.cancel(); controller.enter(inner,0); advance(800);
        controller.resolveNavigation(stale,"moved"); check(outcomes.length===finished+1,"stale result crossed hold");
        controller.resolveNavigation(actions[actions.length-1].id,"unknown");
        check(outcomes[outcomes.length-1].outcome==="unknown","unknown result changed");
        controller.cancel(); autoComplete=true;
        console.log("PASS correlated outcomes, no attempt success, duplicate/stale replies and serialization");
        const sourceA={}, sourceB={};
        for (const leaveFirst of [false,true]) {
          controller.cancel(); controller.enter(outer,0,sourceA); advance(300);
          if (leaveFirst) controller.leave(outer.key,sourceA);
          controller.enter(outer,0,sourceB);
          if (!leaveFirst) controller.leave(outer.key,sourceA);
          check(controller.activeZone && controller.progress===0.5,"surface handoff restarted hold");
          const requests=actions.length;
          advance(299); count(requests); advance(1); count(requests+1);
        }
        const handoffRequests=actions.length;
        Qt.callLater(function() {
          try {
            check(controller.activeZone,"deferred leave cancelled replacement");
            advance(899); count(handoffRequests); advance(1); count(handoffRequests+1);
            controller.leave(outer.key,sourceB);
            check(!controller.activeZone && controller.progress===0,"real leave not prompt");
            Qt.callLater(function() {
              try {
                advance(2000); count(handoffRequests+1);
                controller.enter(outer,0,sourceA); advance(300);
                controller.leave(outer.key,sourceA); controller.enter(outer,0,sourceA);
                check(controller.progress===0,"same-surface re-entry retained hold");
                advance(599); count(handoffRequests+1); advance(1); count(handoffRequests+2);
                controller.cancel(); controller.enter(null,0); advance(2000);
                check(!controller.activeZone,"corner activated");
                console.log("PASS hold range, corners, both handoff orders, deferred ownership and fresh re-entry");
                console.log("EDGE_SCROLL_SERVICE: PASS");
              } catch(error) { console.error("EDGE_SCROLL_SERVICE: FAIL " + error); }
              Qt.quit();
            });
          } catch(error) { console.error("EDGE_SCROLL_SERVICE: FAIL " + error); Qt.quit(); }
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
    with tempfile.NamedTemporaryFile(mode='w', suffix='.qml', prefix='edge-service-', dir=root) as fixture:
        fixture.write(QML)
        fixture.flush()
        result = subprocess.run(['qs', '-p', fixture.name, '--no-color'], text=True, capture_output=True,
                                timeout=120, env=dict(os.environ, QT_QPA_PLATFORM='wayland'))
    print(result.stdout + result.stderr)
    assert result.returncode == 0 and 'EDGE_SCROLL_SERVICE: PASS' in result.stdout + result.stderr
    assert not any(error in result.stdout + result.stderr for error in ['TypeError:', 'ReferenceError:', 'SyntaxError:'])
