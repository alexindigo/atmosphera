import QtQuick
import Quickshell
import qs.Commons
import qs.Portals

Item {
  id: root

  property string title: I18n.tr("widgets.file-picker.title")
  property string initialPath: Quickshell.env("HOME") || "/home"
  property string selectionMode: "files"
  property var nameFilters: ["*"]
  property bool allowMultiSelection: false
  property var _operation: null

  signal accepted(var paths)
  signal cancelled

  function openFilePicker() {
    if (_operation)
      return;
    _operation = FileChooserClient.openPicker({
                                   title: root.title,
                                   directory: root.selectionMode === "folders",
                                   multiple: root.allowMultiSelection,
                                   filters: root.nameFilters,
                                   initialPath: root.initialPath
                                  }, paths => { root._operation = null; root.accepted(paths); }, () => { root._operation = null; root.cancelled(); });
  }

  function open() {
    root.openFilePicker();
  }

  function close() {
    if (_operation)
      _operation.cancel();
  }
  Component.onDestruction: {
    if (_operation) {
      _operation.dispose();
    }
  }
}
