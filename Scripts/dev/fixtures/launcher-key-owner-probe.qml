// Guest-only observer/fixture. Never imported by the production shell.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor
import qs.Services.Keyboard
import qs.Services.UI

Item {
  id: probe
  property var attachedCore: null
  property var challenger: null
  property bool compete: false
  property int shortcutHits: 0
  property int closes: 0
  property int activations: 0
  property string activatedName: ""
  property bool activationArmed: false
  property var liveCore: core()
  property var liveField: editor(liveCore)
  property var nativeEdges: []
  property var deliveredKeys: []
  property int keySerial: 0
  Connections {
    target: probe.liveCore
    function onResultsChanged() {
      probe.installActivationSpy();
    }
  }
  function installActivationSpy() {
    const current = core();
    if (!activationArmed || !current)
      return;
    for (const item of current.results) {
      item.onActivate = () => {
        probe.activations++;
        probe.activatedName = item.name;
      };
    }
  }
  property var pasteEvents: []
  property var lastPasteSession: null

  // Every facade focus notification, recorded synchronously inside its own
  // callback: what any consumer could read at that moment.
  property var focusNotifications: []
  readonly property string boundFocusTitle: CompositorService.getFocusedWindowTitle()
  function focusView(signalName) {
    const focused = CompositorService.getFocusedWindow();
    const rows = [];
    for (let i = 0; i < CompositorService.windows.count; i++) {
      const row = CompositorService.windows.get(i);
      rows.push({
                  id: row.id,
                  title: row.title,
                  isFocused: row.isFocused,
                  nativeId: row.handle && row.handle.id !== undefined ? row.handle.id : row.id
                });
    }
    const id = CompositorService.focusedWindowId === undefined ? "absent" : CompositorService.focusedWindowId;
    const index = CompositorService.focusedWindowIndex;
    const atIndex = index >= 0 && index < rows.length ? rows[index] : null;
    const title = CompositorService.getFocusedWindowTitle();
    const flagged = rows.filter(row => row.isFocused).map(row => row.id);
    const expected = atIndex ? atIndex.id : null;
    const checks = {
      index_names_id: id === "absent" || id === expected,
      getter: (focused ? focused.id : null) === expected,
      getter_title: !focused || String(focused.title).replace(/(\r\n|\n|\r)/g, "") === title,
      title: title === (atIndex ? String(atIndex.title).replace(/(\r\n|\n|\r)/g, "") : ""),
      // A consumer binding is current once the facade signals; inside a
      // property-change handler other bindings may still be pending.
      bound_title: (signalName !== "windowListChanged" && signalName !== "activeWindowChanged") || boundFocusTitle === title,
      one_flagged_row: JSON.stringify(flagged) === JSON.stringify(expected === null ? [] : [expected])
    };
    return {
      signal: signalName,
      at: Date.now(),
      focusedWindowId: id,
      focusedWindowIndex: index,
      focused: focused ? {
                           id: focused.id,
                           title: focused.title
                         } : null,
      title: title,
      boundTitle: boundFocusTitle,
      rows: rows,
      checks: checks,
      coherent: Object.keys(checks).every(key => checks[key])
    };
  }
  function recordFocus(signalName) {
    focusNotifications.push(focusView(signalName));
  }
  onBoundFocusTitleChanged: recordFocus("boundTitle")
  Connections {
    target: CompositorService
    function onWindowListChanged() {
      probe.recordFocus("windowListChanged");
    }
    function onActiveWindowChanged() {
      probe.recordFocus("activeWindowChanged");
    }
    function onFocusedWindowIdChanged() {
      probe.recordFocus("focusedWindowIdChanged");
    }
    function onFocusedWindowIndexChanged() {
      probe.recordFocus("focusedWindowIndexChanged");
    }
  }

  Connections {
    target: probe.liveCore ? probe.liveCore.Window.window : null
    function onActiveChanged() {
      probe.nativeEdges.push({
                               at: Date.now(),
                               active: probe.liveCore ? probe.liveCore.Window.active : false
                             });
    }
  }
  Connections {
    target: probe.liveField ? probe.liveField.Keys : null
    function onPressed(event) {
      if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_AltGr].indexOf(event.key) === -1)
        probe.keySerial++;
      probe.deliveredKeys.push({
                                 at: Date.now(),
                                 key: event.key,
                                 text: event.text
                               });
    }
  }

  function core() {
    const screen = PanelService.findFallbackScreen();
    // Track the observable slot even before getPanel's mutable registry is
    // populated; otherwise a probe constructed at startup can stay null.
    const panel = PanelService.openedPanel;
    if (!PanelService.isLauncherOpen(screen))
      return null;
    return Settings.data.appLauncher.overviewLayer ? PanelService.overlayLauncherCore : (panel ? panel.launcherCoreRef : null);
  }
  function editor(item) {
    if (!item)
      return null;
    if (item.cursorPosition !== undefined && item.preeditText !== undefined)
      return item;
    for (const child of item.children || []) {
      const found = editor(child);
      if (found)
        return found;
    }
    return null;
  }
  function attach() {
    const current = core();
    if (!current || attachedCore === current)
      return;
    attachedCore = current;
    current.requestClose.connect(() => probe.closes++);
    challenger = competition.createObject(current);
  }
  function snapshot() {
    const current = core();
    const field = editor(current);
    const view = current ? current.resultsView : null;
    return {
      open: !!current,
      query: current ? current.searchText : null,
      layout: current ? current.layoutMode : null,
      index: current ? current.selectedIndex : null,
      count: current ? current.results.length : 0,
      selected: current && current.results[current.selectedIndex] ? current.results[current.selectedIndex].name : null,
      clipboardId: current && current.results[current.selectedIndex] ? (current.results[current.selectedIndex].clipboardId || null) : null,
      autoPasteText: current && current.results[current.selectedIndex] ? (current.results[current.selectedIndex].autoPasteText || "") : "",
      category: current && current.currentProvider.selectedCategory !== undefined ? current.currentProvider.selectedCategory : null,
      categories: current ? current.providerCategories : [],
      resultNames: current ? current.results.map(item => item.name) : [],
      categoryBar: categoryBar(current),
      showCategories: current ? current.showProviderCategories : false,
      columns: current ? current.gridColumns : null,
      wrap: current ? current.allowWrapNavigation : null,
      single: current ? current.isSingleView : null,
      viewHeight: view ? view.height : null,
      rowHeight: view && current ? (current.isGridView ? view.cellHeight : current.entryHeight + view.spacing) : null,
      field: field ? {
                       text: field.text,
                       cursor: field.cursorPosition,
                       start: field.selectionStart,
                       end: field.selectionEnd,
                       selected: field.selectedText,
                       preedit: field.preeditText,
                       composing: field.inputMethodComposing,
                       focused: field.activeFocus
                     } : null,
      shortcutHits: shortcutHits,
      closes: closes,
      activations: activations,
      activatedName: activatedName,
      nativeActive: current ? current.Window.active : false,
      nativeEdges: nativeEdges.slice(-12),
      deliveredKeys: deliveredKeys.slice(-20),
      keySerial: keySerial
    };
  }
  function categoryBar(item) {
    if (!item)
      return null;
    if (item.computedCurrentIndex !== undefined)
      return {
        visible: item.visible,
        enabled: item.enabled,
        opacity: item.opacity,
        index: item.currentIndex
      };
    for (const child of item.children || []) {
      const found = categoryBar(child);
      if (found)
        return found;
    }
    return null;
  }

  Item {
    id: singleProvider
    property var launcher: null
    property string name: "K1 single-view plugin"
    property string supportedLayouts: "single"
    property bool handleSearch: false
    function handleCommand(text) {
      return text.startsWith(">keyfixture");
    }
    function getResults(text) {
      return [
            {
              name: "K1 single result",
              description: "Third-party provider contract fixture",
              provider: singleProvider,
              onActivate: () => {
                probe.activations++;
                probe.activatedName = "K1 single result";
              }
            }
          ];
    }
  }

  Component {
    id: competition
    Item {
      Shortcut {
        sequence: "Esc"
        enabled: probe.compete
        onActivated: probe.shortcutHits++
      }
      Shortcut {
        sequence: "Return"
        enabled: probe.compete
        onActivated: probe.shortcutHits++
      }
      Shortcut {
        sequence: "Enter"
        enabled: probe.compete
        onActivated: probe.shortcutHits++
      }
      Shortcut {
        sequence: "Ctrl+V"
        enabled: probe.compete
        onActivated: probe.shortcutHits++
      }
      Shortcut {
        sequence: "A"
        enabled: probe.compete
        onActivated: probe.shortcutHits++
      }
      Shortcut {
        sequence: "F1"
        enabled: probe.compete
        onActivated: probe.shortcutHits++
      }
      Button {
        id: focusThief
        text: "K1 focus challenger"
        width: 160
        height: 30
        focusPolicy: Qt.StrongFocus
      }
      function steal() {
        focusThief.forceActiveFocus();
      }
    }
  }

  IpcHandler {
    target: "launcherKeys"
    function state(): string {
      return JSON.stringify(probe.snapshot());
    }
    function configure(options: string): void {
      const opts = JSON.parse(options);
      Settings.data.appLauncher.overviewLayer = opts.host === "overlay";
      Settings.data.appLauncher.viewMode = opts.mode === "apps-grid" ? "grid" : "list";
      Settings.data.appLauncher.showCategories = true;
      ClipboardService.autoWatch = false;
      ClipboardService.stopWatchers();
      Settings.data.appLauncher.enableClipboardHistory = true;
      Settings.data.appLauncher.enableSessionSearch = true;
      Settings.data.appLauncher.autoPasteClipboard = false;
      Settings.data.general.animationDisabled = true;
      probe.compete = false;
      probe.shortcutHits = 0;
      probe.closes = 0;
      probe.activations = 0;
      probe.activatedName = "";
      probe.activationArmed = false;
      probe.pasteEvents = [];
      LauncherProviderRegistry.pluginProviders = Object.assign({}, LauncherProviderRegistry.pluginProviders, {
                                                                 "plugin:k1-single": singleProvider
                                                               });
      LauncherProviderRegistry.providerInstances = Object.assign({}, LauncherProviderRegistry.providerInstances, {
                                                                   "plugin:k1-single": singleProvider
                                                                 });
    }
    function observe(competing: string): void {
      probe.attach();
      probe.compete = competing === "true";
    }
    function stealFocus(): string {
      probe.challenger.steal();
      // Read immediately in the same JS call: no focus-settling wait allowed.
      return JSON.stringify(probe.snapshot());
    }
    function armActivation(): void {
      probe.activationArmed = true;
      probe.installActivationSpy();
    }
    function reprojectResults(): void {
      probe.core().updateResults();
    }
    // The persisted settings and watcher state configure() changes. The
    // console shell outlives every consumer, so consumers read these before
    // configuring and write them back afterwards (configured_settings()).
    function getLauncherSettings(): string {
      const launcher = Settings.data.appLauncher;
      return JSON.stringify({
                              overviewLayer: launcher.overviewLayer,
                              viewMode: launcher.viewMode,
                              showCategories: launcher.showCategories,
                              enableClipboardHistory: launcher.enableClipboardHistory,
                              enableSessionSearch: launcher.enableSessionSearch,
                              autoPasteClipboard: launcher.autoPasteClipboard,
                              animationDisabled: Settings.data.general.animationDisabled,
                              clipboardAutoWatch: ClipboardService.autoWatch
                            });
    }
    function setLauncherSettings(options: string): void {
      const values = JSON.parse(options);
      const launcher = Settings.data.appLauncher;
      launcher.overviewLayer = values.overviewLayer;
      launcher.viewMode = values.viewMode;
      launcher.showCategories = values.showCategories;
      launcher.enableClipboardHistory = values.enableClipboardHistory;
      launcher.enableSessionSearch = values.enableSessionSearch;
      launcher.autoPasteClipboard = values.autoPasteClipboard;
      Settings.data.general.animationDisabled = values.animationDisabled;
      ClipboardService.autoWatch = values.clipboardAutoWatch;
      if (values.clipboardAutoWatch)
        ClipboardService.startWatchers();
    }
    function bindings(options: string): void {
      const values = JSON.parse(options);
      for (const name in values)
        Settings.data.general.keybinds[name] = values[name];
    }
    function getBindings(options: string): string {
      const values = {};
      const bindings = ShellState.buildStateSnapshot().settings.general.keybinds;
      for (const name of JSON.parse(options).names)
        values[name] = bindings[name].slice();
      return JSON.stringify(values);
    }
    function autoPaste(enabled: bool): void {
      Settings.data.appLauncher.autoPasteClipboard = enabled;
    }
    function observePasteSession(): string {
      const session = probe.core().actionSession;
      probe.lastPasteSession = session;
      session.keyboardReleased.connect(sourceWasVisible => probe.pasteEvents.push({
                                                                                    at: Date.now(),
                                                                                    targetId: session.targetId,
                                                                                    sourceActive: session.nativeActive,
                                                                                    sourceVisible: sourceWasVisible
                                                                                  }));
      return JSON.stringify({
                              targetId: session.targetId,
                              hadKeyboard: session.hadKeyboard,
                              sourceActive: session.nativeActive
                            });
    }
    // A further committed job on the last observed session, enqueued now.
    function queuePasteText(text: string): string {
      LauncherActionService.pasteText(text, probe.lastPasteSession);
      return JSON.stringify({
                              at: Date.now(),
                              pending: LauncherActionService.pending.length
                            });
    }
    function pasteObservations(): string {
      const target = CompositorService.getFocusedWindow();
      return JSON.stringify({
                              events: probe.pasteEvents,
                              pending: LauncherActionService.pending.length,
                              sessions: LauncherActionService.pasteSessions.length,
                              focusedId: target ? target.id : null,
                              applicationState: Qt.application.state,
                              overlayCoreAlive: !!PanelService.overlayLauncherCore
                            });
    }
    // The same view as a notification record, read now.
    function focusNow(): string {
      return JSON.stringify(probe.focusView("now"));
    }
    // Notifications since the previous call, then cleared.
    function takeFocusNotifications(): string {
      const records = probe.focusNotifications;
      probe.focusNotifications = [];
      return JSON.stringify(records);
    }
    // Every shell view of the focused window, as its consumers read it.
    function focusIdentity(): string {
      const focused = CompositorService.getFocusedWindow();
      const rows = [];
      for (let i = 0; i < CompositorService.windows.count; i++) {
        const row = CompositorService.windows.get(i);
        rows.push({
                    id: row.id,
                    title: row.title,
                    isFocused: row.isFocused
                  });
      }
      return JSON.stringify({
                              focusedWindowId: CompositorService.focusedWindowId === undefined ? "absent" : CompositorService.focusedWindowId,
                              focusedWindowIndex: CompositorService.focusedWindowIndex,
                              focused: focused ? {
                                                   id: focused.id,
                                                   title: focused.title
                                                 } : null,
                              title: CompositorService.getFocusedWindowTitle(),
                              rows: rows
                            });
    }
    function hide(hidden: string): void {
      probe.core().visible = hidden !== "true";
    }
    function migrationCases(): string {
      const component = Qt.createComponent(Quickshell.shellDir + "/Commons/Migrations/Migration62.qml");
      const migration = component.createObject(probe);
      const rows = [];
      for (const value of [["Del"], ["Ctrl+D"], [], ["Del", "Ctrl+D"], ["Shift+Del"]]) {
        const adapter = {
          general: {
            keybinds: {
              keyRemove: value.slice()
            }
          }
        };
        const expected = value.length === 1 && value[0] === "Del" ? ["Shift+Del"] : value;
        migration.migrate(adapter, Logger, {
                            general: {
                              keybinds: {
                                keyRemove: value
                              }
                            }
                          });
        const once = adapter.general.keybinds.keyRemove;
        migration.migrate(adapter, Logger, adapter);
        rows.push({
                    before: value,
                    after: once,
                    pass: JSON.stringify(once) === JSON.stringify(expected) && JSON.stringify(once) === JSON.stringify(adapter.general.keybinds.keyRemove)
                  });
      }
      migration.destroy();
      return JSON.stringify({
                              rows: rows,
                              version: Settings.data.settingsVersion,
                              remove: Settings.data.general.keybinds.keyRemove
                            });
    }
  }
}
