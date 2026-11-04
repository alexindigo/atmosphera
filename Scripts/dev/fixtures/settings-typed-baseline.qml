// Native QML coercion and selected-value equality, not raw preferences.
import QtQuick
import Quickshell
import qs.Widgets

Item {
  id: root
  property var source: ({color:null, opacity:null, count:1.5, text:null, enabled:null, rows:[{name:"one",address:"127.0.0.1"}]})
  NSettingsBaseline {
    id: baseline
    readonly property color paint: root.source.color
    readonly property real opacity: root.source.opacity
    readonly property int count: root.source.count
    readonly property string text: root.source.text
    readonly property bool enabled: root.source.enabled
    readonly property var rows: root.source.rows
  }
  property color paint: baseline.paint
  property real editedOpacity: baseline.opacity
  property int count: baseline.count
  property string text: baseline.text
  property bool editedEnabled: baseline.enabled
  property var rows: baseline.rows
  NSettingsEditSession { id: session }
  function values() {return {paint:paint,opacity:editedOpacity,count:count,text:text,enabled:editedEnabled,rows:rows};}
  function check(ok,message) {if(!ok)throw new Error("I4_TYPED_BASELINE_ASSERT: "+message);}
  Component.onCompleted: Qt.callLater(function () {
    try {
      check(!baseline.differs(values()),"coerced null/fraction initial state is clean");
      check(String(paint)==="#000000"&&editedOpacity===0&&count===1,"actual Qt conversion preserved");
      paint="#abcdef";check(baseline.differs(values()),"native color edit dirty");paint=baseline.paint;check(!baseline.differs(values()),"native invalid-color revert clean");
      editedOpacity=.75;check(baseline.differs(values()),"real edit dirty");editedOpacity=baseline.opacity;check(!baseline.differs(values()),"real revert clean");
      count=2;check(baseline.differs(values()),"int edit dirty");count=baseline.count;check(!baseline.differs(values()),"fraction-to-int revert clean");
      text="typed";check(baseline.differs(values()),"string edit dirty");text=baseline.text;editedEnabled=!baseline.enabled;check(baseline.differs(values()),"bool edit dirty");editedEnabled=baseline.enabled;
      rows=[{address:"127.0.0.1",name:"one"}];check(!baseline.differs(values()),"record key order is not dirty");
      rows=[{address:"127.0.0.2",name:"one"}];check(baseline.differs(values()),"nested record value edit dirty");rows=baseline.rows;check(!baseline.differs(values()),"collection revert clean");
      var rejected=false;try{baseline.differs({undeclared:true});}catch(error){rejected=true;}check(rejected,"undeclared display field refuses");
      session.value={second:2,first:1};session.begin(null,{first:1,second:2});check(!session.dirty,"shared edit session ignores record key order");
      session.value={first:1,second:3};check(session.dirty,"shared edit session observes changed value");
      console.log("I4_TYPED_BASELINE: PASS");Qt.exit(0);
    }catch(error){console.error(String(error));Qt.exit(2);}
  })
  Timer {interval:5000;running:true;onTriggered:Qt.exit(2)}
}
