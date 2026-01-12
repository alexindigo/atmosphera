import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import "Providers"
import qs.Commons
import qs.Services.Keyboard
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

// Core launcher logic and UI - shared between SmartPanel (Launcher.qml) and overlay (LauncherOverlayWindow.qml)
Rectangle {
  id: root
  color: "transparent"

  // External interface - set by parent
  property var screen: null
  property bool isOpen: false
  signal requestClose
  signal requestCloseImmediately

  function closeImmediately() {
    requestCloseImmediately();
  }

  // Expose for preview panel positioning
  readonly property var resultsView: resultsViewLoader.item

  // State
  property string searchText: ""
  property int selectedIndex: 0
  property var results: []
  property var providers: []
  property var activeProvider: null
  property bool resultsReady: false
  property var pluginProviderInstances: ({})
  property bool ignoreMouseHover: Settings.data.appLauncher.ignoreMouseInput

  readonly property var defaultProvider: appsProvider
  readonly property var currentProvider: activeProvider || defaultProvider

  readonly property int badgeSize: Math.round(Style.baseWidgetSize * 1.6 * Style.uiScaleRatio)
  readonly property int entryHeight: Math.round(badgeSize + Style.marginM * 2)

  readonly property bool providerShowsCategories: currentProvider.showsCategories === true

  readonly property var providerCategories: {
    if (currentProvider.availableCategories && currentProvider.availableCategories.length > 0) {
      return currentProvider.availableCategories;
    }
    return currentProvider.categories || [];
  }

  readonly property bool showProviderCategories: {
    if (!providerShowsCategories || providerCategories.length === 0)
      return false;
    if (currentProvider === defaultProvider)
      return Settings.data.appLauncher.showCategories;
    return true;
  }

  readonly property bool providerHasDisplayString: results.length > 0 && !!results[0].displayString

  readonly property string providerSupportedLayouts: {
    if (activeProvider && activeProvider.supportedLayouts)
      return activeProvider.supportedLayouts;
    if (results.length > 0 && results[0].provider && results[0].provider.supportedLayouts)
      return results[0].provider.supportedLayouts;
    if (defaultProvider && defaultProvider.supportedLayouts)
      return defaultProvider.supportedLayouts;
    return "both";
  }

  readonly property bool showLayoutToggle: !providerHasDisplayString && providerSupportedLayouts === "both"

  readonly property string layoutMode: {
    if (searchText === ">")
      return "list";
    if (providerSupportedLayouts === "grid")
      return "grid";
    if (providerSupportedLayouts === "list")
      return "list";
    if (providerSupportedLayouts === "single")
      return "single";
    if (providerHasDisplayString)
      return "grid";
    return Settings.data.appLauncher.viewMode === "grid" ? "grid" : "list";
  }

  readonly property bool isGridView: layoutMode === "grid"
  readonly property bool isSingleView: layoutMode === "single"

  readonly property int targetGridColumns: currentProvider && currentProvider.preferredGridColumns ? currentProvider.preferredGridColumns : 5
  readonly property int listPanelWidth: Math.round(500 * Style.uiScaleRatio)

  property int gridColumns: 5

  // Lifecycle
  onIsOpenChanged: {
    if (isOpen) {
      onOpened();
    } else {
      onClosed();
    }
  }

  function onOpened() {
    resultsReady = false;
    ignoreMouseHover = true;
    syncPluginProviders();
    Qt.callLater(() => {
                   for (let provider of providers) {
                     if (provider.onOpened)
                     provider.onOpened();
                   }
                   updateResults();
                   resultsReady = true;
                   focusSearchInput();
                 });
  }

  function onClosed() {
    searchText = "";
    for (let provider of providers) {
      if (provider.onClosed)
        provider.onClosed();
    }
  }

  onSearchTextChanged: updateResults()

  function close() {
    requestClose();
  }

  // Public API
  function setSearchText(text) {
    searchText = text;
  }

  function focusSearchInput() {
    if (searchInput.inputItem) {
      searchInput.inputItem.forceActiveFocus();
    }
  }

  // Provider registration
  function registerProvider(provider) {
    providers.push(provider);
    provider.launcher = root;
    if (provider.init)
      provider.init();
  }

  function syncPluginProviders() {
    var registeredIds = LauncherProviderRegistry.getPluginProviders();
    for (var existingId in pluginProviderInstances) {
      if (registeredIds.indexOf(existingId) === -1) {
        var idx = providers.indexOf(pluginProviderInstances[existingId]);
        if (idx >= 0)
          providers.splice(idx, 1);
        pluginProviderInstances[existingId].destroy();
        delete pluginProviderInstances[existingId];
      }
    }
    for (var i = 0; i < registeredIds.length; i++) {
      var providerId = registeredIds[i];
      if (!pluginProviderInstances[providerId]) {
        var component = LauncherProviderRegistry.getProviderComponent(providerId);
        var pluginId = providerId.substring(7);
        var pluginApi = PluginService.getPluginAPI(pluginId);
        if (component && pluginApi) {
          var instance = component.createObject(root, {
                                                  pluginApi: pluginApi
                                                });
          if (instance) {
            pluginProviderInstances[providerId] = instance;
            registerProvider(instance);
          }
        }
      }
    }
  }

  function updateResults() {
    results = [];
    var newActiveProvider = null;

    if (searchText.startsWith(">")) {
      for (let provider of providers) {
        if (provider.handleCommand && provider.handleCommand(searchText)) {
          newActiveProvider = provider;
          results = provider.getResults(searchText);
          break;
        }
      }
      if (!newActiveProvider) {
        let allCommands = [];
        for (let provider of providers) {
          if (provider.commands)
            allCommands = allCommands.concat(provider.commands());
        }
        if (searchText === ">") {
          results = allCommands;
        } else if (searchText.length > 1) {
          const query = searchText.substring(1);
          if (typeof FuzzySort !== 'undefined') {
            const fuzzyResults = FuzzySort.go(query, allCommands, {
                                                "keys": ["name"],
                                                "threshold": -1000,
                                                "limit": 50
                                              });
            results = fuzzyResults.map(result => result.obj);
          } else {
            const queryLower = query.toLowerCase();
            results = allCommands.filter(cmd => (cmd.name || "").toLowerCase().includes(queryLower));
          }
        }
      }
    } else {
      for (let provider of providers) {
        if (provider.handleSearch) {
          const providerResults = provider.getResults(searchText);
          results = results.concat(providerResults);
        }
      }
    }

    activeProvider = newActiveProvider;
    selectedIndex = 0;
  }

  // Navigation functions
  function selectNextWrapped() {
    if (results.length > 0)
      selectedIndex = (selectedIndex + 1) % results.length;
  }
  function selectPreviousWrapped() {
    if (results.length > 0)
      selectedIndex = (((selectedIndex - 1) % results.length) + results.length) % results.length;
  }
  function selectFirst() {
    selectedIndex = 0;
  }
  function selectLast() {
    selectedIndex = results.length > 0 ? results.length - 1 : 0;
  }

  function selectNextRow() {
    if (results.length > 0 && isGridView && gridColumns > 0) {
      const currentRow = Math.floor(selectedIndex / gridColumns);
      const currentCol = selectedIndex % gridColumns;
      const totalRows = Math.ceil(results.length / gridColumns);
      if (currentRow < totalRows - 1) {
        const targetIndex = (currentRow + 1) * gridColumns + currentCol;
        selectedIndex = targetIndex < results.length ? targetIndex : results.length - 1;
      } else {
        selectedIndex = Math.min(currentCol, results.length - 1);
      }
    }
  }

  function selectPreviousRow() {
    if (results.length > 0 && isGridView && gridColumns > 0) {
      const currentRow = Math.floor(selectedIndex / gridColumns);
      const currentCol = selectedIndex % gridColumns;
      if (currentRow > 0) {
        selectedIndex = (currentRow - 1) * gridColumns + currentCol;
      } else {
        const totalRows = Math.ceil(results.length / gridColumns);
        selectedIndex = Math.min((totalRows - 1) * gridColumns + currentCol, results.length - 1);
      }
    }
  }

  function selectNextColumn() {
    if (results.length > 0 && isGridView) {
      const currentRow = Math.floor(selectedIndex / gridColumns);
      const currentCol = selectedIndex % gridColumns;
      const itemsInRow = Math.min(gridColumns, results.length - currentRow * gridColumns);
      if (currentCol < itemsInRow - 1)
        selectedIndex++;
      else {
        const totalRows = Math.ceil(results.length / gridColumns);
        selectedIndex = currentRow < totalRows - 1 ? (currentRow + 1) * gridColumns : 0;
      }
    }
  }

  function selectPreviousColumn() {
    if (results.length > 0 && isGridView) {
      const currentRow = Math.floor(selectedIndex / gridColumns);
      const currentCol = selectedIndex % gridColumns;
      if (currentCol > 0)
        selectedIndex--;
      else if (currentRow > 0)
        selectedIndex = (currentRow - 1) * gridColumns + gridColumns - 1;
      else
        selectedIndex = results.length - 1;
    }
  }

  function activate() {
    if (results.length > 0 && results[selectedIndex]) {
      const item = results[selectedIndex];
      const provider = item.provider || currentProvider;
      if (Settings.data.appLauncher.autoPasteClipboard && provider && provider.supportsAutoPaste && item.autoPasteText) {
        if (item.onAutoPaste)
          item.onAutoPaste();
        close();
        Qt.callLater(() => ClipboardService.pasteText(item.autoPasteText));
        return;
      }
      if (item.onActivate)
        item.onActivate();
    }
  }

  // Keyboard handler
  function handleKeyPress(event) {
    switch (event.key) {
    case Qt.Key_Escape:
      close();
      event.accepted = true;
      break;
    case Qt.Key_Tab:
      if (showProviderCategories) {
        var cats = providerCategories;
        var idx = cats.indexOf(currentProvider.selectedCategory);
        currentProvider.selectCategory(cats[(idx + 1) % cats.length]);
      } else
        selectNextWrapped();
      event.accepted = true;
      break;
    case Qt.Key_Backtab:
      if (showProviderCategories) {
        var cats = providerCategories;
        var idx = cats.indexOf(currentProvider.selectedCategory);
        currentProvider.selectCategory(cats[((idx - 1) % cats.length + cats.length) % cats.length]);
      } else
        selectPreviousWrapped();
      event.accepted = true;
      break;
    case Qt.Key_Up:
      isGridView ? selectPreviousRow() : selectPreviousWrapped();
      event.accepted = true;
      break;
    case Qt.Key_Down:
      isGridView ? selectNextRow() : selectNextWrapped();
      event.accepted = true;
      break;
    case Qt.Key_Left:
      isGridView ? selectPreviousColumn() : selectPreviousWrapped();
      event.accepted = true;
      break;
    case Qt.Key_Right:
      isGridView ? selectNextColumn() : selectNextWrapped();
      event.accepted = true;
      break;
    case Qt.Key_Return:
    case Qt.Key_Enter:
      activate();
      event.accepted = true;
      break;
    case Qt.Key_Home:
      selectFirst();
      event.accepted = true;
      break;
    case Qt.Key_End:
      selectLast();
      event.accepted = true;
      break;
    case Qt.Key_Delete:
      if (selectedIndex >= 0 && results && results[selectedIndex]) {
        var item = results[selectedIndex];
        var provider = item.provider || currentProvider;
        if (provider && provider.canDeleteItem && provider.canDeleteItem(item))
          provider.deleteItem(item);
      }
      event.accepted = true;
      break;
    }
  }

  // Providers
  ApplicationsProvider {
    id: appsProvider
    launcher: root
    Component.onCompleted: registerProvider(this)
  }

  ClipboardProvider {
    id: clipProvider
    launcher: root
    Component.onCompleted: if (Settings.data.appLauncher.enableClipboardHistory)
                             registerProvider(this)
  }

  CommandProvider {
    id: cmdProvider
    launcher: root
    Component.onCompleted: registerProvider(this)
  }

  EmojiProvider {
    id: emojiProvider
    launcher: root
    Component.onCompleted: registerProvider(this)
  }

  CalculatorProvider {
    id: calcProvider
    launcher: root
    Component.onCompleted: registerProvider(this)
  }

  // ==================== UI Content ====================

  opacity: resultsReady ? 1.0 : 0.0

  Behavior on opacity {
    NumberAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCirc
    }
  }

  MouseArea {
    id: mouseMovementDetector
    anchors.fill: parent
    z: -999
    hoverEnabled: true
    propagateComposedEvents: true
    acceptedButtons: Qt.NoButton
    enabled: !Settings.data.appLauncher.ignoreMouseInput

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
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginM

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NTextInput {
        id: searchInput
        Layout.fillWidth: true
        text: root.searchText
        placeholderText: I18n.tr("placeholders.search-launcher")
        fontSize: Style.fontSizeM
        onTextChanged: root.searchText = text

        Component.onCompleted: {
          if (searchInput.inputItem) {
            searchInput.inputItem.forceActiveFocus();
            searchInput.inputItem.Keys.onPressed.connect(function (event) {
              root.handleKeyPress(event);
            });
          }
        }
      }

      NIconButton {
        visible: root.showLayoutToggle
        icon: Settings.data.appLauncher.viewMode === "grid" ? "layout-list" : "layout-grid"
        tooltipText: Settings.data.appLauncher.viewMode === "grid" ? I18n.tr("tooltips.list-view") : I18n.tr("tooltips.grid-view")
        Layout.preferredWidth: searchInput.height
        Layout.preferredHeight: searchInput.height
        onClicked: Settings.data.appLauncher.viewMode = Settings.data.appLauncher.viewMode === "grid" ? "list" : "grid"
      }
    }

    // Category tabs
    NTabBar {
      id: categoryTabs
      visible: root.showProviderCategories
      Layout.fillWidth: true
      margins: Style.marginM
      border.color: Style.boxBorderColor
      border.width: Style.borderS

      property int computedCurrentIndex: visible && root.providerCategories.length > 0 ? root.providerCategories.indexOf(root.currentProvider.selectedCategory) : 0
      currentIndex: computedCurrentIndex

      Repeater {
        model: root.providerCategories
        NIconTabButton {
          required property string modelData
          required property int index
          icon: root.currentProvider.categoryIcons ? (root.currentProvider.categoryIcons[modelData] || "star") : "star"
          tooltipText: root.currentProvider.getCategoryName ? root.currentProvider.getCategoryName(modelData) : modelData
          tabIndex: index
          checked: categoryTabs.currentIndex === index
          onClicked: root.currentProvider.selectCategory(modelData)
        }
      }
    }

    // Results view
    Loader {
      id: resultsViewLoader
      Layout.fillWidth: true
      Layout.fillHeight: true
      sourceComponent: root.isSingleView ? singleViewComponent : (root.isGridView ? gridViewComponent : listViewComponent)
    }

    NDivider {
      Layout.fillWidth: true
    }

    NText {
      Layout.fillWidth: true
      text: {
        if (root.results.length === 0) {
          if (root.searchText)
            return I18n.tr("common.no-results");
          if (root.currentProvider && root.currentProvider.emptyBrowsingMessage)
            return root.currentProvider.emptyBrowsingMessage;
          return "";
        }
        var prefix = root.activeProvider && root.activeProvider.name ? root.activeProvider.name + ": " : "";
        return prefix + root.results.length + " result" + (root.results.length !== 1 ? 's' : '');
      }
      pointSize: Style.fontSizeXS
      color: Color.mOnSurfaceVariant
      horizontalAlignment: Text.AlignCenter
    }
  }

  // List view component
  Component {
    id: listViewComponent
    NListView {
      id: resultsList
      horizontalPolicy: ScrollBar.AlwaysOff
      verticalPolicy: ScrollBar.AlwaysOff
      spacing: Style.marginXS
      model: root.results
      currentIndex: root.selectedIndex
      cacheBuffer: height * 2
      interactive: !Settings.data.appLauncher.ignoreMouseInput

      onCurrentIndexChanged: {
        cancelFlick();
        if (currentIndex >= 0)
          positionViewAtIndex(currentIndex, ListView.Contain);
      }

      delegate: NBox {
        id: entry
        property bool isSelected: (!root.ignoreMouseHover && mouseArea.containsMouse) || (index === root.selectedIndex)

        Component.onCompleted: {
          var provider = modelData.provider;
          if (provider && provider.prepareItem)
            provider.prepareItem(modelData);
        }

        width: resultsList.width
        implicitHeight: root.entryHeight
        clip: true
        color: entry.isSelected ? Color.mHover : Color.mSurface

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
            easing.type: Easing.OutCirc
          }
        }

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          Item {
            visible: !modelData.hideIcon
            Layout.preferredWidth: modelData.hideIcon ? 0 : root.badgeSize
            Layout.preferredHeight: modelData.hideIcon ? 0 : root.badgeSize

            Rectangle {
              anchors.fill: parent
              radius: Style.radiusM
              color: Color.mSurfaceVariant
              visible: Settings.data.appLauncher.showIconBackground && !modelData.isImage
            }

            NImageRounded {
              id: imagePreview
              anchors.fill: parent
              visible: modelData.isImage && !modelData.displayString
              radius: Style.radiusXS
              borderColor: Color.mOnSurface
              borderWidth: Style.borderM
              imageFillMode: Image.PreserveAspectCrop

              readonly property int _rev: modelData.provider && modelData.provider.imageRevision ? modelData.provider.imageRevision : 0

              imagePath: {
                _rev;
                var provider = modelData.provider;
                if (provider && provider.getImageUrl)
                  return provider.getImageUrl(modelData);
                return "";
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
              visible: (!modelData.isImage && !modelData.displayString) || (modelData.isImage && imagePreview.status === Image.Error)
              active: visible
              sourceComponent: Settings.data.appLauncher.iconMode === "tabler" && modelData.isTablerIcon ? tablerIconComp : systemIconComp

              Component {
                id: tablerIconComp
                NIcon {
                  icon: modelData.icon
                  pointSize: Style.fontSizeXXXL
                  visible: modelData.icon && !modelData.displayString
                }
              }
              Component {
                id: systemIconComp
                IconImage {
                  anchors.fill: parent
                  source: modelData.icon ? ThemeIcons.iconFromName(modelData.icon, "application-x-executable") : ""
                  visible: modelData.icon && source !== "" && !modelData.displayString
                  asynchronous: true
                }
              }
            }

            NText {
              id: stringDisplay
              anchors.centerIn: parent
              visible: modelData.displayString || (!imagePreview.visible && !iconLoader.visible)
              text: modelData.displayString ? modelData.displayString : (modelData.name ? modelData.name.charAt(0).toUpperCase() : "?")
              pointSize: modelData.displayString ? (modelData.displayStringSize || Style.fontSizeXXXL) : Style.fontSizeXXL
              font.weight: Style.fontWeightBold
              color: modelData.displayString ? Color.mOnSurface : Color.mOnPrimary
            }

            Rectangle {
              visible: modelData.isImage && imagePreview.visible
              anchors.bottom: parent.bottom
              anchors.right: parent.right
              anchors.margins: 2
              width: formatLabel.width + Style.marginXXS * 2
              height: formatLabel.height + Style.marginXXS
              color: Color.mSurfaceVariant
              radius: Style.radiusXXS
              NText {
                id: formatLabel
                anchors.centerIn: parent
                text: {
                  if (!modelData.isImage)
                    return "";
                  const parts = (modelData.description || "").split(" • ");
                  return parts[0] || "IMG";
                }
                pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            NText {
              text: modelData.name || "Unknown"
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: entry.isSelected ? Color.mOnHover : Color.mOnSurface
              elide: Text.ElideRight
              maximumLineCount: 1
              wrapMode: Text.Wrap
              clip: true
              Layout.fillWidth: true
            }

            NText {
              text: modelData.description || ""
              pointSize: Style.fontSizeS
              color: entry.isSelected ? Color.mOnHover : Color.mOnSurfaceVariant
              elide: Text.ElideRight
              maximumLineCount: 1
              Layout.fillWidth: true
              visible: text !== ""
            }
          }

          RowLayout {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            spacing: Style.marginXS
            visible: entry.isSelected && itemActions.length > 0

            property var itemActions: {
              if (!entry.isSelected)
                return [];
              var provider = modelData.provider || root.currentProvider;
              if (provider && provider.getItemActions)
                return provider.getItemActions(modelData);
              return [];
            }

            Repeater {
              model: parent.itemActions
              NIconButton {
                icon: modelData.icon
                tooltipText: modelData.tooltip
                z: 1
                onClicked: if (modelData.action)
                             modelData.action()
              }
            }
          }
        }

        MouseArea {
          id: mouseArea
          anchors.fill: parent
          z: -1
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          enabled: !Settings.data.appLauncher.ignoreMouseInput
          onEntered: if (!root.ignoreMouseHover)
                       root.selectedIndex = index
          onClicked: mouse => {
                       if (mouse.button === Qt.LeftButton) {
                         root.selectedIndex = index;
                         root.activate();
                         mouse.accepted = true;
                       }
                     }
        }
      }
    }
  }

  // Grid view component
  Component {
    id: gridViewComponent
    NGridView {
      id: resultsGrid
      horizontalPolicy: ScrollBar.AlwaysOff
      verticalPolicy: ScrollBar.AlwaysOff
      cellWidth: width / root.targetGridColumns
      cellHeight: {
        var cw = width / root.targetGridColumns;
        if (root.currentProvider && root.currentProvider.preferredGridCellRatio)
          return cw * root.currentProvider.preferredGridCellRatio;
        return cw;
      }
      model: root.results
      cacheBuffer: height * 2
      keyNavigationEnabled: false
      focus: false
      interactive: !Settings.data.appLauncher.ignoreMouseInput

      Component.onCompleted: root.gridColumns = root.targetGridColumns
      onWidthChanged: root.gridColumns = root.targetGridColumns

      Connections {
        target: root
        enabled: root.isGridView
        function onSelectedIndexChanged() {
          if (root.isGridView && root.selectedIndex >= 0) {
            Qt.callLater(() => {
                           if (resultsGrid && resultsGrid.cancelFlick) {
                             resultsGrid.cancelFlick();
                             resultsGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
                           }
                         });
          }
        }
      }

      delegate: Item {
        id: gridEntryContainer
        width: resultsGrid.cellWidth
        height: resultsGrid.cellHeight
        property bool isSelected: (!root.ignoreMouseHover && gridMouseArea.containsMouse) || (index === root.selectedIndex)

        Component.onCompleted: {
          var provider = modelData.provider;
          if (provider && provider.prepareItem)
            provider.prepareItem(modelData);
        }

        NBox {
          id: gridEntry
          anchors.fill: parent
          anchors.margins: Style.marginXXS
          color: gridEntryContainer.isSelected ? Color.mHover : Color.mSurface

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Easing.OutCirc
            }
          }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginS
            anchors.bottomMargin: Style.marginS
            spacing: Style.marginXXS

            Item {
              Layout.preferredWidth: Math.round(gridEntry.width * 0.65)
              Layout.preferredHeight: Math.round(gridEntry.width * 0.65)
              Layout.alignment: Qt.AlignHCenter

              Rectangle {
                anchors.fill: parent
                radius: Style.radiusM
                color: Color.mSurfaceVariant
                visible: Settings.data.appLauncher.showIconBackground && !modelData.isImage
              }

              NImageRounded {
                id: gridImagePreview
                anchors.fill: parent
                visible: modelData.isImage && !modelData.displayString
                radius: Style.radiusM
                readonly property int _rev: modelData.provider && modelData.provider.imageRevision ? modelData.provider.imageRevision : 0
                imagePath: {
                  _rev;
                  var provider = modelData.provider;
                  if (provider && provider.getImageUrl)
                    return provider.getImageUrl(modelData);
                  return "";
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
                visible: (!modelData.isImage && !modelData.displayString) || (modelData.isImage && gridImagePreview.status === Image.Error)
                active: visible
                sourceComponent: Settings.data.appLauncher.iconMode === "tabler" && modelData.isTablerIcon ? gridTablerIconComp : gridSystemIconComp

                Component {
                  id: gridTablerIconComp
                  NIcon {
                    icon: modelData.icon
                    pointSize: Style.fontSizeXXXL
                    visible: modelData.icon && !modelData.displayString
                  }
                }
                Component {
                  id: gridSystemIconComp
                  IconImage {
                    anchors.fill: parent
                    source: modelData.icon ? ThemeIcons.iconFromName(modelData.icon, "application-x-executable") : ""
                    visible: modelData.icon && source !== "" && !modelData.displayString
                    asynchronous: true
                  }
                }
              }

              NText {
                id: gridStringDisplay
                anchors.centerIn: parent
                visible: modelData.displayString || (!gridImagePreview.visible && !gridIconLoader.visible)
                text: modelData.displayString ? modelData.displayString : (modelData.name ? modelData.name.charAt(0).toUpperCase() : "?")
                pointSize: {
                  if (modelData.displayString) {
                    if (modelData.displayStringSize)
                      return modelData.displayStringSize * Style.uiScaleRatio;
                    if (root.providerHasDisplayString) {
                      const cellBasedSize = gridEntry.width * 0.4;
                      const maxSize = Style.fontSizeXXXL * Style.uiScaleRatio;
                      return Math.min(cellBasedSize, maxSize);
                    }
                    return Style.fontSizeXXL * 2 * Style.uiScaleRatio;
                  }
                  const cellBasedSize = gridEntry.width * 0.25;
                  const baseSize = Style.fontSizeXL * Style.uiScaleRatio;
                  const maxSize = Style.fontSizeXXL * Style.uiScaleRatio;
                  return Math.min(Math.max(cellBasedSize, baseSize), maxSize);
                }
                font.weight: Style.fontWeightBold
                color: modelData.displayString ? Color.mOnSurface : Color.mOnPrimary
              }
            }

            NText {
              visible: !modelData.hideLabel
              text: modelData.name || "Unknown"
              pointSize: {
                if (root.providerHasDisplayString && modelData.displayString)
                  return Style.fontSizeS * Style.uiScaleRatio;
                const cellBasedSize = gridEntry.width * 0.12;
                const baseSize = Style.fontSizeS * Style.uiScaleRatio;
                const maxSize = Style.fontSizeM * Style.uiScaleRatio;
                return Math.min(Math.max(cellBasedSize, baseSize), maxSize);
              }
              font.weight: Style.fontWeightSemiBold
              color: gridEntryContainer.isSelected ? Color.mOnHover : Color.mOnSurface
              elide: Text.ElideRight
              Layout.fillWidth: true
              Layout.maximumWidth: gridEntry.width - 8
              Layout.leftMargin: (root.providerHasDisplayString && modelData.displayString) ? Style.marginS : 0
              Layout.rightMargin: (root.providerHasDisplayString && modelData.displayString) ? Style.marginS : 0
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.NoWrap
              maximumLineCount: 1
            }
          }

          Row {
            visible: gridEntryContainer.isSelected && gridItemActions.length > 0
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.marginXS
            z: 10
            spacing: Style.marginXXS

            property var gridItemActions: {
              if (!gridEntryContainer.isSelected)
                return [];
              var provider = modelData.provider || root.currentProvider;
              if (provider && provider.getItemActions)
                return provider.getItemActions(modelData);
              return [];
            }

            Repeater {
              model: parent.gridItemActions
              NIconButton {
                icon: modelData.icon
                tooltipText: modelData.tooltip
                z: 11
                onClicked: if (modelData.action)
                             modelData.action()
              }
            }
          }
        }

        MouseArea {
          id: gridMouseArea
          anchors.fill: parent
          z: -1
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          enabled: !Settings.data.appLauncher.ignoreMouseInput
          onEntered: {
            root.ignoreMouseHover = false;
            root.selectedIndex = index;
          }
          onClicked: mouse => {
                       if (mouse.button === Qt.LeftButton) {
                         root.selectedIndex = index;
                         root.activate();
                         mouse.accepted = true;
                       }
                     }
        }
      }
    }
  }

  // Single view component
  Component {
    id: singleViewComponent
    Item {
      NBox {
        anchors.fill: parent
        color: Color.mSurfaceVariant

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginL

          Item {
            Layout.alignment: Qt.AlignTop | Qt.AlignLeft
            NText {
              text: root.results.length > 0 ? root.results[0].name : ""
              pointSize: Style.fontSizeL
              font.weight: Font.Bold
              color: Color.mPrimary
            }
          }

          ScrollView {
            Layout.alignment: Qt.AlignTop | Qt.AlignLeft
            Layout.topMargin: Style.fontSizeL + Style.marginXL
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            contentWidth: availableWidth

            NText {
              width: parent.width
              text: root.results.length > 0 ? root.results[0].description : ""
              pointSize: Style.fontSizeM
              font.weight: Font.Bold
              color: Color.mOnSurface
              horizontalAlignment: Text.AlignHLeft
              verticalAlignment: Text.AlignTop
              wrapMode: Text.Wrap
              markdownTextEnabled: true
            }
          }
        }
      }
    }
  }
}
