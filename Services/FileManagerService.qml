pragma Singleton

import QtQuick
import Quickshell

QtObject {
  id: root

  // Function to open a file manager dialog
  function open(options) {
    var component = Qt.createComponent(Qt.resolvedUrl(Quickshell.shellDir + "/Widgets/NFileManager.qml"))
    if (component.status === Component.Ready) {
      var dialog = component.createObject(options.parent || Overlay.overlay, {
                                            "title": options.title || "Select File/Folder",
                                            "initialPath": options.initialPath || Quickshell.env("HOME"),
                                            "selectFiles": options.selectFiles || false,
                                            "selectFolders": !options.selectFiles || false,
                                            "scaling": options.scaling || 1.0
                                          })
      if (dialog) {
        if (options.onSelected) {
          if (options.selectFiles) {
            dialog.fileSelected.connect(options.onSelected)
          } else {
            dialog.folderSelected.connect(options.onSelected)
          }
        }
        dialog.open()
        return dialog
      }
    } else {
      console.error("Component error:", component.errorString())
    }
    return null
  }
}
