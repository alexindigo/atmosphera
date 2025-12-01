import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../Helpers/FuzzySort.js" as Fuzzysort

import "Plugins"
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Keyboard
import qs.Widgets

SmartPanel {
  id: root

  readonly property bool previewActive: !!(searchText && searchText.startsWith(">clip") && Settings.data.appLauncher.enableClipPreview && ClipboardService.items && ClipboardService.items.length > 0 && selectedIndex >= 0 && results && results[selectedIndex] && results[selectedIndex].clipboardId)

  // Panel configuration
  readonly property int listPanelWidth: Math.round(500 * Style.uiScaleRatio)
  readonly property int previewPanelWidth: Math.round(400 * Style.uiScaleRatio)
  readonly property int totalBaseWidth: listPanelWidth + (Style.marginL * 2)

  preferredWidth: totalBaseWidth
  preferredHeight: Math.round(600 * Style.uiScaleRatio)
  preferredWidthRatio: 0.3
  preferredHeightRatio: 0.5

  // Positioning
  readonly property string panelPosition: {
    if (Settings.data.appLauncher.position === "follow_bar") {
      if (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") {
        return `center_${Settings.data.bar.position}`;
      } else {
        return `${Settings.data.bar.position}_center`;
      }
    } else {
      return Settings.data.appLauncher.position;
    }
  }
  panelAnchorHorizontalCenter: panelPosition === "center" || panelPosition.endsWith("_center")
  panelAnchorVerticalCenter: panelPosition === "center"
  panelAnchorLeft: panelPosition !== "center" && panelPosition.endsWith("_left")
  panelAnchorRight: panelPosition !== "center" && panelPosition.endsWith("_right")
  panelAnchorBottom: panelPosition.startsWith("bottom_")
  panelAnchorTop: panelPosition.startsWith("top_")

  // Core state
  property string searchText: ""
  property int selectedIndex: 0
  property var results: []
  property var plugins: []
  property var activePlugin: null
  property bool resultsReady: false
  property bool ignoreMouseHover: false

  readonly property int badgeSize: Math.round(Style.baseWidgetSize * 1.6)
  readonly property int entryHeight: Math.round(badgeSize + Style.marginM * 2)
  readonly property bool isGridView: {
    // Always use list view for clipboard and calculator to better display content
    if (searchText.startsWith(">clip") || searchText.startsWith(">calc")) {
      return false;
    }
    if (activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
      return true;
    }
    return Settings.data.appLauncher.viewMode === "grid";
  }

  // Target columns, but actual columns may vary based on available width
  // Account for NTabBar margins (Style.marginXS on each side) to match category tabs width
  readonly property int targetGridColumns: 5
  readonly property int gridContentWidth: listPanelWidth - (2 * Style.marginXS)
  readonly property int gridCellSize: Math.floor((gridContentWidth - ((targetGridColumns - 1) * Style.marginS)) / targetGridColumns)

  // Actual columns that fit in the GridView
  // This gets updated dynamically by the GridView when its actual width is known
  property int gridColumns: 5

  // Override keyboard handlers from SmartPanel for navigation.
  // Launcher specific: onTabPressed() and onBackTabPressed() are special here.
  // They are not coming from SmartPanelWindow as they are consumed by the search field before reaching the panel.
  // They are instead being forwared from the search field NTextInput below.
  function onTabPressed() {
    // In emoji browsing mode, Tab navigates between categories
    if (activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
      var currentIndex = emojiPlugin.categories.indexOf(emojiPlugin.selectedCategory);
      var nextIndex = (currentIndex + 1) % emojiPlugin.categories.length;
      emojiPlugin.selectCategory(emojiPlugin.categories[nextIndex]);
    } else if ((activePlugin === null || activePlugin === appsPlugin) && appsPlugin.isBrowsingMode) {
      // In apps browsing mode (no search), Tab navigates between categories
      var availableCategories = appsPlugin.availableCategories || ["all"];
      var currentIndex = availableCategories.indexOf(appsPlugin.selectedCategory);
      var nextIndex = (currentIndex + 1) % availableCategories.length;
      appsPlugin.selectCategory(availableCategories[nextIndex]);
    } else {
      selectNextWrapped();
    }
  }

  function onBackTabPressed() {
    selectPreviousWrapped();
  }

  function onUpPressed() {
    if (isGridView) {
      // Force update to prevent GridView interference
      Qt.callLater(() => {
                     selectPreviousRow();
                   });
    } else {
      selectPreviousWrapped();
    }
  }

  function onDownPressed() {
    if (isGridView) {
      // Force update to prevent GridView interference
      Qt.callLater(() => {
                     selectNextRow();
                   });
    } else {
      selectNextWrapped();
    }
  }

  function onLeftPressed() {
    if (isGridView) {
      selectPreviousColumn();
    } else {
      // In list view, left = previous item
      selectPreviousWrapped();
    }
  }

  function onRightPressed() {
    if (isGridView) {
      selectNextColumn();
    } else {
      // In list view, right = next item
      selectNextWrapped();
    }
  }

  function onReturnPressed() {
    activate();
  }

  function onHomePressed() {
    selectFirst();
  }

  function onEndPressed() {
    selectLast();
  }

  function onPageUpPressed() {
    selectPreviousPage();
  }

  function onPageDownPressed() {
    selectNextPage();
  }

  function onCtrlJPressed() {
    selectNextWrapped();
  }

  function onCtrlKPressed() {
    selectPreviousWrapped();
  }

  function onCtrlNPressed() {
    selectNextWrapped();
  }

  function onCtrlPPressed() {
    selectPreviousWrapped();
  }

  // Public API for plugins
  function setSearchText(text) {
    searchText = text;
  }

  // Plugin registration
  function registerPlugin(plugin) {
    plugins.push(plugin);
    plugin.launcher = root;
    if (plugin.init)
      plugin.init();
  }

  // Search handling
  function updateResults() {
    results = [];
    activePlugin = null;

    // Check for command mode
    if (searchText.startsWith(">")) {
      // Find plugin that handles this command
      for (let plugin of plugins) {
        if (plugin.handleCommand && plugin.handleCommand(searchText)) {
          activePlugin = plugin;
          results = plugin.getResults(searchText);
          break;
        }
      }

      // Show available commands if just ">" or filter commands if partial match
      if (!activePlugin) {
        // Collect all commands from all plugins
        let allCommands = [];
        for (let plugin of plugins) {
          if (plugin.commands) {
            allCommands = allCommands.concat(plugin.commands());
          }
        }

        if (searchText === ">") {
          // Show all commands when just ">"
          results = allCommands;
        } else if (searchText.length > 1) {
          // Filter commands using fuzzy search when typing partial command
          const query = searchText.substring(1); // Remove the ">" prefix

          if (typeof Fuzzysort !== 'undefined') {
            // Use fuzzy search to filter commands
            const fuzzyResults = Fuzzysort.go(query, allCommands, {
                                                "keys": ["name"],
                                                "threshold": -1000,
                                                "limit": 50
                                              });

            // Convert fuzzy results back to command objects
            results = fuzzyResults.map(result => result.obj);
          } else {
            // Fallback to simple substring matching
            const queryLower = query.toLowerCase();
            results = allCommands.filter(cmd => {
                                           const cmdName = (cmd.name || "").toLowerCase();
                                           return cmdName.includes(queryLower);
                                         });
          }
        }
      }
    } else {
      // Regular search - let plugins contribute results
      for (let plugin of plugins) {
        if (plugin.handleSearch) {
          const pluginResults = plugin.getResults(searchText);
          results = results.concat(pluginResults);
        }
      }
    }

    selectedIndex = 0;
  }

  onSearchTextChanged: updateResults()

  // Lifecycle
  onOpened: {
    resultsReady = false;
    ignoreMouseHover = true;

    // Notify plugins and update results
    // Use Qt.callLater to ensure plugins are registered (Component.onCompleted runs first)
    Qt.callLater(() => {
                   for (let plugin of plugins) {
                     if (plugin.onOpened)
                     plugin.onOpened();
                   }
                   updateResults();
                   resultsReady = true;
                 });
  }

  onClosed: {
    // Reset search text
    searchText = "";
    ignoreMouseHover = true;

    // Notify plugins
    for (let plugin of plugins) {
      if (plugin.onClosed)
        plugin.onClosed();
    }
  }

  // Plugin components - declared inline so imports work correctly
  ApplicationsPlugin {
    id: appsPlugin
    Component.onCompleted: {
      registerPlugin(this);
      Logger.d("Launcher", "Registered: ApplicationsPlugin");
    }
  }

  CalculatorPlugin {
    id: calcPlugin
    Component.onCompleted: {
      registerPlugin(this);
      Logger.d("Launcher", "Registered: CalculatorPlugin");
    }
  }

  ClipboardPlugin {
    id: clipPlugin
    Component.onCompleted: {
      if (Settings.data.appLauncher.enableClipboardHistory) {
        registerPlugin(this);
        Logger.d("Launcher", "Registered: ClipboardPlugin");
      }
    }
  }

  EmojiPlugin {
    id: emojiPlugin
    Component.onCompleted: {
      registerPlugin(this);
      Logger.d("Launcher", "Registered: EmojiPlugin");
    }
  }

  // Navigation functions
  function selectNextWrapped() {
    if (results.length > 0) {
      selectedIndex = (selectedIndex + 1) % results.length;
    }
  }

  function selectPreviousWrapped() {
    if (results.length > 0) {
      selectedIndex = (((selectedIndex - 1) % results.length) + results.length) % results.length;
    }
  }

  function selectFirst() {
    selectedIndex = 0;
  }

  function selectLast() {
    if (results.length > 0) {
      selectedIndex = results.length - 1;
    } else {
      selectedIndex = 0;
    }
  }

  function selectNextPage() {
    if (results.length > 0) {
      const page = Math.max(1, Math.floor(600 / entryHeight)); // Use approximate height
      selectedIndex = Math.min(selectedIndex + page, results.length - 1);
    }
  }

  function selectPreviousPage() {
    if (results.length > 0) {
      const page = Math.max(1, Math.floor(600 / entryHeight)); // Use approximate height
      selectedIndex = Math.max(selectedIndex - page, 0);
    }
  }

  // Grid view navigation functions
  function selectPreviousRow() {
    if (results.length > 0 && isGridView) {
      const currentRow = Math.floor(selectedIndex / gridColumns);
      const currentCol = selectedIndex % gridColumns;

      if (currentRow > 0) {
        // Move to previous row, same column
        const targetRow = currentRow - 1;
        const targetIndex = targetRow * gridColumns + currentCol;
        // Check if target column exists in target row
        const itemsInTargetRow = Math.min(gridColumns, results.length - targetRow * gridColumns);
        if (currentCol < itemsInTargetRow) {
          selectedIndex = targetIndex;
        } else {
          // Target column doesn't exist, go to last item in target row
          selectedIndex = targetRow * gridColumns + itemsInTargetRow - 1;
        }
      } else {
        // Wrap to last row, same column
        const totalRows = Math.ceil(results.length / gridColumns);
        const lastRow = totalRows - 1;
        const itemsInLastRow = Math.min(gridColumns, results.length - lastRow * gridColumns);
        if (currentCol < itemsInLastRow) {
          selectedIndex = lastRow * gridColumns + currentCol;
        } else {
          selectedIndex = results.length - 1;
        }
      }
    }
  }

  function selectNextRow() {
    if (results.length > 0 && isGridView) {
      const currentRow = Math.floor(selectedIndex / gridColumns);
      const currentCol = selectedIndex % gridColumns;
      const totalRows = Math.ceil(results.length / gridColumns);

      if (currentRow < totalRows - 1) {
        // Move to next row, same column
        const targetRow = currentRow + 1;
        const targetIndex = targetRow * gridColumns + currentCol;

        // Check if target index is valid
        if (targetIndex < results.length) {
          selectedIndex = targetIndex;
        } else {
          // Target column doesn't exist in target row, go to last item in target row
          const itemsInTargetRow = results.length - targetRow * gridColumns;
          if (itemsInTargetRow > 0) {
            selectedIndex = targetRow * gridColumns + itemsInTargetRow - 1;
          } else {
            // Target row is empty, wrap to first row
            selectedIndex = Math.min(currentCol, results.length - 1);
          }
        }
      } else {
        // Wrap to first row, same column
        selectedIndex = Math.min(currentCol, results.length - 1);
      }
    }
  }

  function selectPreviousColumn() {
    if (results.length > 0 && isGridView) {
      const currentRow = Math.floor(selectedIndex / gridColumns);
      const currentCol = selectedIndex % gridColumns;
      if (currentCol > 0) {
        // Move left in same row
        selectedIndex = currentRow * gridColumns + (currentCol - 1);
      } else {
        // Wrap to last column of previous row
        if (currentRow > 0) {
          selectedIndex = (currentRow - 1) * gridColumns + (gridColumns - 1);
        } else {
          // Wrap to last column of last row
          const totalRows = Math.ceil(results.length / gridColumns);
          const lastRowIndex = (totalRows - 1) * gridColumns + (gridColumns - 1);
          selectedIndex = Math.min(lastRowIndex, results.length - 1);
        }
      }
    }
  }

  function selectNextColumn() {
    if (results.length > 0 && isGridView) {
      const currentRow = Math.floor(selectedIndex / gridColumns);
      const currentCol = selectedIndex % gridColumns;
      const itemsInCurrentRow = Math.min(gridColumns, results.length - currentRow * gridColumns);

      if (currentCol < itemsInCurrentRow - 1) {
        // Move right in same row
        selectedIndex = currentRow * gridColumns + (currentCol + 1);
      } else {
        // Wrap to first column of next row
        const totalRows = Math.ceil(results.length / gridColumns);
        if (currentRow < totalRows - 1) {
          selectedIndex = (currentRow + 1) * gridColumns;
        } else {
          // Wrap to first item
          selectedIndex = 0;
        }
      }
    }
  }

  function activate() {
    if (results.length > 0 && results[selectedIndex]) {
      const item = results[selectedIndex];
      if (item.onActivate) {
        item.onActivate();
      }
    }
  }

  panelContent: Rectangle {
    id: ui
    color: Color.transparent
    opacity: resultsReady ? 1.0 : 0.0

    // Preview Panel (external)
    NBox {
      id: previewBox
      visible: root.previewActive
      width: root.previewPanelWidth
      height: Math.round(400 * Style.uiScaleRatio)
      x: ui.width + Style.marginM
      y: {
        if (!resultsViewLoader.item)
          return Style.marginL;
        const view = resultsViewLoader.item;
        const row = root.isGridView ? Math.floor(root.selectedIndex / root.gridColumns) : root.selectedIndex;
        const itemHeight = root.isGridView ? (root.gridCellSize + Style.marginXXS) : (root.entryHeight + view.spacing);
        const yPos = row * itemHeight - view.contentY;
        const mapped = view.mapToItem(ui, 0, yPos);
        return Math.max(Style.marginL, Math.min(mapped.y, ui.height - previewBox.height - Style.marginL));
      }
      z: -1 // Draw behind main panel content if it ever overlaps

      opacity: visible ? 1.0 : 0.0
      Behavior on opacity {
        NumberAnimation {
          duration: Style.animationFast
        }
      }

      Loader {
        id: clipboardPreviewLoader
        anchors.fill: parent
        active: root.previewActive
        source: active ? "./ClipboardPreview.qml" : ""

        onLoaded: {
          if (selectedIndex >= 0 && results[selectedIndex] && item) {
            item.currentItem = results[selectedIndex];
          }
        }

        onItemChanged: {
          if (item && selectedIndex >= 0 && results[selectedIndex]) {
            item.currentItem = results[selectedIndex];
          }
        }
      }
    }

    MouseArea {
      id: mouseMovementDetector
      anchors.fill: parent
      z: -999
      hoverEnabled: true
      propagateComposedEvents: true
      acceptedButtons: Qt.NoButton

      property real lastX: 0
      property real lastY: 0
      property bool initialized: false

      onPositionChanged: mouse => {
                           if (!initialized) {
                             lastX = mouse.x;
                             lastY = mouse.y;
                             initialized = true;
                             return;
                           }

                           const deltaX = Math.abs(mouse.x - lastX);
                           const deltaY = Math.abs(mouse.y - lastY);
                           if (deltaX > 1 || deltaY > 1) {
                             root.ignoreMouseHover = false;
                             lastX = mouse.x;
                             lastY = mouse.y;
                           }
                         }

      Connections {
        target: root
        function onOpened() {
          mouseMovementDetector.initialized = false;
        }
      }
    }

    // Focus management
    Connections {
      target: root
      function onOpened() {
        // Delay focus to ensure window has keyboard focus
        Qt.callLater(() => {
                       if (searchInput.inputItem) {
                         searchInput.inputItem.forceActiveFocus();
                       }
                     });
      }
    }

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCirc
      }
    }

    RowLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL // Apply overall margins here
      spacing: Style.marginM // Apply spacing between elements here

      // Left Pane
      ColumnLayout {
        id: leftPane
        Layout.fillHeight: true
        Layout.preferredWidth: root.listPanelWidth
        spacing: Style.marginM

        NTextInput {
          id: searchInput
          Layout.fillWidth: true

          fontSize: Style.fontSizeL
          fontWeight: Style.fontWeightSemiBold

          text: searchText
          placeholderText: I18n.tr("placeholders.search-launcher")

          onTextChanged: searchText = text

          Component.onCompleted: {
            if (searchInput.inputItem) {
              searchInput.inputItem.forceActiveFocus();
              // Intercept keys before TextField handles them
              searchInput.inputItem.Keys.onPressed.connect(function (event) {
                if (event.key === Qt.Key_Tab) {
                  root.onTabPressed();
                  event.accepted = true;
                } else if (event.key === Qt.Key_Backtab) {
                  root.onBackTabPressed();
                  event.accepted = true;
                } else if (event.key === Qt.Key_Left && root.isGridView) {
                  // In grid view, left arrow navigates the grid
                  root.onLeftPressed();
                  event.accepted = true;
                } else if (event.key === Qt.Key_Right && root.isGridView) {
                  // In grid view, right arrow navigates the grid
                  root.onRightPressed();
                  event.accepted = true;
                }
              });
            }
          }
        }

        // Emoji category tabs (shown when in browsing mode)
        NTabBar {
          id: emojiCategoryTabs
          visible: root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode && !root.searchText.startsWith(">")
          Layout.fillWidth: true
          currentIndex: {
            if (visible && emojiPlugin.categories) {
              return emojiPlugin.categories.indexOf(emojiPlugin.selectedCategory);
            }
            return 0;
          }

          Repeater {
            model: emojiPlugin.categories
            NIconTabButton {
              required property string modelData
              required property int index
              icon: emojiPlugin.categoryIcons[modelData] || "star"
              tabIndex: index
              checked: emojiCategoryTabs.currentIndex === index
              onClicked: {
                emojiPlugin.selectCategory(modelData);
              }
            }
          }
        }

        // App category tabs (shown when browsing apps without search)
        NTabBar {
          id: appCategoryTabs
          visible: (root.activePlugin === null || root.activePlugin === appsPlugin) && appsPlugin.isBrowsingMode && !root.searchText.startsWith(">")
          Layout.fillWidth: true
          currentIndex: {
            if (visible && appsPlugin.availableCategories) {
              return appsPlugin.availableCategories.indexOf(appsPlugin.selectedCategory);
            }
            return 0;
          }

          Repeater {
            model: appsPlugin.availableCategories || []
            NIconTabButton {
              required property string modelData
              required property int index
              icon: appsPlugin.categoryIcons[modelData] || "apps"
              tooltipText: appsPlugin.getCategoryName ? appsPlugin.getCategoryName(modelData) : modelData
              tabIndex: index
              checked: appCategoryTabs.currentIndex === index
              onClicked: {
                appsPlugin.selectCategory(modelData);
              }
            }
          }
        }

        Loader {
          id: resultsViewLoader
          Layout.fillWidth: true
          Layout.fillHeight: true
          sourceComponent: root.isGridView ? gridViewComponent : listViewComponent
        }

        Component {
          id: listViewComponent
          NListView {
            id: resultsList

            horizontalPolicy: ScrollBar.AlwaysOff
            verticalPolicy: ScrollBar.AsNeeded

            width: parent.width
            height: parent.height
            spacing: Style.marginXXS
            model: results
            currentIndex: selectedIndex
            cacheBuffer: resultsList.height * 2
            onCurrentIndexChanged: {
              cancelFlick();
              if (currentIndex >= 0) {
                positionViewAtIndex(currentIndex, ListView.Contain);
              }
              if (clipboardPreviewLoader.item) {
                clipboardPreviewLoader.item.currentItem = results[currentIndex] || null;
              }
            }
            onModelChanged: {}

            delegate: Rectangle {
              id: entry

              property bool isSelected: (!root.ignoreMouseHover && mouseArea.containsMouse) || (index === selectedIndex)
              property string appId: (modelData && modelData.appId) ? String(modelData.appId) : ""

              // Helper function to normalize app IDs for case-insensitive matching
              function normalizeAppId(appId) {
                if (!appId || typeof appId !== 'string')
                  return "";
                return appId.toLowerCase().trim();
              }

              // Pin helpers
              function togglePin(appId) {
                if (!appId)
                  return;
                const normalizedId = normalizeAppId(appId);
                let arr = (Settings.data.dock.pinnedApps || []).slice();
                const idx = arr.findIndex(pinnedId => normalizeAppId(pinnedId) === normalizedId);
                if (idx >= 0)
                  arr.splice(idx, 1);
                else
                  arr.push(appId);
                Settings.data.dock.pinnedApps = arr;
              }

              function isPinned(appId) {
                if (!appId)
                  return false;
                const arr = Settings.data.dock.pinnedApps || [];
                const normalizedId = normalizeAppId(appId);
                return arr.some(pinnedId => normalizeAppId(pinnedId) === normalizedId);
              }

              // Property to reliably track the current item's ID.
              // This changes whenever the delegate is recycled for a new item.
              property var currentClipboardId: modelData.isImage ? modelData.clipboardId : ""

              // When this delegate is assigned a new image item, trigger the decode.
              onCurrentClipboardIdChanged: {
                // Check if it's a valid ID and if the data isn't already cached.
                if (currentClipboardId && !ClipboardService.getImageData(currentClipboardId)) {
                  ClipboardService.decodeToDataUrl(currentClipboardId, modelData.mime, null);
                }
              }

              width: resultsList.width - Style.marginS
              implicitHeight: entryHeight
              radius: Style.radiusM
              color: entry.isSelected ? Color.mHover : Color.mSurface

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.OutCirc
                }
              }

              ColumnLayout {
                id: contentLayout
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginM

                // Top row - Main entry content with pin button
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginM

                  // Icon badge or Image preview or Emoji
                  Rectangle {
                    Layout.preferredWidth: badgeSize
                    Layout.preferredHeight: badgeSize
                    radius: Style.radiusM
                    color: Color.mSurfaceVariant

                    // Image preview for clipboard images
                    NImageRounded {
                      id: imagePreview
                      anchors.fill: parent
                      visible: modelData.isImage && !modelData.emojiChar
                      radius: Style.radiusM

                      // This property creates a dependency on the service's revision counter
                      readonly property int _rev: ClipboardService.revision

                      // Fetches from the service's cache.
                      // The dependency on `_rev` ensures this binding is re-evaluated when the cache is updated.
                      imagePath: {
                        _rev;
                        return ClipboardService.getImageData(modelData.clipboardId) || "";
                      }

                      Rectangle {
                        anchors.fill: parent
                        visible: parent.status === Image.Loading
                        color: Color.mSurfaceVariant

                        BusyIndicator {
                          anchors.centerIn: parent
                          running: true
                          width: Style.baseWidgetSize * 0.5
                          height: width
                        }
                      }

                      onStatusChanged: status => {
                                         if (status === Image.Error) {
                                           iconLoader.visible = true;
                                           imagePreview.visible = false;
                                         }
                                       }
                    }

                    Loader {
                      id: iconLoader
                      anchors.fill: parent
                      anchors.margins: Style.marginXS

                      visible: !modelData.isImage && !modelData.emojiChar || (modelData.isImage && imagePreview.status === Image.Error)
                      active: visible

                      sourceComponent: Component {
                        IconImage {
                          anchors.fill: parent
                          source: modelData.icon ? ThemeIcons.iconFromName(modelData.icon, "application-x-executable") : ""
                          visible: modelData.icon && source !== "" && !modelData.emojiChar
                          asynchronous: true
                        }
                      }
                    }

                    // Emoji display - takes precedence when emojiChar is present
                    NText {
                      id: emojiDisplay
                      anchors.centerIn: parent
                      visible: modelData.emojiChar || (!imagePreview.visible && !iconLoader.visible)
                      text: modelData.emojiChar ? modelData.emojiChar : modelData.name.charAt(0).toUpperCase()
                      pointSize: modelData.emojiChar ? Style.fontSizeXXXL : Style.fontSizeXXL  // Larger font for emojis
                      font.weight: Style.fontWeightBold
                      color: modelData.emojiChar ? Color.mOnSurface : Color.mOnPrimary  // Different color for emojis
                    }

                    // Image type indicator overlay
                    Rectangle {
                      visible: modelData.isImage && imagePreview.visible
                      anchors.bottom: parent.bottom
                      anchors.right: parent.right
                      anchors.margins: 2
                      width: formatLabel.width + 6
                      height: formatLabel.height + 2
                      radius: Style.radiusM
                      color: Color.mSurfaceVariant

                      NText {
                        id: formatLabel
                        anchors.centerIn: parent
                        text: {
                          if (!modelData.isImage)
                            return "";
                          const desc = modelData.description || "";
                          const parts = desc.split(" • ");
                          return parts[0] || "IMG";
                        }
                        pointSize: Style.fontSizeXXS
                        color: Color.mPrimary
                      }
                    }
                  }

                  // Text content
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    NText {
                      text: modelData.name || "Unknown"
                      pointSize: Style.fontSizeL
                      font.weight: Style.fontWeightBold
                      color: entry.isSelected ? Color.mOnHover : Color.mOnSurface
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    NText {
                      text: modelData.description || ""
                      pointSize: Style.fontSizeS
                      color: entry.isSelected ? Color.mOnHover : Color.mOnSurfaceVariant
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                      visible: text !== ""
                    }
                  }

                  // Pin/Unpin action icon button
                  NIconButton {
                    visible: !!entry.appId && !modelData.isImage && entry.isSelected && Settings.data.dock.enabled
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    icon: entry.isPinned(entry.appId) ? "unpin" : "pin"
                    tooltipText: entry.isPinned(entry.appId) ? I18n.tr("launcher.unpin") : I18n.tr("launcher.pin")
                    onClicked: entry.togglePin(entry.appId)
                  }
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  if (!root.ignoreMouseHover) {
                    selectedIndex = index;
                  }
                }
                onClicked: mouse => {
                             if (mouse.button === Qt.LeftButton) {
                               selectedIndex = index;
                               root.activate();
                               mouse.accepted = true;
                             }
                           }
                acceptedButtons: Qt.LeftButton
              }
            }
          }
        }

        Component {
          id: gridViewComponent
          NGridView {
            id: resultsGrid

            horizontalPolicy: ScrollBar.AlwaysOff
            verticalPolicy: ScrollBar.AsNeeded

            width: parent.width
            height: parent.height
            cellWidth: {
              if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
                return parent.width / 5;
              }
              // Use gridCellSize which already accounts for NTabBar margins
              return root.gridCellSize + Style.marginXL;
            }
            cellHeight: {
              if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
                return (parent.width / 5) * 1.2;
              }
              return gridCellSize + Style.marginXL;
            }
            leftMargin: {
              if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
                return 0;
              }
              // Match NTabBar margins (Style.marginXS on each side) to align with category tabs
              return Style.marginXS;
            }
            rightMargin: {
              if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
                return 0;
              }
              // Match NTabBar margins (Style.marginXS on each side) to align with category tabs
              return Style.marginXS;
            }
            topMargin: 0
            bottomMargin: 0
            model: results
            cacheBuffer: resultsGrid.height * 2
            keyNavigationEnabled: false
            focus: false
            interactive: true

            onWidthChanged: {
              // Update gridColumns based on actual GridView width
              // This ensures navigation works correctly regardless of panel size
              if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
                // Always 5 columns for emoji browsing mode
                root.gridColumns = 5;
              } else {
                const actualCols = Math.floor(width / cellWidth);
                if (actualCols > 0 && actualCols !== root.gridColumns) {
                  root.gridColumns = actualCols;
                }
              }
            }

            // Completely disable GridView key handling
            Keys.enabled: false

            // Don't sync selectedIndex to GridView's currentIndex
            // The visual selection is handled by the delegate based on selectedIndex
            // We only need to position the view to show the selected item

            onModelChanged: {}

            // Update gridColumns when entering/exiting emoji browsing mode
            Connections {
              target: emojiPlugin
              function onIsBrowsingModeChanged() {
                if (emojiPlugin.isBrowsingMode) {
                  root.gridColumns = 5;
                }
              }
            }

            // Handle scrolling to show selected item when it changes
            Connections {
              target: root
              enabled: root.isGridView
              function onSelectedIndexChanged() {
                // Only process if we're still in grid view and component exists
                if (!root.isGridView || root.selectedIndex < 0 || !resultsGrid) {
                  return;
                }

                Qt.callLater(() => {
                               // Double-check we're still in grid view mode
                               if (root.isGridView && resultsGrid && resultsGrid.cancelFlick) {
                                 resultsGrid.cancelFlick();
                                 resultsGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
                               }
                             });

                // Update preview
                if (clipboardPreviewLoader.item && root.selectedIndex >= 0) {
                  clipboardPreviewLoader.item.currentItem = results[root.selectedIndex] || null;
                }
              }
            }

            delegate: Rectangle {
              id: gridEntry

              property bool isSelected: (!root.ignoreMouseHover && mouseArea.containsMouse) || (index === selectedIndex)
              property string appId: (modelData && modelData.appId) ? String(modelData.appId) : ""

              // Helper function to normalize app IDs for case-insensitive matching
              function normalizeAppId(appId) {
                if (!appId || typeof appId !== 'string')
                  return "";
                return appId.toLowerCase().trim();
              }

              // Pin helpers
              function togglePin(appId) {
                if (!appId)
                  return;
                const normalizedId = normalizeAppId(appId);
                let arr = (Settings.data.dock.pinnedApps || []).slice();
                const idx = arr.findIndex(pinnedId => normalizeAppId(pinnedId) === normalizedId);
                if (idx >= 0)
                  arr.splice(idx, 1);
                else
                  arr.push(appId);
                Settings.data.dock.pinnedApps = arr;
              }

              function isPinned(appId) {
                if (!appId)
                  return false;
                const arr = Settings.data.dock.pinnedApps || [];
                const normalizedId = normalizeAppId(appId);
                return arr.some(pinnedId => normalizeAppId(pinnedId) === normalizedId);
              }

              width: {
                if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
                  return resultsGrid.width / 5;
                }
                return resultsGrid.cellWidth;
              }
              height: {
                if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
                  return (resultsGrid.width / 5) * 1.2;
                }
                return resultsGrid.cellHeight;
              }
              radius: Style.radiusM
              color: gridEntry.isSelected ? Color.mHover : Color.mSurface

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.OutCirc
                }
              }

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: {
                  if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
                    return 4;
                  }
                  return Style.marginM;
                }
                spacing: Style.marginM

                // Icon badge or Image preview or Emoji
                Rectangle {
                  Layout.preferredWidth: {
                    if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode && modelData.emojiChar) {
                      return gridEntry.width - 8;
                    }
                    return badgeSize * 1.5;
                  }
                  Layout.preferredHeight: {
                    if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode && modelData.emojiChar) {
                      return gridEntry.width - 8;
                    }
                    return badgeSize * 1.5;
                  }
                  Layout.alignment: Qt.AlignHCenter
                  radius: Style.radiusM
                  color: Color.mSurfaceVariant

                  // Image preview for clipboard images
                  NImageRounded {
                    id: gridImagePreview
                    anchors.fill: parent
                    visible: modelData.isImage && !modelData.emojiChar
                    radius: Style.radiusM

                    readonly property int _rev: ClipboardService.revision

                    imagePath: {
                      _rev;
                      return ClipboardService.getImageData(modelData.clipboardId) || "";
                    }

                    Rectangle {
                      anchors.fill: parent
                      visible: parent.status === Image.Loading
                      color: Color.mSurfaceVariant

                      BusyIndicator {
                        anchors.centerIn: parent
                        running: true
                        width: Style.baseWidgetSize * 0.5
                        height: width
                      }
                    }

                    onStatusChanged: status => {
                                       if (status === Image.Error) {
                                         gridIconLoader.visible = true;
                                         gridImagePreview.visible = false;
                                       }
                                     }
                  }

                  Loader {
                    id: gridIconLoader
                    anchors.fill: parent
                    anchors.margins: Style.marginXS

                    visible: !modelData.isImage && !modelData.emojiChar || (modelData.isImage && gridImagePreview.status === Image.Error)
                    active: visible

                    sourceComponent: Component {
                      IconImage {
                        anchors.fill: parent
                        source: modelData.icon ? ThemeIcons.iconFromName(modelData.icon, "application-x-executable") : ""
                        visible: modelData.icon && source !== "" && !modelData.emojiChar
                        asynchronous: true
                      }
                    }
                  }

                  // Emoji display
                  NText {
                    id: gridEmojiDisplay
                    anchors.centerIn: parent
                    visible: modelData.emojiChar || (!gridImagePreview.visible && !gridIconLoader.visible)
                    text: modelData.emojiChar ? modelData.emojiChar : modelData.name.charAt(0).toUpperCase()
                    pointSize: {
                      if (modelData.emojiChar) {
                        if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
                          return Math.max(Style.fontSizeL, gridEntry.width * 0.4);
                        }
                        return Style.fontSizeXXL * 2;
                      }
                      return Style.fontSizeXL;
                    }
                    font.weight: Style.fontWeightBold
                    color: modelData.emojiChar ? Color.mOnSurface : Color.mOnPrimary
                  }
                }

                // Text content
                NText {
                  text: modelData.name || "Unknown"
                  pointSize: {
                    if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode && modelData.emojiChar) {
                      return Style.fontSizeS;
                    }
                    return Style.fontSizeS;
                  }
                  font.weight: Style.fontWeightSemiBold
                  color: gridEntry.isSelected ? Color.mOnHover : Color.mOnSurface
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                  Layout.maximumWidth: gridEntry.width - 8
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.NoWrap
                  maximumLineCount: 1
                }
              }

              // Pin/Unpin action icon button (overlay in top-right corner)
              NIconButton {
                visible: !!gridEntry.appId && !modelData.isImage && gridEntry.isSelected && Settings.data.dock.enabled
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.marginXS
                z: 10
                icon: gridEntry.isPinned(gridEntry.appId) ? "unpin" : "pin"
                tooltipText: gridEntry.isPinned(gridEntry.appId) ? I18n.tr("launcher.unpin") : I18n.tr("launcher.pin")
                onClicked: gridEntry.togglePin(gridEntry.appId)
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  if (!root.ignoreMouseHover) {
                    selectedIndex = index;
                  }
                }
                onClicked: mouse => {
                             if (mouse.button === Qt.LeftButton) {
                               selectedIndex = index;
                               root.activate();
                               mouse.accepted = true;
                             }
                           }
                acceptedButtons: Qt.LeftButton
              }
            }
          }
        }

        NDivider {
          Layout.fillWidth: true
        }

        NText {
          Layout.fillWidth: true
          text: {
            if (results.length === 0) {
              if (searchText) {
                return "No results";
              } else if (activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode && emojiPlugin.selectedCategory === "recent") {
                return "No recently used emoji";
              }
              return "";
            }
            var prefix = activePlugin && activePlugin.name ? activePlugin.name + ": " : "";
            return prefix + results.length + " result" + (results.length !== 1 ? 's' : '');
          }
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
          horizontalAlignment: Text.AlignCenter
        }
      }
    }
  }
}
