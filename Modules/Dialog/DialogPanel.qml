import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI
import qs.Widgets

PanelWindow {
  id: root

  property int dialogType: -1
  property string dialogQuestion: ""
  property string dialogDefault: ""
  property bool responded: false
  property string replyPath: ""

  objectName: "dialogPanel-" + (screen?.name || "unknown")

  color: "#80000000"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "atmosphera-dialog"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  visible: false

  Component.onCompleted: {
    PanelService.registerPanel(root);
  }

  function showFor(type, question, defaultText, path) {
    dialogType = type;
    dialogQuestion = question;
    dialogDefault = defaultText || "";
    replyPath = path;
    responded = false;

    if (inputField)
      inputField.text = defaultText || "";

    if (screen) {
      width = screen.width;
      height = screen.height;
    }

    visible = true;
    Qt.callLater(function () {
      if (inputField && inputField.inputItem)
        inputField.inputItem.forceActiveFocus();
    });
  }

  function writeReply(text) {
    if (!replyPath)
      return;
    Quickshell.execDetached(["python3", "-c", "import sys; open(sys.argv[1], 'w').write(sys.argv[2])", replyPath, text]);
    replyPath = "";
  }

  onVisibleChanged: {
    if (!visible && !responded && replyPath) {
      writeReply("");
    }
  }

  Shortcut {
    sequence: "Return"
    onActivated: okBtn.clicked()
  }

  Shortcut {
    sequence: "Escape"
    onActivated: root.visible = false
  }

  // Background click = dismiss (cancel)
  MouseArea {
    anchors.fill: parent
    z: 0
    onClicked: root.visible = false
  }

  // Dialog card
  Item {
    width: 420
    height: 220
    anchors.centerIn: parent
    z: 1

    // Blocks background clicks from reaching bgDismiss
    MouseArea {
      anchors.fill: parent
    }

    Rectangle {
      anchors.fill: parent
      color: Color.mSurface
      radius: Style.radiusS
      border.color: Color.mOutline
      border.width: Style.borderS

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        Text {
          text: root.dialogQuestion
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
          color: Color.mOnSurface
          font.pointSize: Style.fontSizeL
        }

        FocusScope {
          Layout.fillWidth: true
          visible: root.dialogType === 2

          NTextInput {
            id: inputField
            anchors.fill: parent
            text: root.dialogDefault
            onAccepted: okBtn.clicked()
          }
        }

        Item {
          Layout.fillHeight: true
        }

        RowLayout {
          spacing: Style.marginM
          Layout.alignment: Qt.AlignRight

          NButton {
            text: "Cancel"
            visible: root.dialogType !== 0
            outlined: true
            onClicked: root.visible = false
          }

          NButton {
            id: okBtn
            text: "OK"
            icon: root.dialogType === 1 ? "check" : ""
            onClicked: {
              root.responded = true;
              var v = root.dialogType === 2 ? inputField.text : root.dialogType === 1 ? "true" : "";
              root.writeReply(v);
              root.visible = false;
            }
          }
        }
      }
    }
  }
}
