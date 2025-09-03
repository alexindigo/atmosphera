import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  // Panel configuration
  panelWidth: Math.min(700 * scaling, screen?.width * 0.75)
  panelHeight: Math.min(600 * scaling, screen?.height * 0.8)
  panelKeyboardFocus: true
  panelBackgroundColor: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b,
                                Settings.data.appLauncher.backgroundOpacity)

  // Positioning
  readonly property string launcherPosition: Settings.data.appLauncher.position
  panelAnchorHorizontalCenter: launcherPosition === "center" || launcherPosition.endsWith("_center")
  panelAnchorVerticalCenter: launcherPosition === "center"
  panelAnchorLeft: launcherPosition !== "center" && launcherPosition.endsWith("_left")
  panelAnchorRight: launcherPosition !== "center" && launcherPosition.endsWith("_right")
  panelAnchorBottom: launcherPosition.startsWith("bottom_")
  panelAnchorTop: launcherPosition.startsWith("top_")

  // Core state
  property string searchText: ""
  property int selectedIndex: 0
  property var results: []
  property var plugins: []
  property var activePlugin: null

  // Public API for plugins
  function setSearchText(text) {
    searchText = text
  }

  // Plugin registration
  function registerPlugin(plugin) {
    plugins.push(plugin)
    plugin.launcher = root
    if (plugin.init)
      plugin.init()
  }

  // Search handling
  function updateResults() {
    results = []
    activePlugin = null

    // Check for command mode
    if (searchText.startsWith(">")) {
      // Find plugin that handles this command
      for (let plugin of plugins) {
        if (plugin.handleCommand && plugin.handleCommand(searchText)) {
          activePlugin = plugin
          results = plugin.getResults(searchText)
          break
        }
      }

      // Show available commands if just ">"
      if (searchText === ">" && !activePlugin) {
        for (let plugin of plugins) {
          if (plugin.commands) {
            results = results.concat(plugin.commands())
          }
        }
      }
    } else {
      // Regular search - let plugins contribute results
      for (let plugin of plugins) {
        if (plugin.handleSearch) {
          const pluginResults = plugin.getResults(searchText)
          results = results.concat(pluginResults)
        }
      }
    }

    selectedIndex = 0
  }

  onSearchTextChanged: updateResults()

  // Lifecycle
  onOpened: {
    // Notify plugins
    for (let plugin of plugins) {
      if (plugin.onOpened)
        plugin.onOpened()
    }
    updateResults()
  }

  onClosed: {
    // Notify plugins
    for (let plugin of plugins) {
      if (plugin.onClosed)
        plugin.onClosed()
    }
  }

  // Navigation
  function selectNext() {
    if (results.length > 0) {
      // Clamp the index to not exceed the last item
      selectedIndex = Math.min(selectedIndex + 1, results.length - 1)
    }
  }

  function selectPrev() {
    if (results.length > 0) {
      // Clamp the index to not go below the first item (0)
      selectedIndex = Math.max(selectedIndex - 1, 0)
    }
  }

  function activate() {
    if (results.length > 0 && results[selectedIndex]) {
      const item = results[selectedIndex]
      if (item.onActivate) {
        item.onActivate()
      }
    }
  }

  // Load plugins
  Component.onCompleted: {
    // Load applications plugin
    const appsPlugin = Qt.createComponent("Plugins/ApplicationsPlugin.qml").createObject(this)
    if (appsPlugin) {
      registerPlugin(appsPlugin)
      Logger.log("Launcher", "Registered: ApplicationsPlugin")
    } else {
      Logger.error("Launcher", "Failed to load ApplicationsPlugin")
    }

    // Load calculator plugin
    const calcPlugin = Qt.createComponent("Plugins/CalculatorPlugin.qml").createObject(this)
    if (calcPlugin) {
      registerPlugin(calcPlugin)
      Logger.log("Launcher", "Registered: CalculatorPlugin")
    } else {
      Logger.error("Launcher", "Failed to load CalculatorPlugin")
    }

    // Load clipboard history plugin
    const clipboardPlugin = Qt.createComponent("Plugins/ClipboardPlugin.qml").createObject(this)
    if (clipboardPlugin) {
      registerPlugin(clipboardPlugin)
      Logger.log("Launcher", "Registered: clipboardPlugin")
    } else {
      Logger.error("Launcher", "Failed to load clipboardPlugin")
    }
  }

  // UI
  panelContent: Rectangle {
    color: Color.transparent

    Component.onCompleted: {
      searchText = ""
      selectedIndex = 0
      if (searchInput?.forceActiveFocus) {
        searchInput.forceActiveFocus()
      }
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL * scaling
      spacing: Style.marginM * scaling

      FocusScope {
        id: searchInputWrap
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(Style.barHeight * scaling)

        // This FocusScope should get focus when panel opens
        focus: true

        NTextInput {
          id: searchInput
          anchors.fill: parent

          // The input should have focus within the scope
          focus: true

          placeholderText: "Search entries... or use > for commands"
          text: searchText
          inputMaxWidth: Number.MAX_SAFE_INTEGER

          function forceActiveFocus() {
            // First ensure the scope has focus
            searchInputWrap.forceActiveFocus()
            // Then focus the actual input
            if (inputItem && inputItem.visible) {
              inputItem.forceActiveFocus()
            }
          }

          Component.onCompleted: {
            if (inputItem) {
              inputItem.font.pointSize = Style.fontSizeL * scaling
              inputItem.verticalAlignment = TextInput.AlignVCenter
            }
          }

          onTextChanged: searchText = text

          Keys.onDownPressed: root.selectNext()
          Keys.onUpPressed: root.selectPrev()
          Keys.onReturnPressed: root.activate()
          Keys.onEscapePressed: root.close()
        }
      }

      // Results list
      ListView {
        id: resultsList

        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.marginXXS * scaling

        model: results
        currentIndex: selectedIndex

        clip: true
        cacheBuffer: resultsList.height * 2
        onCurrentIndexChanged: {
          cancelFlick()
          if (currentIndex >= 0) {
            positionViewAtIndex(currentIndex, ListView.Contain)
          }
        }

        ScrollBar.vertical: ScrollBar {
          policy: ScrollBar.AsNeeded
        }

        delegate: Rectangle {
          id: entry

          property bool isSelected: mouseArea.containsMouse || (index === selectedIndex)
          property int badgeSize: Style.baseWidgetSize * 1.75 * scaling

          // Property to reliably track the current item's ID.
          // This changes whenever the delegate is recycled for a new item.
          property var currentClipboardId: modelData.isImage ? modelData.clipboardId : ""

          // When this delegate is assigned a new image item, trigger the decode.
          onCurrentClipboardIdChanged: {
            // Check if it's a valid ID and if the data isn't already cached.
            if (currentClipboardId && !ClipboardService.getImageData(currentClipboardId)) {
              ClipboardService.decodeToDataUrl(currentClipboardId, modelData.mime, null)
            }
          }

          width: resultsList.width - Style.marginS * scaling
          height: badgeSize + Style.marginM * 2 * scaling
          radius: Style.radiusM * scaling
          color: entry.isSelected ? Color.mTertiary : Color.mSurface

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Easing.OutCirc
            }
          }

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM * scaling
            spacing: Style.marginM * scaling

            // Icon badge or Image preview
            Rectangle {
              Layout.preferredWidth: badgeSize
              Layout.preferredHeight: badgeSize
              radius: Style.radiusM * scaling
              color: Color.mSurfaceVariant
              clip: true

              // Image preview for clipboard images
              Image {
                id: imagePreview
                anchors.fill: parent
                anchors.margins: 2 * scaling
                visible: modelData.isImage

                // This property creates a dependency on the service's revision counter
                readonly property int _rev: ClipboardService.revision

                // Fetches from the service's cache.
                // The dependency on `_rev` ensures this binding is re-evaluated
                // when the cache is updated by the service.
                source: {
                  _rev
                  return ClipboardService.getImageData(modelData.clipboardId) || ""
                }

                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                asynchronous: true
                cache: true

                // Loading indicator
                Rectangle {
                  anchors.fill: parent
                  visible: parent.status === Image.Loading
                  color: Color.mSurfaceVariant

                  BusyIndicator {
                    anchors.centerIn: parent
                    running: true
                    width: Style.baseWidgetSize * 0.5 * scaling
                    height: width
                  }
                }

                // Error fallback
                onStatusChanged: {
                  if (status === Image.Error) {
                    iconLoader.visible = true
                    imagePreview.visible = false
                  }
                }
              }

              // Icon fallback
              Loader {
                id: iconLoader
                anchors.fill: parent
                anchors.margins: Style.marginXS * scaling

                visible: !modelData.isImage || imagePreview.status === Image.Error
                active: visible

                sourceComponent: Component {
                  IconImage {
                    anchors.fill: parent
                    source: modelData.icon ? Icons.iconFromName(modelData.icon, "application-x-executable") : ""
                    visible: modelData.icon && source !== ""
                    asynchronous: true
                  }
                }
              }

              // Fallback text if no icon and no image
              NText {
                anchors.centerIn: parent
                visible: !imagePreview.visible && !iconLoader.visible
                text: modelData.name ? modelData.name.charAt(0).toUpperCase() : "?"
                font.pointSize: Style.fontSizeXXL * scaling
                font.weight: Style.fontWeightBold
                color: Color.mOnPrimary
              }

              // Image type indicator overlay
              Rectangle {
                visible: modelData.isImage && imagePreview.visible
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: 2 * scaling
                width: formatLabel.width + 6 * scaling
                height: formatLabel.height + 2 * scaling
                radius: 2 * scaling
                color: Qt.rgba(0, 0, 0, 0.7)

                NText {
                  id: formatLabel
                  anchors.centerIn: parent
                  text: {
                    if (!modelData.isImage)
                      return ""
                    const desc = modelData.description || ""
                    const parts = desc.split(" • ")
                    return parts[0] || "IMG"
                  }
                  font.pointSize: Style.fontSizeXXS * scaling
                  color: Color.mPrimary
                }
              }
            }

            // Text content
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0 * scaling

              NText {
                text: modelData.name || "Unknown"
                font.pointSize: Style.fontSizeL * scaling
                font.weight: Style.fontWeightBold
                color: entry.isSelected ? Color.mOnTertiary : Color.mOnSurface
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              NText {
                text: modelData.description || ""
                font.pointSize: Style.fontSizeS * scaling
                color: entry.isSelected ? Color.mOnTertiary : Color.mOnSurfaceVariant
                elide: Text.ElideRight
                Layout.fillWidth: true
                visible: text !== ""
              }
            }
          }

          MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              selectedIndex = index
              root.activate()
            }
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      // Status
      NText {
        Layout.fillWidth: true
        text: {
          if (results.length === 0)
            return searchText ? "No results" : ""
          const prefix = activePlugin?.name ? `${activePlugin.name}: ` : ""
          return prefix + `${results.length} result${results.length !== 1 ? 's' : ''}`
        }
        font.pointSize: Style.fontSizeXS * scaling
        color: Color.mOnSurfaceVariant
        horizontalAlignment: Text.AlignCenter
      }
    }
  }
}
