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
  property var _surveyFields: []
  property var _surveyInputs: ({})
  readonly property int _maxCardHeight: screen ? Math.round(screen.height * 0.75) : 600

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
    _surveyFields = [];
    _surveyInputs = ({});

    if (type === 3) {
      try {
        _surveyFields = JSON.parse(defaultText || "[]");
      } catch (e) {}
    }

    if (inputField)
      inputField.text = defaultText || "";

    if (screen) {
      width = screen.width;
      height = screen.height;
    }

    visible = true;
    Qt.callLater(function () {
      if (dialogType === 2 && inputField && inputField.inputItem)
        inputField.inputItem.forceActiveFocus();
      else if (dialogType === 3) {
        var firstKey = Object.keys(root._surveyInputs)[0];
        if (firstKey && root._surveyInputs[firstKey] && root._surveyInputs[firstKey].inputItem)
          root._surveyInputs[firstKey].inputItem.forceActiveFocus();
      }
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
    height: root.dialogType === 3 ? Math.min(root._maxCardHeight, Math.max(220, root._surveyFields.length * 60 + 140)) : 220
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

        // Survey fields
        ScrollView {
          Layout.fillWidth: true
          Layout.fillHeight: root.dialogType === 3
          visible: root.dialogType === 3
          clip: true
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

          ColumnLayout {
            width: parent.width
            spacing: Style.marginXS

            Repeater {
              model: root._surveyFields

              delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 2

                Text {
                  text: modelData.label || ""
                  color: Color.mOnSurfaceVariant
                  font.pointSize: Style.fontSizeXS
                  font.weight: Style.fontWeightMedium
                }

                NTextInput {
                  Layout.fillWidth: true
                  text: modelData.default || ""
                  Component.onCompleted: {
                    root._surveyInputs[modelData.label] = this;
                  }
                }
              }
            }
          }
        }

        Item {
          Layout.fillHeight: root.dialogType !== 3
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
              var v = "";
              if (root.dialogType === 2) {
                v = inputField.text;
              } else if (root.dialogType === 3) {
                var pairs = [];
                for (var fi = 0; fi < root._surveyFields.length; fi++) {
                  var f = root._surveyFields[fi];
                  var inp = root._surveyInputs[f.label];
                  pairs.push(f.label);
                  var val = inp ? inp.text : "";
                  pairs.push(val === "" ? "-" : val);
                }
                v = pairs.join(" ");
              } else if (root.dialogType === 1) {
                v = "true";
              }
              root.writeReply(v);
              root.visible = false;
            }
          }
        }
      }
    }
  }
}
