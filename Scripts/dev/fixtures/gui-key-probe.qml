// Non-terminal Qt key/clipboard probe (plan: post-071). Run with qml6:
//   qml6 gui-key-probe.qml
// A plain toplevel (app-id is NOT in the xremap terminal list) with a focused
// TextField. Logs received keys and text changes to stdout:
//   GUIPROBE|KEY|<key>|<modifiers>
//   GUIPROBE|TEXT|<text>
import QtQuick
import QtQuick.Controls

ApplicationWindow {
  id: win

  visible: true
  width: 420
  height: 120
  title: "guiprobe"
  color: "#202020"

  Component.onCompleted: {
    console.log("GUIPROBE|READY");
    tf.forceActiveFocus();
  }

  onActiveChanged: {
    if (active)
      tf.forceActiveFocus();
  }

  TextField {
    id: tf
    anchors.fill: parent
    anchors.margins: 12
    placeholderText: "guiprobe"
    onActiveFocusChanged: console.log("GUIPROBE|FOCUS|" + activeFocus)
    onTextChanged: console.log("GUIPROBE|TEXT|" + text)
    Keys.onPressed: event => console.log("GUIPROBE|KEY|" + event.key + "|" + event.modifiers)
  }
}
