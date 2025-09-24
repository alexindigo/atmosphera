import QtCore
import QtQuick
import QtQuick.Dialogs
import QtQuick.Controls
import qs.Services

Item {
  id: root

  // Public API Properties
  property string initialPath: ""
  property var selectedPaths: []
  property string selectedPath: ""
  property bool multipleSelection: false
  property string pickerType: "file" // "file" or "folder"
  property var nameFilters: ["All files (*)"] // e.g., ["Image files (*.png *.jpg)", "Text files (*.txt)"]
  property string title: pickerType === "folder" ? "Select Folder" : "Select File"
  property string acceptLabel: I18n.tr("placeholders.select")
  property string rejectLabel: I18n.tr("placeholders.cancel")

  // State properties
  property bool isOpen: false

  // Signals for external connections
  signal accepted(var paths)
  signal rejected
  signal pathSelected(string path)
  signal pathsSelected(var paths)
  signal beforeOpen
  signal afterClose

  // Public functions
  function open() {
    beforeOpen()

    if (PanelService.openedPanel !== null) {
      PanelService.openedPanel.isMasked = true
    }

    for (var i = 0; i < PanelService.openedPopups.length; i++) {
      PanelService.openedPopups[i].isMasked = true
    }

    isOpen = true

    // Small delay to ensure panel changes happen first
    Qt.callLater(function () {
      if (pickerType === "folder") {
        folderDialog.open()
      } else {
        fileDialog.open()
      }
    })
  }

  function close() {
    if (pickerType === "folder") {
      folderDialog.close()
    } else {
      fileDialog.close()
    }

    handleClose()
  }

  function handleClose() {
    isOpen = false

    if (PanelService.openedPanel !== null) {
      PanelService.openedPanel.isMasked = false
    }

    for (var i = 0; i < PanelService.openedPopups.length; i++) {
      PanelService.openedPopups[i].isMasked = false
    }

    afterClose()
  }

  function reset() {
    selectedPaths = []
    selectedPath = ""
  }

  // Helper function to set file extensions easily
  function setFileExtensions(extensions) {
    if (!extensions || extensions.length === 0) {
      nameFilters = ["All files (*)"]
      return
    }

    var filters = []
    for (var i = 0; i < extensions.length; i++) {
      var ext = extensions[i]
      if (typeof ext === "string") {
        // Simple extension like "png"
        filters.push(ext.toUpperCase() + " files (*." + ext + ")")
      } else if (typeof ext === "object" && ext.label && ext.extensions) {
        // Complex filter like {label: "Images", extensions: ["png", "jpg", "jpeg"]}
        var filterStr = ext.label + " ("
        for (var j = 0; j < ext.extensions.length; j++) {
          filterStr += "*." + ext.extensions[j]
          if (j < ext.extensions.length - 1)
            filterStr += " "
        }
        filterStr += ")"
        filters.push(filterStr)
      }
    }

    if (filters.length > 0) {
      filters.push("All files (*)")
      nameFilters = filters
    }
  }

  // Helper function to convert URL to local path
  function urlToPath(url) {
    var path = url.toString()
    // Remove file:// prefix (works for both Windows and Unix)
    path = path.replace(/^file:\/\/\//, "/") // Unix
    path = path.replace(/^file:\/\//, "") // Windows
    // Handle Windows drive letters
    if (Qt.platform.os === "windows") {
      path = path.replace(/^\/([A-Z]:)/, "$1")
    }
    return path
  }

  // Get default folder with proper fallback
  function getDefaultFolder() {
    if (root.initialPath) {
      return "file:///" + root.initialPath.replace(/^\//, "")
    }

    // Fallback to home directory
    try {
      return StandardPaths.writableLocation(StandardPaths.HomeLocation)
    } catch (e) {
      // Final fallback if StandardPaths fails
      return "file:///" + (Qt.platform.os === "windows" ? "C:/Users" : "/home")
    }
  }

  // FileDialog for file selection (Qt 6.x)
  FileDialog {
    id: fileDialog
    title: root.title
    currentFolder: getDefaultFolder()
    fileMode: root.multipleSelection ? FileDialog.OpenFiles : FileDialog.OpenFile
    nameFilters: root.nameFilters
    acceptLabel: root.acceptLabel
    rejectLabel: root.rejectLabel
    modality: Qt.WindowModal

    onAccepted: {
      if (fileMode === FileDialog.OpenFiles) {
        var paths = []
        for (var i = 0; i < fileDialog.selectedFiles.length; i++) {
          paths.push(urlToPath(fileDialog.selectedFiles[i]))
        }
        root.selectedPaths = paths
        root.selectedPath = paths.length > 0 ? paths[0] : ""
        root.pathsSelected(paths)
        root.accepted(paths)
      } else {
        var singlePath = urlToPath(fileDialog.selectedFile)
        root.selectedPath = singlePath
        root.selectedPaths = [singlePath]
        root.pathSelected(singlePath)
        root.accepted([singlePath])
      }
      root.handleClose()
    }

    onRejected: {
      root.rejected()
      root.handleClose()
    }
  }

  // FolderDialog for folder selection (Qt 6.x)
  FolderDialog {
    id: folderDialog
    title: root.title
    currentFolder: getDefaultFolder()
    acceptLabel: root.acceptLabel
    rejectLabel: root.rejectLabel
    modality: Qt.WindowModal

    onAccepted: {
      var folderPath = urlToPath(folderDialog.selectedFolder)
      root.selectedPath = folderPath
      root.selectedPaths = [folderPath]
      root.pathSelected(folderPath)
      root.accepted([folderPath])
      root.handleClose()
    }

    onRejected: {
      root.rejected()
      root.handleClose()
    }
  }
}
