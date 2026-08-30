import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Widgets

PanelWindow {
  id: root

  property string mode: "open"
  property var options: ({})

  signal accepted(var paths)
  signal cancelled

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  color: Qt.rgba(0, 0, 0, 0.5)

  WlrLayershell.namespace: "atmosphera-portal-filedialog"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  AtmoFilePicker {
    id: picker

    title: root.options.title !== undefined && root.options.title !== "" ? root.options.title : I18n.tr("widgets.file-picker.title")
    saveMode: root.mode !== "open"
    multiTarget: root.mode === "saveMulti"
    selectionMode: root.options.directory ? "folders" : "files"
    allowMultiSelection: root.options.multiple === true
    acceptLabel: root.options.accept_label || ""
    initialPath: root.options.current_folder || Quickshell.env("HOME") || "/home"
    currentName: root.options.current_name || root.options.current_file_name || ""
    nameFilters: root.options.filters && root.options.filters.length > 0 ? root.options.filters : ["*"]

    // open only once the parent window exists — Component.onCompleted
    // races window creation and intermittently leaves the popup
    // unmapped (dim-only dialog)
    Component.onCompleted: Qt.callLater(picker.openFilePicker)
    onAccepted: paths => root.accepted(paths)
    onCancelled: root.cancelled()
  }
}
