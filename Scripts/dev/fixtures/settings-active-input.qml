// Inert native-input witness; the VM driver sends actual ydotool/uinput events.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Widgets

ShellRoot {
  id: root
  property string textStored: "base"
  property string buttonStored: "base2"
  property real sliderStored: 50
  property string choiceStored: "one"
  property string editableStored: "first"
  property string areaStored: "area"
  property int accepted: 0
  property int closed: 0
  property int oldFence: 0
  property bool ready: false

  function check(ok, message) {
    if (!ok)
      throw new Error("I4_ACTIVE_INPUT_ASSERT: " + message);
  }

  function nativeInput(item): var {
    if (typeof item.insert === "function" && typeof item.selectAll === "function")
      return item;
    var nested = item.children || [];
    for (var i = 0; i < nested.length; i++) {
      var result = nativeInput(nested[i]);
      if (result)
        return result;
    }
    return null;
  }

  function begin() {
    if (ready || !Settings.isLoaded)
      return;
    if (Quickshell.env("I4_VERIFY") === "1") {
      var rows = JSON.parse(Settings.data.idle.customCommands);
      check(rows.length === 1 && rows[0].timeout === 61, "restarted numeric consumer");
      check(rows[0].command === "z" && rows[0].resumeCommand === "x", "restarted text consumers");
      check(rows[0].slider === 51 && rows[0].choice === "two", "restarted selection consumers");
      check(rows[0].editable === "v" && rows[0].area === "c", "restarted native combo/area consumers");
      console.log("I4_ACTIVE_INPUT: RESTART_PASS");
      Qt.exit(0);
      return;
    }
    session.begin(Settings.createEditor("idle.customCommands"), session.value);
    check(!inputs.dirty && !session.dirty, "constructor has no input intent");
    ready = true;
  }

  NSettingsEditSession {
    id: session
    inputGuard: inputs
    value: JSON.stringify([{name: "guard", timeout: spin.value, command: root.textStored,
      resumeCommand: root.buttonStored, slider: root.sliderStored, choice: root.choiceStored,
      editable: root.editableStored, area: root.areaStored}])
    onAccepted: value => { root.accepted++; }
    onCloseRequested: root.closed++
  }

  NSettingsInputGuard {
    id: inputs
    target: form
    active: root.ready && !session.busy
  }

  PanelWindow {
    id: window
    implicitWidth: 900
    implicitHeight: 760
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    FocusScope {
      id: form
      anchors.fill: parent
      ColumnLayout {
        anchors.fill: parent
        NSpinBox {
          id: spin
          label: "Numeric buffer"
          from: 30
          to: 90
          value: 60
        }
        NTextInput {
          id: textInput
          text: "base"
          onEditingFinished: root.textStored = text
        }
        NTextInputButton {
          id: buttonInput
          text: "base2"
          buttonIcon: "folder"
          onInputEditingFinished: root.buttonStored = text
        }
        NValueSlider {
          id: slider
          from: 0
          to: 100
          stepSize: 1
          value: 50
          text: String(root.sliderStored)
          onPressedChanged: function (pressed, value) {
            if (!pressed)
              root.sliderStored = value;
          }
        }
        NComboBox {
          id: choice
          currentKey: root.choiceStored
          model: [{key: "one", name: "One"}, {key: "two", name: "Two"}]
          onSelected: key => root.choiceStored = key
        }
        ComboBox {
          id: editable
          editable: true
          model: ["first", "second"]
          onEditTextChanged: root.editableStored = editText
        }
        TextArea {
          id: area
          text: "area"
          onActiveFocusChanged: {
            if (!activeFocus)
              root.areaStored = text;
          }
        }
      }
    }
  }

  IpcHandler {
    target: "active"
    function focus(kind: string): void {
      var input;
      if (kind === "spin") input = root.nativeInput(spin);
      else if (kind === "text") input = textInput.inputItem;
      else if (kind === "button") input = root.nativeInput(buttonInput);
      else if (kind === "slider") input = root.nativeSlider(slider);
      else if (kind === "choice") input = choice.comboBox;
      else if (kind === "editable") input = editable.contentItem;
      else if (kind === "area") input = area;
      root.check(input !== null && input !== undefined, "native input exists: " + kind);
      input.forceActiveFocus();
    }
    function holdFence(): void { root.oldFence = inputs.capture(); }
    function clearInputGuard(): void { inputs.reset(); }
    function acknowledgeOld(): void { inputs.acknowledge(root.oldFence); }
    function requestClose(): void { session.requestClose(); }
    function keepEditing(): void { session.discardPending = false; }
    function commit(): void { inputs.commit(); }
    function apply(): void { session.apply(); }
    function snapshot(): string {
      return JSON.stringify({ready: root.ready, dirty: inputs.dirty, sessionDirty: session.dirty,
        spin: spin.value, spinPending: spin.editPending, spinText: root.nativeInput(spin).text,
        text: textInput.text, textStored: root.textStored, button: buttonInput.text,
        buttonStored: root.buttonStored, slider: root.sliderStored, choice: root.choiceStored,
        editable: root.editableStored, editableText: editable.editText,
        focusedType: String(form.Window.window.activeFocusItem), area: area.text, areaStored: root.areaStored,
        discard: session.discardPending, busy: session.busy, failed: session.failed,
        accepted: root.accepted, closed: root.closed, value: Settings.data.idle.customCommands});
    }
    function quit(): void { Qt.exit(0); }
  }

  function nativeSlider(item): var {
    if (String(item).indexOf("NSlider_QMLTYPE") === 0)
      return item;
    var nested = item.children || [];
    for (var i = 0; i < nested.length; i++) {
      var result = nativeSlider(nested[i]);
      if (result)
        return result;
    }
    return null;
  }

  Connections {
    target: Settings
    function onSettingsLoaded() { root.begin(); }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 110000
    running: true
    onTriggered: { console.error("I4_ACTIVE_INPUT_ASSERT: watchdog"); Qt.exit(2); }
  }
}
