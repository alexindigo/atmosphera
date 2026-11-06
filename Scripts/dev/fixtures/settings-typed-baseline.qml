// Native QML coercion and selected-value equality, not raw preferences.
import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import qs.Widgets

Item {
  id: root
  property var source: ({color:null, opacity:null, count:1.5, text:null, enabled:null, rows:[{name:"one",address:"127.0.0.1"}]})
  property var rangeSource: 0
  NSettingsBaseline {
    id: baseline
    readonly property color paint: root.source.color
    readonly property real opacity: root.source.opacity
    readonly property int count: root.source.count
    readonly property string text: root.source.text
    readonly property bool enabled: root.source.enabled
    readonly property var rows: root.source.rows
    readonly property int boundedCount: root.rangeSource
    ranges: [NSettingsRange { field: "boundedCount"; from: rangeControl.from; to: rangeControl.to }]
  }
  property int projectedCount: baseline.project("boundedCount")
  property int movedCount: 0
  Controls.Slider {
    id: rangeControl
    from: 60
    to: 3600
    value: root.projectedCount
    onMoved: { root.movedCount++; root.projectedCount=value; }
  }
  NValueSlider {
    id: wrappedRange
    from: 60
    to: 3600
    value: 0
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
      check(rangeSource===0&&projectedCount===60&&rangeControl.value===60&&!baseline.differs({boundedCount:projectedCount})&&movedCount===0,"native lower clamp is clean and does not change admitted input");
      rangeSource=5000;check(projectedCount===3600&&rangeControl.value===3600&&!baseline.differs({boundedCount:projectedCount})&&movedCount===0,"native upper clamp and programmatic refresh are clean");
      rangeSource=100.9;check(projectedCount===100&&rangeControl.value===100,"native integer coercion precedes range projection");
      projectedCount=200;check(baseline.differs({boundedCount:projectedCount}),"bounded edit dirty");
      rangeSource=0;check(projectedCount===200&&baseline.differs({boundedCount:projectedCount}),"newer local bounded edit retained across source publication");
      projectedCount=baseline.project("boundedCount");check(projectedCount===60&&!baseline.differs({boundedCount:projectedCount}),"bounded revert uses the same projection");
      rangeControl.from=3600;rangeControl.to=60;rangeControl.value=rangeSource;check(baseline.project("boundedCount")===rangeControl.value&&rangeControl.value===60,"reversed native bounds");
      check(wrappedRange.value===60,"wrapper exposes the native clamped value, not a second raw owner");
      wrappedRange.value=5000;check(wrappedRange.value===3600,"wrapper upper range agrees with its actual control");
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
