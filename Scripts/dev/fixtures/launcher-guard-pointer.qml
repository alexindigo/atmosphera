import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Modules.FileChooser
import qs.Widgets

ShellRoot {
  id: root
  property bool deactivated: false
  property bool callerEnabled: true
  property int clicks: 0
  property string selection: "a"
  function point(item, x, y) {
    const p = item.mapToGlobal(x, y);
    return {
      x: p.x,
      y: p.y
    };
  }
  function editor(item) {
    if (item.cursorPosition !== undefined && item.validator !== undefined)
      return item;
    for (const child of item.children || []) {
      const found = editor(child);
      if (found)
        return found;
    }
    return null;
  }
  FloatingWindow {
    title: "Launcher Guard Pointer Regression"
    fullscreen: true
    Item {
      id: surface
      x: 40
      y: 40
      width: 420
      height: 600
      NInputGuard {
        target: surface
      }
      ColumnLayout {
        anchors.fill: parent
        spacing: 16
        NComboBox {
          id: combo
          Layout.fillWidth: true
          model: [
            {
              key: "a",
              name: "Alpha"
            },
            {
              key: "b",
              name: "Beta"
            },
            {
              key: "c",
              name: "Gamma"
            }
          ]
          currentKey: root.selection
          onSelected: key => root.selection = key
        }
        NSpinBox {
          id: spin
          Layout.fillWidth: true
          value: 5
          from: 0
          to: 20
        }
        ChooserButton {
          id: button
          text: "Click guarded control"
          onClicked: root.clicks++
        }
        ChooserButton {
          id: disabled
          text: "Caller enabled binding"
          enabled: root.callerEnabled
        }
        NGridView {
          id: grid
          Layout.fillWidth: true
          Layout.fillHeight: true
          model: 80
          cellWidth: 100
          cellHeight: 40
          delegate: Text {
            required property int index
            text: "Row " + index
            width: 100
            height: 40
          }
        }
      }
    }
  }
  PanelWindow {
    visible: root.deactivated
    anchors.bottom: true
    anchors.right: true
    implicitWidth: 120
    implicitHeight: 60
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "#303030"
  }
  IpcHandler {
    target: "guardPointer"
    function state(): string {
      const field = editor(spin);
      const popup = combo.comboBox.popup;
      const second = popup.visible ? popup.contentItem.itemAtIndex(1) : null;
      return JSON.stringify({
                              active: surface.Window.active,
                              surfaceEnabled: surface.enabled,
                              comboEnabled: combo.comboBox.enabled,
                              comboOpacity: combo.comboBox.opacity,
                              spinEditorEnabled: field ? field.enabled : null,
                              gridEnabled: grid.enabled,
                              buttonEnabled: button.enabled,
                              callerEnabled: disabled.enabled,
                              clicks: root.clicks,
                              spin: spin.value,
                              selection: root.selection,
                              contentY: grid.contentY,
                              popupVisible: popup.visible,
                              second: second ? point(second, second.width / 2, second.height / 2) : null,
                              button: point(button, button.width / 2, button.height / 2),
                              combo: point(combo.comboBox, combo.comboBox.width / 2, combo.comboBox.height / 2),
                              spinPlus: point(spin, spin.width - 10, spin.height / 2),
                              grid: point(grid, grid.width / 2, grid.height / 2)
                            });
    }
    function deactivate(value: bool): void {
      root.deactivated = value;
    }
    function caller(value: bool): void {
      root.callerEnabled = value;
    }
    function exitControl(): void {
      Qt.exit(0);
    }
  }
}
