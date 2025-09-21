import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets
import "../Helpers/FuzzySort.js" as FuzzySort

Popup {
  id: root

  // Public properties
  property string title: "File Manager"
  property string initialPath: Quickshell.env("HOME") || "/home"
  property bool selectFiles: true
  property bool selectFolders: true
  property var nameFilters: ["*"] // Default to show all files
  property bool showDirs: true
  property real scaling: 1.0

  // Selected files/folders
  property var selectedPaths: []
  property string currentPath: initialPath
  property bool shouldResetSelection: false

  // Signals
  signal fileSelected(string path)
  signal filesSelected(var paths)
  signal folderSelected(string path)
  signal cancelled

  // Override the open function to ensure proper initialization
  function openFileManager() {
    // Ensure we have a valid path
    if (!root.currentPath || root.currentPath === "") {
      root.currentPath = root.initialPath
    }
    // Signal that selection should be reset
    shouldResetSelection = true
    open()
  }

  // Helper functions
  function getFileIcon(fileName) {
    var extension = fileName.split('.').pop().toLowerCase()
    switch (extension) {
    case 'txt':
    case 'md':
    case 'log':
      return 'file-text'
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'bmp':
    case 'svg':
      return 'photo'
    case 'mp4':
    case 'avi':
    case 'mkv':
    case 'mov':
      return 'video'
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'ogg':
      return 'music'
    case 'zip':
    case 'tar':
    case 'gz':
    case 'rar':
    case '7z':
      return 'archive'
    case 'pdf':
      return 'file-text'
    case 'doc':
    case 'docx':
      return 'file-text'
    case 'xls':
    case 'xlsx':
      return 'table'
    case 'ppt':
    case 'pptx':
      return 'presentation'
    case 'html':
    case 'htm':
    case 'css':
    case 'js':
    case 'json':
    case 'xml':
      return 'code'
    case 'exe':
    case 'app':
    case 'deb':
    case 'rpm':
      return 'settings'
    default:
      return 'file'
    }
  }

  function formatFileSize(bytes) {
    if (bytes === 0)
      return "0 B"
    var k = 1024
    var sizes = ["B", "KB", "MB", "GB", "TB"]
    var i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i]
  }

  function confirmSelection() {
    if (fileManagerPanel.currentSelection.length === 0) {
      return
    }

    root.selectedPaths = fileManagerPanel.currentSelection

    if (fileManagerPanel.currentSelection.length === 1) {
      var path = fileManagerPanel.currentSelection[0]
      if (root.selectFiles && !root.selectFolders) {
        root.fileSelected(path)
      } else if (root.selectFolders && !root.selectFiles) {
        root.folderSelected(path)
      } else {
        // Both files and folders allowed
        var isDir = folderModel.get(folderModel.indexOf(path), "fileIsDir")
        if (isDir) {
          root.folderSelected(path)
        } else {
          root.fileSelected(path)
        }
      }
    } else {
      root.filesSelected(fileManagerPanel.currentSelection)
    }

    root.close()
  }

  // Function to update the filtered model
  function updateFilteredModel() {
    filteredModel.clear()
    var searchText = fileManagerPanel.filterText.toLowerCase()

    for (var i = 0; i < folderModel.count; i++) {
      var fileName = folderModel.get(i, "fileName")
      var filePath = folderModel.get(i, "filePath")
      var fileIsDir = folderModel.get(i, "fileIsDir")
      var fileSize = folderModel.get(i, "fileSize")

      // In folder selection mode, only show directories
      if (root.selectFolders && !root.selectFiles && !fileIsDir) {
        continue
      }

      // If no search text or file name contains search text
      if (searchText === "" || fileName.toLowerCase().includes(searchText)) {
        filteredModel.append({
                               "fileName": fileName,
                               "filePath": filePath,
                               "fileIsDir": fileIsDir,
                               "fileSize": fileSize
                             })
      }
    }
  }

  // Function to intelligently truncate filenames
  function truncateFileName(fileName, maxLength) {
    if (fileName.length <= maxLength) {
      return fileName
    }

    // For files, try to preserve the extension
    var lastDot = fileName.lastIndexOf('.')
    if (lastDot > 0 && lastDot < fileName.length - 1) {
      var name = fileName.substring(0, lastDot)
      var ext = fileName.substring(lastDot)
      var availableForName = maxLength - ext.length - 3 // 3 for "..."

      if (availableForName > 0) {
        return name.substring(0, availableForName) + "..." + ext
      }
    }

    // Fallback: just truncate from the end
    return fileName.substring(0, maxLength - 3) + "..."
  }

  // Popup properties
  width: 900 * scaling
  height: 700 * scaling
  modal: true
  closePolicy: Popup.CloseOnEscape
  anchors.centerIn: Overlay.overlay

  background: Rectangle {
    color: Color.mSurfaceVariant
    radius: Style.radiusL * scaling
    border.color: Color.mOutline
    border.width: Math.max(1, Style.borderS * scaling)
  }

  Rectangle {
    id: fileManagerPanel
    anchors.fill: parent
    anchors.margins: Style.marginL * scaling
    color: Color.transparent

    property string filterText: ""
    property var currentSelection: []
    property bool isNavigating: false
    property bool viewMode: true // true = grid, false = list
    property string searchText: ""
    property bool isSearching: false
    property bool showSearchBar: false

    // Keyboard shortcuts
    Keys.onPressed: event => {
                      if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_F) {
                        fileManagerPanel.showSearchBar = !fileManagerPanel.showSearchBar
                        if (fileManagerPanel.showSearchBar) {
                          // Focus the search input when opening
                          Qt.callLater(() => {
                                         searchInput.forceActiveFocus()
                                       })
                        }
                        event.accepted = true
                      } else if (event.key === Qt.Key_Escape && fileManagerPanel.showSearchBar) {
                        // Close search bar on Escape
                        fileManagerPanel.showSearchBar = false
                        fileManagerPanel.searchText = ""
                        fileManagerPanel.isSearching = false
                        fileManagerPanel.filterText = ""
                        root.updateFilteredModel()
                        event.accepted = true
                      }
                    }

    // Focus the file manager to receive key events
    focus: true

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.marginM * scaling

      // Header row (like SettingsPanel)
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * scaling

        // Main icon
        NIcon {
          icon: "folder"
          color: Color.mPrimary
          font.pointSize: Style.fontSizeXXL * scaling
        }

        // Main title
        NText {
          text: root.title
          font.pointSize: Style.fontSizeXL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mPrimary
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
        }

        // Action buttons
        NIconButton {
          icon: "refresh"
          tooltipText: "Refresh"
          Layout.alignment: Qt.AlignVCenter
          onClicked: {
            folderModel.refresh()
          }
        }

        NIconButton {
          icon: "close"
          tooltipText: "Close"
          Layout.alignment: Qt.AlignVCenter
          onClicked: {
            root.cancelled()
            root.close()
          }
        }
      }

      // Divider
      NDivider {
        Layout.fillWidth: true
      }

      // Navigation toolbar
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 45 * scaling
        color: Color.mSurfaceVariant
        radius: Style.radiusS * scaling
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS * scaling)

        RowLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Style.marginS * scaling
          spacing: Style.marginS * scaling

          // Navigation buttons
          NIconButton {
            icon: "arrow-left"
            tooltipText: "Back"
            baseSize: Style.baseWidgetSize * 0.8
            enabled: folderModel.folder.toString() !== "file://" + root.initialPath
            onClicked: {
              var parentPath = folderModel.parentFolder.toString().replace("file://", "")
              if (parentPath !== folderModel.folder.toString().replace("file://", "")) {
                folderModel.folder = "file://" + parentPath
                root.currentPath = parentPath
              }
            }
          }

          NIconButton {
            icon: "arrow-up"
            tooltipText: "Up"
            baseSize: Style.baseWidgetSize * 0.8
            enabled: folderModel.folder.toString() !== "file:///"
            onClicked: {
              var parentPath = folderModel.parentFolder.toString().replace("file://", "")
              folderModel.folder = "file://" + parentPath
              root.currentPath = parentPath
            }
          }

          NIconButton {
            icon: "home"
            tooltipText: "Home"
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              var homePath = Quickshell.env("HOME") || "/home"
              folderModel.folder = "file://" + homePath
              root.currentPath = homePath
            }
          }

          // View mode toggle
          NIconButton {
            icon: fileManagerPanel.viewMode ? "layout-grid" : "list"
            tooltipText: fileManagerPanel.viewMode ? "List View" : "Grid View"
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              fileManagerPanel.viewMode = !fileManagerPanel.viewMode
            }
          }

          // Search toggle
          NIconButton {
            icon: fileManagerPanel.showSearchBar ? "x" : "search"
            tooltipText: fileManagerPanel.showSearchBar ? "Close Search" : "Search"
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              fileManagerPanel.showSearchBar = !fileManagerPanel.showSearchBar
              if (!fileManagerPanel.showSearchBar) {
                // Clear search when closing
                fileManagerPanel.searchText = ""
                fileManagerPanel.isSearching = false
                fileManagerPanel.filterText = ""
                root.updateFilteredModel()
              }
            }
          }

          // Location input
          NTextInput {
            id: locationInput
            text: root.currentPath
            placeholderText: "Enter path..."
            Layout.fillWidth: true

            onEditingFinished: {
              var newPath = text.trim()
              if (newPath !== "" && newPath !== root.currentPath) {
                // Navigate to the path
                folderModel.folder = "file://" + newPath
                root.currentPath = newPath
              } else {
                // Reset to current path if invalid or same
                text = root.currentPath
              }
            }

            // Update text when currentPath changes from navigation (but not when user is typing)
            Connections {
              target: root
              function onCurrentPathChanged() {
                if (!locationInput.activeFocus) {
                  locationInput.text = root.currentPath
                }
              }
            }
          }
        }
      }

      // Search bar (appears when search is toggled)
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 45 * scaling
        color: Color.mSurfaceVariant
        radius: Style.radiusS * scaling
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS * scaling)
        visible: fileManagerPanel.showSearchBar

        RowLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Style.marginS * scaling
          spacing: Style.marginS * scaling

          NIcon {
            icon: "search"
            color: Color.mOnSurfaceVariant
            font.pointSize: Style.fontSizeS * scaling
          }

          NTextInput {
            id: searchInput
            placeholderText: "Search files and folders..."
            Layout.fillWidth: true
            text: fileManagerPanel.searchText

            onTextChanged: {
              fileManagerPanel.searchText = text
              fileManagerPanel.isSearching = text.length > 0
              fileManagerPanel.filterText = text
              root.updateFilteredModel()
            }

            Keys.onEscapePressed: {
              fileManagerPanel.showSearchBar = false
              fileManagerPanel.searchText = ""
              fileManagerPanel.isSearching = false
              fileManagerPanel.filterText = ""
              root.updateFilteredModel()
            }
          }

          NIconButton {
            icon: "x"
            tooltipText: "Clear"
            baseSize: Style.baseWidgetSize * 0.6
            visible: fileManagerPanel.searchText.length > 0
            onClicked: {
              searchInput.text = ""
              fileManagerPanel.searchText = ""
              fileManagerPanel.isSearching = false
              fileManagerPanel.filterText = ""
              root.updateFilteredModel()
            }
          }
        }
      }

      // File list area
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurface
        radius: Style.radiusM * scaling
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS * scaling)
        clip: true

        FolderListModel {
          id: folderModel
          folder: "file://" + root.currentPath
          nameFilters: root.nameFilters
          showDirs: root.showDirs
          showHidden: true
          sortField: FolderListModel.Name
          sortReversed: false

          onFolderChanged: {
            root.currentPath = folder.toString().replace("file://", "")
            fileManagerPanel.currentSelection = []
          }

          onStatusChanged: {
            if (status === FolderListModel.Error) {
              console.log("FolderListModel error for path:", root.currentPath)
              // Fallback to home directory if there's an error
              if (root.currentPath !== Quickshell.env("HOME")) {
                folder = "file://" + Quickshell.env("HOME")
                root.currentPath = Quickshell.env("HOME")
              }
            } else if (status === FolderListModel.Ready) {
              root.updateFilteredModel()
            }
          }
        }

        // Filtered model for search functionality
        ListModel {
          id: filteredModel
        }

        // Grid view
        GridView {
          id: gridView
          anchors.fill: parent
          anchors.margins: Style.marginM * scaling
          model: filteredModel
          visible: fileManagerPanel.viewMode
          clip: true

          property int columns: Math.max(1, Math.floor(width / (120 * scaling)))
          property int itemSize: Math.floor((width - leftMargin - rightMargin - (columns * Style.marginS * scaling)) / columns)

          cellWidth: Math.floor((width - leftMargin - rightMargin) / columns)
          cellHeight: Math.floor(itemSize * 0.8) + Style.marginXS * scaling + Style.fontSizeS * scaling + Style.marginM * scaling

          leftMargin: Style.marginS * scaling
          rightMargin: Style.marginS * scaling
          topMargin: Style.marginS * scaling
          bottomMargin: Style.marginS * scaling

          ScrollBar.vertical: ScrollBar {
            parent: gridView
            x: gridView.mirrored ? 0 : gridView.width - width
            y: 0
            height: gridView.height
            policy: ScrollBar.AsNeeded

            contentItem: Rectangle {
              implicitWidth: 6 * scaling
              implicitHeight: 100
              radius: Style.radiusM * scaling
              color: parent.pressed ? Qt.alpha(Color.mTertiary, 0.8) : parent.hovered ? Qt.alpha(Color.mTertiary, 0.8) : Qt.alpha(Color.mTertiary, 0.8)
              opacity: parent.policy === ScrollBar.AlwaysOn || parent.active ? 1.0 : 0.0

              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
            }

            background: Rectangle {
              implicitWidth: 6 * scaling
              implicitHeight: 100
              color: Color.transparent
              opacity: parent.policy === ScrollBar.AlwaysOn || parent.active ? 0.3 : 0.0
              radius: (Style.radiusM * scaling) / 2

              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }
            }
          }

          delegate: Rectangle {
            id: gridItem
            width: gridView.itemSize
            height: gridView.cellHeight
            color: Color.transparent
            radius: Style.radiusM * scaling

            property string fileName: model.fileName
            property string filePath: model.filePath
            property bool isDirectory: model.fileIsDir
            property bool isSelected: fileManagerPanel.currentSelection.includes(filePath)

            // Selection background (covers entire item)
            Rectangle {
              anchors.fill: parent
              color: isSelected ? Qt.alpha(Color.mSecondary, 0.15) : Color.transparent
              radius: parent.radius
              border.color: isSelected ? Color.mSecondary : Color.mSurface
              border.width: Math.max(1, Style.borderL * 1.5 * scaling)

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
            }

            // Hover overlay
            Rectangle {
              anchors.fill: parent
              color: Color.mSurface
              opacity: (mouseArea.containsMouse && !isSelected) ? 0.1 : 0
              radius: parent.radius
              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }
            }

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.marginS * scaling
              spacing: Style.marginXS * scaling

              Rectangle {
                id: iconContainer
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(gridView.itemSize * 0.67)
                color: Color.transparent

                // Check if file is an image
                property bool isImage: {
                  if (isDirectory)
                    return false
                  var ext = fileName.split('.').pop().toLowerCase()
                  return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico'].includes(ext)
                }

                // Show thumbnail for images, icon for others
                Image {
                  id: thumbnail
                  anchors.fill: parent
                  anchors.margins: Style.marginXS * scaling
                  source: iconContainer.isImage ? "file://" + filePath : ""
                  fillMode: Image.PreserveAspectFit
                  visible: iconContainer.isImage && status === Image.Ready
                  smooth: false // Disable smooth for faster rendering
                  cache: true
                  asynchronous: true // Load images asynchronously
                  sourceSize.width: 120 * scaling // Limit image size for faster loading
                  sourceSize.height: 120 * scaling

                  // Fallback to icon if image fails to load or takes too long
                  onStatusChanged: {
                    if (status === Image.Error) {
                      visible = false
                    }
                  }

                  // Show loading indicator while image loads
                  Rectangle {
                    anchors.fill: parent
                    color: Color.mSurfaceVariant
                    radius: Style.radiusS * scaling
                    visible: thumbnail.status === Image.Loading

                    NIcon {
                      icon: "photo"
                      font.pointSize: Style.fontSizeL * scaling
                      color: Color.mOnSurfaceVariant
                      anchors.centerIn: parent
                    }
                  }
                }

                NIcon {
                  icon: isDirectory ? "folder" : root.getFileIcon(fileName)
                  font.pointSize: Style.fontSizeXXL * scaling
                  color: isDirectory ? Color.mPrimary : Color.mOnSurfaceVariant
                  anchors.centerIn: parent
                  visible: !iconContainer.isImage || thumbnail.status !== Image.Ready
                }

                // Selection indicator (like WallpaperSelector)
                Rectangle {
                  anchors.top: parent.top
                  anchors.right: parent.right
                  anchors.margins: Style.marginS * scaling
                  width: 24 * scaling
                  height: 24 * scaling
                  radius: width / 2
                  color: Color.mSecondary
                  border.color: Color.mOutline
                  border.width: Math.max(1, Style.borderS * scaling)
                  visible: isSelected

                  NIcon {
                    icon: "check"
                    font.pointSize: Style.fontSizeS * scaling
                    font.weight: Style.fontWeightBold
                    color: Color.mOnSecondary
                    anchors.centerIn: parent
                  }
                }
              }

              NText {
                text: fileName
                color: isSelected ? Color.mPrimary : Color.mOnSurface
                font.pointSize: Style.fontSizeS * scaling
                font.weight: isSelected ? Style.fontWeightBold : Style.fontWeightRegular
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
              }
            }

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton

              onClicked: mouse => {
                           if (mouse.button === Qt.LeftButton) {
                             if (isDirectory) {
                               if (root.selectFolders && !root.selectFiles) {
                                 fileManagerPanel.currentSelection = [filePath]
                               } else {
                                 folderModel.folder = "file://" + filePath
                                 root.currentPath = filePath
                               }
                             } else {
                               if (root.selectFiles) {
                                 fileManagerPanel.currentSelection = [filePath]
                               }
                             }
                           }
                         }

              onDoubleClicked: mouse => {
                                 if (mouse.button === Qt.LeftButton) {
                                   if (isDirectory) {
                                     if (root.selectFolders && !root.selectFiles) {
                                       fileManagerPanel.currentSelection = [filePath]
                                       root.confirmSelection()
                                     } else {
                                       folderModel.folder = "file://" + filePath
                                       root.currentPath = filePath
                                     }
                                   } else {
                                     if (root.selectFiles) {
                                       fileManagerPanel.currentSelection = [filePath]
                                       root.confirmSelection()
                                     }
                                   }
                                 }
                               }
            }
          }
        }

        // List view
        ListView {
          id: listView
          anchors.fill: parent
          anchors.margins: Style.marginS * scaling
          model: filteredModel
          visible: !fileManagerPanel.viewMode
          clip: true

          ScrollBar.vertical: ScrollBar {
            parent: listView
            x: listView.mirrored ? 0 : listView.width - width
            y: 0
            height: listView.height
            policy: ScrollBar.AsNeeded

            contentItem: Rectangle {
              implicitWidth: 6 * scaling
              implicitHeight: 100
              radius: Style.radiusM * scaling
              color: parent.pressed ? Qt.alpha(Color.mTertiary, 0.8) : parent.hovered ? Qt.alpha(Color.mTertiary, 0.8) : Qt.alpha(Color.mTertiary, 0.8)
              opacity: parent.policy === ScrollBar.AlwaysOn || parent.active ? 1.0 : 0.0

              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
            }

            background: Rectangle {
              implicitWidth: 6 * scaling
              implicitHeight: 100
              color: Color.transparent
              opacity: parent.policy === ScrollBar.AlwaysOn || parent.active ? 0.3 : 0.0
              radius: (Style.radiusM * scaling) / 2

              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }
            }
          }

          delegate: Rectangle {
            id: listItem
            width: listView.width
            height: 40 * scaling
            color: {
              if (fileManagerPanel.currentSelection.includes(filePath)) {
                return Color.mSecondary
              }
              if (mouseArea.containsMouse) {
                return Qt.alpha(Color.mOnSurface, 0.1)
              }
              return Color.transparent
            }
            radius: Style.radiusS * scaling

            property string fileName: model.fileName
            property string filePath: model.filePath
            property bool isDirectory: model.fileIsDir

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.marginM * scaling
              anchors.rightMargin: Style.marginM * scaling
              spacing: Style.marginM * scaling

              NIcon {
                icon: isDirectory ? "folder" : root.getFileIcon(fileName)
                font.pointSize: Style.fontSizeL * scaling
                color: isDirectory ? (fileManagerPanel.currentSelection.includes(filePath) ? Color.mOnSecondary : Color.mPrimary) : Color.mOnSurfaceVariant
              }

              NText {
                text: fileName
                color: fileManagerPanel.currentSelection.includes(filePath) ? Color.mOnSecondary : Color.mOnSurface
                font.pointSize: Style.fontSizeM * scaling
                font.weight: fileManagerPanel.currentSelection.includes(filePath) ? Style.fontWeightBold : Style.fontWeightRegular
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              NText {
                text: isDirectory ? "" : root.formatFileSize(model.fileSize)
                color: fileManagerPanel.currentSelection.includes(filePath) ? Color.mOnSecondary : Color.mOnSurfaceVariant
                font.pointSize: Style.fontSizeS * scaling
                visible: !isDirectory
                Layout.preferredWidth: implicitWidth
              }
            }

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton

              onClicked: mouse => {
                           if (mouse.button === Qt.LeftButton) {
                             if (isDirectory) {
                               if (root.selectFolders && !root.selectFiles) {
                                 fileManagerPanel.currentSelection = [filePath]
                               } else {
                                 folderModel.folder = "file://" + filePath
                                 root.currentPath = filePath
                               }
                             } else {
                               if (root.selectFiles) {
                                 fileManagerPanel.currentSelection = [filePath]
                               }
                             }
                           }
                         }

              onDoubleClicked: mouse => {
                                 if (mouse.button === Qt.LeftButton) {
                                   if (isDirectory) {
                                     if (root.selectFolders && !root.selectFiles) {
                                       fileManagerPanel.currentSelection = [filePath]
                                       root.confirmSelection()
                                     } else {
                                       folderModel.folder = "file://" + filePath
                                       root.currentPath = filePath
                                     }
                                   } else {
                                     if (root.selectFiles) {
                                       fileManagerPanel.currentSelection = [filePath]
                                       root.confirmSelection()
                                     }
                                   }
                                 }
                               }
            }
          }
        }
      }

      // Status and actions
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * scaling

        // Status text
        NText {
          text: {
            if (fileManagerPanel.isSearching) {
              return "Searching for: \"" + fileManagerPanel.searchText + "\" (" + filteredModel.count + " matches)"
            } else if (fileManagerPanel.currentSelection.length > 0) {
              return fileManagerPanel.currentSelection.length + " item(s) selected"
            } else {
              return filteredModel.count + " items"
            }
          }
          color: fileManagerPanel.isSearching ? Color.mPrimary : Color.mOnSurfaceVariant
          font.pointSize: Style.fontSizeS * scaling
          Layout.fillWidth: true
        }

        // Action buttons
        NButton {
          text: "Cancel"
          outlined: true
          onClicked: {
            root.cancelled()
            root.close()
          }
        }

        NButton {
          text: {
            if (root.selectFolders && !root.selectFiles) {
              return "Select Folder"
            } else if (root.selectFiles && !root.selectFolders) {
              return "Select File"
            } else {
              return "Select"
            }
          }
          icon: "check"
          enabled: fileManagerPanel.currentSelection.length > 0
          onClicked: root.confirmSelection()
        }
      }
    }

    // Watch for selection reset flag
    Connections {
      target: root
      function onShouldResetSelectionChanged() {
        if (root.shouldResetSelection) {
          fileManagerPanel.currentSelection = []
          root.shouldResetSelection = false
        }
      }
    }

    Component.onCompleted: {
      // Ensure we have a valid path
      if (!root.currentPath || root.currentPath === "") {
        root.currentPath = root.initialPath
      }
      folderModel.folder = "file://" + root.currentPath
    }
  }
}
