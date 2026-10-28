import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "Helpers/LauncherNavigation.js" as LauncherNav
import "Helpers/LauncherResults.js" as LauncherResults
import "Helpers/LauncherSelection.js" as LauncherSelection

import "Providers"
import qs.Commons
import qs.Services.Keyboard
import qs.Services.UI
import qs.Widgets

// Core launcher logic and UI - shared between SmartPanel (Launcher.qml) and overlay (LauncherOverlayWindow.qml)
Rectangle {
  id: root
  color: "transparent"

  // External interface - set by parent
  property var screen: null
  property bool isOpen: false
  property var actionSession: null
  enabled: isOpen && visible
  signal requestClose
  signal requestCloseImmediately

  function closeImmediately() {
    LauncherActionService.finishSession(actionSession);
    requestCloseImmediately();
  }
  function pasteText(text) {
    LauncherActionService.pasteText(text, pasteContext());
    closeImmediately();
  }
  function pasteClipboard(id, mime) {
    LauncherActionService.pasteClipboard(id, mime, pasteContext());
    closeImmediately();
  }
  function pasteContext() {
    LauncherActionService.attachWindow(actionSession, root.Window.window, screen);
    return actionSession;
  }

  // Expose for preview panel positioning
  readonly property var resultsView: resultsSwapView.item

  // State
  property string searchText: ""
  property int selectedIndex: 0
  property var results: []
  property var providers: []
  // The views' model, derived from results and owned here (projectRows). Rows
  // are keyed by item identity. results stays the source for selection and
  // activation; the model only decides which delegates the views keep.
  ScriptModel {
    id: rowsA
    objectProp: "key"
  }
  ScriptModel {
    id: rowsB
    objectProp: "key"
  }
  property var resultsModel: rowsA
  // Whether a change of the selected row animates its highlight. Only the
  // user's navigation (keys, pointer) does; a refresh or an open moves the
  // highlight at once, so a retained row never fades out a stale selection.
  property bool selectionAnimated: false
  property var shownKeys: []
  function projectRows(items) {
    const rows = LauncherSelection.keyedRows(items, providers);
    const current = resultsModel;
    // A view applies an incremental change row by row and creates every row it
    // moves or inserts synchronously, its cache buffer included. A reset
    // creates only the rows it shows and incubates the rest. Apply the refresh
    // incrementally while it touches no more rows than the view shows (small
    // refreshes keep their delegates); otherwise reset the view by moving it to
    // the other keyed model.
    if (LauncherSelection.changedRows(shownKeys, rows) <= visiblePageSize) {
      current.values = rows;
    } else {
      const next = current === rowsA ? rowsB : rowsA;
      next.values = rows;
      resultsModel = next;
      current.values = [];
    }
    shownKeys = rows.map(row => row.key);
  }
  onProvidersChanged: syncProviderObservers()
  property var activeProvider: null
  property bool resultsReady: false
  property bool openReady: false
  property var pluginProviderInstances: ({})
  ListModel {
    id: providerObservers
  }
  Instantiator {
    // Incremental rows preserve existing observers during registration. A JS
    // array replacement resets the entire model on every provider append.
    model: providerObservers
    delegate: Connections {
      required property var providerObject
      target: providerObject
      // Synchronous and legacy plugin providers need not publish this signal.
      ignoreUnknownSignals: true
      function onResultsChanged() {
        root.providerDataChanged();
      }
    }
  }
  function syncProviderObservers() {
    // providers remains the registry's public source of truth. Reconcile its
    // observer projection by identity, never reset surviving Connections.
    for (let index = providerObservers.count - 1; index >= 0; index--) {
      if (providers.indexOf(providerObservers.get(index).providerObject) === -1)
        providerObservers.remove(index);
    }
    for (const provider of providers) {
      let observed = false;
      for (let index = 0; index < providerObservers.count; index++) {
        if (providerObservers.get(index).providerObject === provider) {
          observed = true;
          break;
        }
      }
      if (!observed)
        providerObservers.append({
                                   providerObject: provider
                                 });
    }
  }
  Connections {
    target: Settings
    function onEffectiveSettingsChanged() {
      root.providerDataChanged();
    }
  }
  Connections {
    target: I18n
    function onTranslationsLoaded() {
      root.providerDataChanged();
    }
  }
  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.providerDataChanged();
    }
  }
  function providerDataChanged() {
    if (isOpen && openReady)
      Qt.callLater(root.updateResults);
  }
  Component.onDestruction: {
    releaseProviderOwners();
    LauncherActionService.finishSession(actionSession);
  }
  function releaseProviderOwners() {
    openReady = false;
    for (const id in pluginProviderInstances) {
      const instance = pluginProviderInstances[id];
      if (instance && instance.launcher === root)
        instance.launcher = null;
    }
  }
  property bool ignoreMouseHover: true // Transient flag, should always be true on init

  // Global mouse tracking for movement detection across delegates
  property real globalLastMouseX: 0
  property real globalLastMouseY: 0
  property bool globalMouseInitialized: false
  property bool mouseTrackingReady: false // Delay tracking until panel is settled

  readonly property bool animationsDisabled: Settings.data.general.animationDisabled

  Timer {
    id: mouseTrackingDelayTimer
    interval: root.animationsDisabled ? 0 : (Style.animationNormal + 50) // Wait for panel animation to complete + safety margin
    repeat: false
    onTriggered: {
      root.mouseTrackingReady = true;
      root.globalMouseInitialized = false; // Reset so we get fresh initial position
    }
  }

  readonly property var defaultProvider: appsProvider
  readonly property var currentProvider: activeProvider || defaultProvider

  readonly property string launcherDensity: (currentProvider && currentProvider.ignoreDensity === false) ? (Settings.data.appLauncher.density || "default") : "comfortable"
  readonly property int effectiveIconSize: launcherDensity === "comfortable" ? 48 : (launcherDensity === "default" ? 36 : 24)
  readonly property int badgeSize: Math.round(effectiveIconSize * Style.uiScaleRatio)
  readonly property int entryHeight: Math.round(badgeSize + (launcherDensity === "compact" ? (Style.marginL + Style.marginXXS) : (Style.marginXL + Style.marginS)))

  readonly property bool providerShowsCategories: (currentProvider.showsCategories !== undefined ? currentProvider.showsCategories : true) && providerCategories.length > 0

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
    return Settings.data.appLauncher.viewMode;
  }

  readonly property bool isGridView: layoutMode === "grid"
  readonly property bool isSingleView: layoutMode === "single"
  readonly property bool isCompactDensity: launcherDensity === "compact"

  readonly property int targetGridColumns: {
    let base = 5;
    if (launcherDensity === "comfortable")
      base = 4;
    else if (launcherDensity === "compact")
      base = 6;

    if (!activeProvider || activeProvider === defaultProvider)
      return base;

    if (activeProvider.preferredGridColumns) {
      let multiplier = base / 5.0;
      return Math.max(1, Math.round(activeProvider.preferredGridColumns * multiplier));
    }

    return base;
  }
  readonly property int listPanelWidth: Math.round(500 * Style.uiScaleRatio)
  readonly property int gridContentWidth: listPanelWidth - Style.margin2XS
  readonly property int gridCellSize: Math.floor((gridContentWidth - ((targetGridColumns - 1) * Style.marginS)) / targetGridColumns)

  readonly property int gridColumns: targetGridColumns

  // Check if current provider allows wrap navigation (default true)
  readonly property bool allowWrapNavigation: {
    var provider = activeProvider || currentProvider;
    return provider && provider.wrapNavigation !== undefined ? provider.wrapNavigation : true;
  }

  // Listen for plugin provider registry changes
  Connections {
    target: LauncherProviderRegistry
    function onPluginProviderRegistryUpdated() {
      root.syncPluginProviders();
    }
  }

  // Lifecycle
  onIsOpenChanged: {
    if (isOpen) {
      onOpened();
    } else {
      onClosed();
    }
  }

  onSearchTextChanged: {
    if (isOpen) {
      // Query changes (including IME commits) take selection back from a
      // stationary pointer, independently of how native editing delivered text.
      ignoreMouseHover = true;
      globalMouseInitialized = false;
      updateResults(true);
    }
  }

  function onOpened() {
    selectionAnimated = false;
    LauncherActionService.finishSession(actionSession);
    actionSession = LauncherActionService.beginSession(screen);
    pasteContext();
    openReady = false;
    ignoreMouseHover = true;
    globalMouseInitialized = false;
    mouseTrackingReady = false;
    mouseTrackingDelayTimer.restart();

    // Show launcher immediately, results will populate asynchronously
    resultsReady = true;
    Qt.callLater(root.prepareOpenResults);
  }

  // Input is ready before result/model/delegate work. Window activation is
  // the native focus acknowledgement; a locally focused TextField alone is not.
  Connections {
    target: root.Window.window
    function onActiveChanged() {
      if (root.Window.active) {
        root.pasteContext();
        Qt.callLater(root.prepareOpenResults);
      }
    }
  }

  function prepareOpenResults() {
    if (!isOpen || openReady || !root.Window.active)
      return;
    openReady = true;
    pasteContext();
    syncPluginProviders();
    for (let provider of providers) {
      if (provider.onOpened)
        provider.onOpened();
    }
    updateResults(true);
  }

  function onClosed() {
    LauncherActionService.finishSession(actionSession);
    openReady = false;
    searchText = "";
    ignoreMouseHover = true;
    if (resultsSwapView)
      resultsSwapView.resetVisuals();
    for (let provider of providers) {
      if (provider.onClosed)
        provider.onClosed();
    }
  }

  function close() {
    LauncherActionService.finishSession(actionSession);
    requestClose();
  }

  function applyCategorySelection(tabIndex, categories) {
    const categoryList = categories || providerCategories;
    if (!categoryList || tabIndex < 0 || tabIndex >= categoryList.length)
      return false;

    currentProvider.selectCategory(categoryList[tabIndex]);
    categoryTabs.currentIndex = tabIndex;
    return true;
  }

  function selectCategoryWithSlide(tabIndex) {
    if (!showProviderCategories || !currentProvider || !currentProvider.selectCategory)
      return;

    const cats = providerCategories;
    if (!cats || tabIndex < 0 || tabIndex >= cats.length)
      return;

    const currentIdx = cats.indexOf(currentProvider.selectedCategory);
    if (tabIndex === currentIdx)
      return;

    const canAnimate = !animationsDisabled && resultsSwapView.width > 0 && resultsSwapView.height > 0;
    if (!canAnimate) {
      applyCategorySelection(tabIndex, cats);
      return;
    }

    const direction = tabIndex > currentIdx ? 1 : -1;
    resultsSwapView.swap(direction, () => applyCategorySelection(tabIndex, providerCategories));
  }

  // Public API
  function setSearchText(text) {
    searchText = text;
  }

  // Provider registration
  function registerProvider(provider) {
    providers = providers.concat([provider]);
    provider.launcher = root;
    if (provider.init)
      provider.init();
  }

  function syncPluginProviders() {
    var registeredIds = LauncherProviderRegistry.getPluginProviders();
    var changed = false;

    // Remove providers that are no longer registered
    for (var existingId in pluginProviderInstances) {
      if (registeredIds.indexOf(existingId) === -1) {
        var idx = providers.indexOf(pluginProviderInstances[existingId]);
        if (idx >= 0)
          providers = providers.filter((provider, index) => index !== idx);
        delete pluginProviderInstances[existingId];
        Logger.d("Launcher", "Removed plugin provider:", existingId);
        changed = true;
      }
    }

    // Adopt persistent instances from the registry
    for (var i = 0; i < registeredIds.length; i++) {
      var providerId = registeredIds[i];
      if (!pluginProviderInstances[providerId]) {
        var instance = LauncherProviderRegistry.getProviderInstance(providerId);
        if (instance) {
          pluginProviderInstances[providerId] = instance;
          providers = providers.concat([instance]);
          instance.launcher = root;
          Logger.d("Launcher", "Adopted plugin provider:", providerId);
          changed = true;
        }
      }
    }

    // Update results only if providers changed
    if (changed && root.isOpen) {
      updateResults();
    }
  }

  // Search handling
  function updateResults(resetSelection) {
    if (!isOpen || !openReady)
      return;
    selectionAnimated = false;
    const previousItem = results[selectedIndex];
    const previousIndex = selectedIndex;
    let nextResults = [];
    var newActiveProvider = null;

    // Check for command mode
    if (searchText.startsWith(">")) {
      for (let provider of providers) {
        if (provider.handleCommand && provider.handleCommand(searchText)) {
          newActiveProvider = provider;
          nextResults = provider.getResults(searchText);
          break;
        }
      }

      // Show available commands if just ">" or filter commands if partial match
      if (!newActiveProvider) {
        let allCommands = [];
        for (let provider of providers) {
          if (provider.commands)
            allCommands = allCommands.concat(provider.commands());
        }
        if (searchText === ">") {
          nextResults = allCommands;
        } else if (searchText.length > 1) {
          const query = searchText.substring(1);
          if (typeof FuzzySort !== 'undefined') {
            const fuzzyResults = FuzzySort.go(query, allCommands, {
                                                "keys": ["name"],
                                                "limit": 50
                                              });
            nextResults = fuzzyResults.map(result => result.obj);
          } else {
            const queryLower = query.toLowerCase();
            nextResults = allCommands.filter(cmd => (cmd.name || "").toLowerCase().includes(queryLower));
          }
        }
      }
    } else {
      // Regular search - let providers contribute results
      let allResults = [];
      let appResults = [];
      let otherResults = [];
      for (let provider of providers) {
        if (provider.handleSearch) {
          const providerResults = provider.getResults(searchText);
          allResults = allResults.concat(providerResults);
          if (provider === defaultProvider)
            appResults = providerResults;
          else
            otherResults = otherResults.concat(providerResults);
        }
      }

      // Apps arrive fully ranked. Merge by match bucket with the other
      // providers' existing scores; never apply a second app/usage sort.
      if (searchText.trim() !== "") {
        allResults = LauncherResults.merge(appResults, otherResults, Settings.data.appLauncher.sortByMostUsed ? key => ShellState.getLauncherUsageCount(key) : null);
      }
      nextResults = allResults;
    }

    // Update activeProvider only after computing new state to avoid UI flicker
    activeProvider = newActiveProvider;
    projectRows(nextResults);
    results = nextResults;
    selectedIndex = LauncherSelection.afterRefresh(nextResults, previousItem, previousIndex, !!resetSelection);
    // The view applies the refresh's row moves now, not at its next polish, so
    // every highlight change the refresh causes happens here, unanimated.
    if (resultsView && resultsView.revealSelection)
      resultsView.revealSelection();
  }

  function selectFromPointer(index) {
    if (!ignoreMouseHover && mouseTrackingReady && index >= 0 && index < results.length) {
      selectionAnimated = true;
      selectedIndex = index;
    }
  }

  function trackPointer(index, point) {
    if (!mouseTrackingReady)
      return;
    if (!globalMouseInitialized) {
      globalLastMouseX = point.x;
      globalLastMouseY = point.y;
      globalMouseInitialized = true;
      return;
    }
    if (Math.abs(point.x - globalLastMouseX) + Math.abs(point.y - globalLastMouseY) >= 5) {
      ignoreMouseHover = false;
      globalLastMouseX = point.x;
      globalLastMouseY = point.y;
      selectFromPointer(index);
    }
  }

  // Navigation functions (delegated to LauncherNavigation.js)
  function selectNext() {
    selectedIndex = LauncherNav.selectNext(selectedIndex, results.length);
  }
  function selectPrevious() {
    selectedIndex = LauncherNav.selectPrevious(selectedIndex, results.length);
  }
  function selectNextWrapped() {
    selectedIndex = LauncherNav.selectNextWrapped(selectedIndex, results.length, allowWrapNavigation);
  }
  function selectPreviousWrapped() {
    selectedIndex = LauncherNav.selectPreviousWrapped(selectedIndex, results.length, allowWrapNavigation);
  }
  function selectFirst() {
    selectedIndex = LauncherNav.selectFirst();
  }
  function selectLast() {
    selectedIndex = LauncherNav.selectLast(results.length);
  }
  readonly property int visiblePageSize: {
    const view = resultsView;
    if (!view || isSingleView)
      return 1;
    const rowHeight = isGridView ? view.cellHeight : entryHeight + view.spacing;
    return Math.max(1, Math.floor(view.height / Math.max(1, rowHeight))) * (isGridView ? gridColumns : 1);
  }
  function selectNextPage() {
    selectedIndex = LauncherNav.selectNextPage(selectedIndex, results.length, visiblePageSize);
  }
  function selectPreviousPage() {
    selectedIndex = LauncherNav.selectPreviousPage(selectedIndex, results.length, visiblePageSize);
  }
  function selectPreviousRow() {
    selectedIndex = LauncherNav.selectPreviousRow(selectedIndex, results.length, gridColumns);
  }
  function selectNextRow() {
    selectedIndex = LauncherNav.selectNextRow(selectedIndex, results.length, gridColumns);
  }
  function selectPreviousColumn() {
    selectedIndex = LauncherNav.selectPreviousColumn(selectedIndex, results.length, gridColumns);
  }
  function selectNextColumn() {
    selectedIndex = LauncherNav.selectNextColumn(selectedIndex, results.length, gridColumns);
  }

  function activate() {
    if (results.length > 0 && results[selectedIndex]) {
      const item = results[selectedIndex];
      const provider = item.provider || currentProvider;

      // Track usage for providers that opt in (cross-provider "most used" tracking)
      if (Settings.data.appLauncher.sortByMostUsed && provider && provider.trackUsage && item.usageKey) {
        ShellState.recordLauncherUsage(item.usageKey);
      }

      // Check if auto-paste is enabled and provider/item supports it
      if (Settings.data.appLauncher.autoPasteClipboard && provider && provider.supportsAutoPaste && item.autoPasteText) {
        if (item.onAutoPaste)
          item.onAutoPaste();
        pasteText(item.autoPasteText);
        return;
      }

      if (item.onActivate)
        item.onActivate();
    }
  }

  function keyboardSelection(action) {
    ignoreMouseHover = true;
    globalMouseInitialized = false;
    selectionAnimated = true;
    action();
  }

  function selectCategoryBy(direction) {
    if (!showProviderCategories)
      return;
    const cats = providerCategories;
    const index = cats.indexOf(currentProvider.selectedCategory);
    selectCategoryWithSlide((index + direction + cats.length) % cats.length);
  }

  function removeSelectedItem() {
    const item = results[selectedIndex];
    const provider = item ? (item.provider || currentProvider) : null;
    if (provider && provider.canDeleteItem && provider.canDeleteItem(item))
      provider.deleteItem(item);
  }

  // All hosts, providers and layouts share this complete key table.
  // Configurable commands take precedence over the fixed editing meanings.
  // Editing entries fall through to Qt. Unbound non-editing keys are consumed
  // as no-op commands so they cannot trigger another surface's Shortcut.
  readonly property var keyTable: [
    {
      kind: "command",
      keys: Settings.data.general.keybinds.keyEscape,
      run: () => root.close()
    },
    {
      kind: "command",
      keys: Settings.data.general.keybinds.keyEnter,
      run: () => root.activate()
    },
    {
      kind: "command",
      keys: Settings.data.general.keybinds.keyUp,
      run: () => root.keyboardSelection(() => {
        if (!root.isSingleView)
          root.isGridView ? root.selectPreviousRow() : root.selectPreviousWrapped();
      })
    },
    {
      kind: "command",
      keys: Settings.data.general.keybinds.keyDown,
      run: () => root.keyboardSelection(() => {
        if (!root.isSingleView)
          root.isGridView ? root.selectNextRow() : root.selectNextWrapped();
      })
    },
    {
      kind: "command",
      keys: Settings.data.general.keybinds.keyRemove,
      run: () => root.removeSelectedItem()
    },
    {
      kind: "command",
      keys: ["PgUp"],
      run: () => root.keyboardSelection(root.selectPreviousPage)
    },
    {
      kind: "command",
      keys: ["PgDn"],
      run: () => root.keyboardSelection(root.selectNextPage)
    },
    {
      kind: "command",
      keys: ["Ctrl+Home"],
      run: () => root.keyboardSelection(root.selectFirst)
    },
    {
      kind: "command",
      keys: ["Ctrl+End"],
      run: () => root.keyboardSelection(root.selectLast)
    },
    {
      kind: "command",
      keys: ["Tab"],
      run: () => root.keyboardSelection(root.selectNextWrapped)
    },
    {
      kind: "command",
      keys: ["Shift+Tab"],
      run: () => root.keyboardSelection(root.selectPreviousWrapped)
    },
    {
      kind: "command",
      keys: ["Ctrl+Tab"],
      run: () => root.selectCategoryBy(1)
    },
    {
      kind: "command",
      keys: ["Ctrl+Shift+Tab"],
      run: () => root.selectCategoryBy(-1)
    },
    {
      kind: "editing",
      keys: ["Backspace", "Del", "Left", "Right", "Home", "End", "Shift+Backspace", "Shift+Del", "Shift+Left", "Shift+Right", "Shift+Home", "Shift+End", "Ctrl+Left", "Ctrl+Right", "Ctrl+Backspace", "Ctrl+Del", "Ctrl+Shift+Left", "Ctrl+Shift+Right", "Ctrl+Shift+Backspace", "Ctrl+Shift+Del", "Ctrl+A", "Ctrl+C", "Ctrl+X", "Ctrl+V", "Ctrl+Z", "Ctrl+Y", "Ctrl+Shift+Z",
        "Ctrl+Ins", "Shift+Ins"]
    },
    {
      kind: "editing",
      matches: event => {
        const textModifiers = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) || (event.modifiers & Qt.GroupSwitchModifier);
        const printable = event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127;
        const deadKey = event.key >= Qt.Key_Dead_Grave && event.key <= Qt.Key_Dead_Longsolidusoverlay;
        return textModifiers && (printable || deadKey);
      }
    },
    {
      kind: "command",
      matches: () => true,
      run: () => {}
    }
  ]

  NKeyOwner {
    scope: root
    input: searchInput.inputItem
    active: root.isOpen
    keyTable: root.keyTable
    keyString: event => Keybinds.getKeybindString(event)
  }

  // -----------------------
  // Provider components
  // -----------------------
  ApplicationsProvider {
    id: appsProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: ApplicationsProvider");
    }
  }

  ClipboardProvider {
    id: clipProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: ClipboardProvider");
    }
  }

  CommandProvider {
    id: cmdProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: CommandProvider");
    }
  }

  EmojiProvider {
    id: emojiProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: EmojiProvider");
    }
  }

  CalculatorProvider {
    id: calcProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: CalculatorProvider");
    }
  }

  SettingsProvider {
    id: settingsProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: SettingsProvider");
    }
  }

  SessionProvider {
    id: sessionProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: SessionProvider");
    }
  }

  WindowsProvider {
    id: windowsProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: WindowsProvider");
    }
  }

  // ==================== UI Content ====================

  // One movement owner across both views, including movement within a row
  // already hovered when keyboard navigation took over. The view exposes its
  // public content-coordinate hit test; delegates never own a second selection.
  HoverHandler {
    enabled: !Settings.data.appLauncher.ignoreMouseInput
    onPointChanged: {
      const view = root.resultsView;
      if (!view || !view.indexAt)
        return;
      const local = root.mapToItem(view, point.position.x, point.position.y);
      const index = local.x >= 0 && local.y >= 0 && local.x < view.width && local.y < view.height ? view.indexAt(local.x + view.contentX, local.y + view.contentY) : -1;
      root.trackPointer(index, point.position);
    }
  }

  opacity: resultsReady ? 1.0 : 0.0

  Behavior on opacity {
    NumberAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCirc
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.topMargin: Style.marginL
    anchors.bottomMargin: Style.marginL
    spacing: Style.marginL

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginL
      spacing: Style.marginS

      NTextInput {
        id: searchInput
        Layout.fillWidth: true
        radius: Style.iRadiusM
        text: root.searchText
        placeholderText: I18n.tr("placeholders.search-launcher")
        fontSize: Style.fontSizeM
        onTextChanged: root.searchText = text
      }

      AtmoIconButton {
        visible: root.showLayoutToggle
        icon: Settings.data.appLauncher.viewMode === "grid" ? "layout-list" : "layout-grid"
        tooltipText: Settings.data.appLauncher.viewMode === "grid" ? I18n.tr("tooltips.list-view") : I18n.tr("tooltips.grid-view")
        customRadius: Style.iRadiusM
        Layout.preferredWidth: searchInput.height
        Layout.preferredHeight: searchInput.height
        onClicked: Settings.data.appLauncher.viewMode = Settings.data.appLauncher.viewMode === "grid" ? "list" : "grid"
      }
    }

    // Unified category tabs (works with any provider that has categories)
    NTabBar {
      id: categoryTabs
      visible: root.showProviderCategories
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginL
      margins: 0
      border.color: Style.boxBorderColor
      border.width: Style.borderS

      property int computedCurrentIndex: visible && root.providerCategories.length > 0 ? root.providerCategories.indexOf(root.currentProvider.selectedCategory) : 0
      currentIndex: computedCurrentIndex

      Repeater {
        model: root.providerCategories
        NTabButton {
          required property string modelData
          required property int index
          icon: root.currentProvider.categoryIcons ? (root.currentProvider.categoryIcons[modelData] || "star") : "star"
          tooltipText: root.currentProvider.getCategoryName ? root.currentProvider.getCategoryName(modelData) : modelData
          tabIndex: index
          checked: categoryTabs.currentIndex === index
          onClicked: root.selectCategoryWithSlide(index)
        }
      }
    }

    // Results view
    NSlideSwapView {
      id: resultsSwapView
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginL
      Layout.fillHeight: true
      animationsEnabled: !root.animationsDisabled
      sourceComponent: root.isSingleView ? singleViewComponent : (root.isGridView ? gridViewComponent : listViewComponent)
    }

    // --------------------------
    // LIST VIEW
    Component {
      id: listViewComponent
      NListView {
        id: resultsList
        focus: false
        activeFocusOnTab: false

        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AlwaysOff
        reserveScrollbarSpace: false
        gradientColor: Settings.data.ui.panelBackgroundOpacity < 1 ? "transparent" : AtmoColor.mSurface
        wheelScrollMultiplier: 4.0

        width: parent.width
        height: parent.height
        spacing: Style.marginS
        model: root.resultsModel
        currentIndex: root.selectedIndex
        cacheBuffer: resultsList.height * 2
        interactive: !Settings.data.appLauncher.ignoreMouseInput
        onCurrentIndexChanged: {
          cancelFlick();
          if (currentIndex >= 0) {
            positionViewAtIndex(currentIndex, ListView.Contain);
          }
        }
        onModelChanged: Qt.callLater(revealSelection)
        function revealSelection() {
          cancelFlick();
          // Row moves inside the model can shift the view's own current index;
          // the selection stays authoritative.
          if (currentIndex !== root.selectedIndex)
            currentIndex = Qt.binding(() => root.selectedIndex);
          positionViewAtIndex(root.selectedIndex, ListView.Contain);
        }

        delegate: LauncherListDelegate {
          launcher: root
        }
      }
    }

    // --------------------------
    // SINGLE ITEM VIEW
    Component {
      id: singleViewComponent

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        NBox {
          anchors.fill: parent
          color: AtmoColor.mSurfaceVariant
          forceOpaque: true
          Layout.fillWidth: true
          Layout.fillHeight: true

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
              Layout.alignment: Qt.AlignTop | Qt.AlignLeft
              NText {
                text: root.results.length > 0 ? root.results[0].name : ""
                pointSize: Style.fontSizeL
                font.weight: Font.Bold
                color: AtmoColor.mPrimary
              }
            }

            NScrollView {
              id: descriptionScrollView
              Layout.alignment: Qt.AlignTop | Qt.AlignLeft
              Layout.topMargin: Style.fontSizeL + Style.marginXL
              Layout.fillWidth: true
              Layout.fillHeight: true
              horizontalPolicy: ScrollBar.AlwaysOff
              reserveScrollbarSpace: false

              NText {
                width: descriptionScrollView.availableWidth
                text: root.results.length > 0 ? root.results[0].description : ""
                pointSize: Style.fontSizeM
                font.weight: Font.Bold
                color: AtmoColor.mOnSurface
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

    // // --------------------------
    // GRID VIEW
    Component {
      id: gridViewComponent
      NGridView {
        id: resultsGrid

        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AlwaysOff
        reserveScrollbarSpace: false
        gradientColor: Settings.data.ui.panelBackgroundOpacity < 1 ? "transparent" : AtmoColor.mSurface
        wheelScrollMultiplier: 4.0
        trackedSelectionIndex: root.selectedIndex

        width: parent.width
        height: parent.height
        cellWidth: parent.width / root.targetGridColumns
        cellHeight: {
          var cellWidth = parent.width / root.targetGridColumns;
          // Use provider's preferred ratio if available
          if (root.currentProvider && root.currentProvider.preferredGridCellRatio) {
            return cellWidth * root.currentProvider.preferredGridCellRatio;
          }
          return cellWidth;
        }
        leftMargin: 0
        rightMargin: 0
        topMargin: 0
        bottomMargin: 0
        model: root.resultsModel
        cacheBuffer: resultsGrid.height * 2
        onModelChanged: Qt.callLater(revealSelection)
        function revealSelection() {
          cancelFlick();
          positionViewAtIndex(root.selectedIndex, GridView.Contain);
        }
        keyNavigationEnabled: false
        focus: false
        activeFocusOnTab: false
        interactive: !Settings.data.appLauncher.ignoreMouseInput

        // Completely disable GridView key handling
        Keys.enabled: false

        // Handle scrolling to show selected item when it changes
        Connections {
          target: root
          enabled: root.isGridView
          function onSelectedIndexChanged() {
            if (!root.isGridView || root.selectedIndex < 0 || !resultsGrid) {
              return;
            }

            Qt.callLater(() => {
              if (root.isGridView && resultsGrid && resultsGrid.cancelFlick) {
                resultsGrid.cancelFlick();
                resultsGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
              }
            });
          }
        }

        delegate: LauncherGridDelegate {
          launcher: root
        }
      }
    }

    ColumnLayout {
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginL

      NDivider {
        Layout.fillWidth: true
        Layout.bottomMargin: Style.marginS
      }

      NText {
        Layout.fillWidth: true
        text: {
          if (root.results.length === 0) {
            if (root.searchText) {
              return I18n.tr("common.no-results");
            }
            // Use provider's empty browsing message if available
            var provider = root.currentProvider;
            if (provider && provider.emptyBrowsingMessage) {
              return provider.emptyBrowsingMessage;
            }
            return "";
          }
          var prefix = root.activeProvider && root.activeProvider.name ? root.activeProvider.name + ": " : "";
          return prefix + I18n.trp("common.result-count", root.results.length);
        }
        pointSize: Style.fontSizeXS
        color: AtmoColor.mOnSurfaceVariant
        horizontalAlignment: Text.AlignCenter
      }
    }
  }
}
