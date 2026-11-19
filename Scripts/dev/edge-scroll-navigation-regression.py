#!/usr/bin/env python3
"""Pure adapter target/outcome contracts through production JS in QML. VM only."""
import os
from pathlib import Path
import subprocess
import tempfile
from workspace_guard import require_disk_backed_paths

QML = r'''
import QtQuick
import Quickshell
import "Helpers/NiriEdgeNavigation.js" as Navigation
ShellRoot {
  Timer {
    interval:0; running:true
    onTriggered: {
      function check(ok,message) { if(!ok) throw new Error(message); }
      function ws(id,idx,output,active,window) {
        return {id:id,idx:idx,output:output,isActive:active,isFocused:active&&output==="A",activeWindowId:window};
      }
      function win(id,workspace,col,floating) {
        return {id:id,workspaceId:workspace,isFloating:!!floating,layout:{posInScrollingLayout:col?[col,1]:[]}};
      }
      try {
        let workspaces=[ws(1,1,"A",true,11),ws(2,2,"A",false,0),ws(3,1,"B",true,31)];
        let windows=[win(11,1,1),win(12,1,2),win(13,1,3),win(31,3,1)];
        function resolve(edge) { return Navigation.resolve("A",edge,workspaces,windows); }
        check(resolve("left").kind==="boundary","first column left wall");
        const right=resolve("right");
        check(right.kind==="navigate"&&right.targetColumn===2,"right neighbour");
        check(resolve("top").kind==="boundary","first workspace top wall");
        const down=resolve("bottom");
        check(down.kind==="navigate"&&down.targetWorkspaceId===2,"trailing empty workspace excluded");
        workspaces[0].activeWindowId=12;
        check(Navigation.outcome(right,workspaces,windows)==="moved","right movement");
        workspaces[0].activeWindowId=11;
        check(Navigation.outcome(right,workspaces,windows)==="unknown","Handled/no change asserted success");
        workspaces[0].activeWindowId=13;
        const left=resolve("left");
        check(resolve("right").kind==="boundary","oversized last column is a wall independent of width");
        workspaces[0].activeWindowId=12;
        check(Navigation.outcome(left,workspaces,windows)==="moved","left movement");
        workspaces[0].activeWindowId=13;
        windows[2].isFloating=true;
        check(resolve("left").kind==="unknown"&&resolve("right").kind==="unknown","floating became a wall");
        check(resolve("top").kind==="unknown","floating workspace bound became a wall");
        windows[2].isFloating=false; windows[2].layout.posInScrollingLayout=[];
        check(resolve("right").kind==="unknown","missing layout became a wall");
        windows[2].layout.posInScrollingLayout=[3,1];
        windows[1].layout.posInScrollingLayout=[4,1];
        check(resolve("right").kind==="unknown","gapped topology became a wall");
        windows[1].layout.posInScrollingLayout=[2,1];
        workspaces[0].isFocused=false; workspaces[2].isFocused=true;
        check(resolve("right").kind==="unknown","wrong output accepted");
        workspaces[0].isActive=false; workspaces[2].isFocused=false;
        workspaces[1].isActive=true; workspaces[1].isFocused=true;
        check(Navigation.outcome(down,workspaces,windows)==="moved","workspace movement");
        check(resolve("bottom").kind==="boundary","last empty workspace bottom wall");
        const up=resolve("top");
        workspaces[1].isActive=false; workspaces[1].isFocused=false;
        workspaces[0].isActive=true; workspaces[0].isFocused=true;
        check(Navigation.outcome(up,workspaces,windows)==="moved","workspace return");
        check(Navigation.resolve("missing","right",workspaces,windows).kind==="unknown","missing output");
        console.log("EDGE_SCROLL_NAVIGATION: PASS four directions, real bounds, trailing empty, floating/missing state, moved vs unknown");
      } catch(error) { console.error("EDGE_SCROLL_NAVIGATION: FAIL " + error); }
      Qt.quit();
    }
  }
}
'''

if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2]
    require_disk_backed_paths(root, os.environ['TMPDIR'])
    with tempfile.NamedTemporaryFile(mode='w', suffix='.qml', prefix='edge-navigation-', dir=root) as fixture:
        fixture.write(QML); fixture.flush()
        result = subprocess.run(['qs','-p',fixture.name,'--no-color'], capture_output=True, text=True,
                                timeout=60, env=dict(os.environ, QT_QPA_PLATFORM='wayland'))
    text=result.stdout+result.stderr
    print(text)
    assert result.returncode==0 and 'EDGE_SCROLL_NAVIGATION: PASS' in text
    assert not any(error in text for error in ['TypeError:', 'ReferenceError:', 'SyntaxError:'])
