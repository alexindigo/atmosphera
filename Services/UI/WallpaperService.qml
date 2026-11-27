pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../../Helpers/WallpaperSelection.js" as WallpaperSelection
import qs.Commons
import qs.Services.Power
import qs.Services.Theming
import qs.Services.UI

Singleton {
  id: root

  readonly property ListModel fillModeModel: ListModel {}
  readonly property string defaultDirectory: Settings.preprocessPath(Settings.data.wallpaper.directory)
  readonly property string solidColorPrefix: "solid://"

  // All available wallpaper transitions
  readonly property ListModel transitionsModel: ListModel {}

  // All transition keys but filter out "none" and "random" so we are left with the real transitions
  readonly property var allTransitions: Array.from({
                                                     "length": transitionsModel.count
                                                   }, (_, i) => transitionsModel.get(i).key).filter(key => key !== "random" && key != "none")

  property var wallpaperLists: ({})
  property int scanningCount: 0

  // Cache for current wallpapers - can be updated directly since we use signals for notifications
  property var currentWallpapers: ({})

  // A selection is intent until the shared still renderer acknowledges Ready.
  // Reservations are per screen and appearance; unrelated selections coexist.
  property var _wallpaperChanges: ({})
  property var _wallpaperReservations: ({})
  property int _wallpaperChangeSerial: 0
  signal wallpaperChangeFailed(string screenName, string path, string reason)

  // Last attempted path, not an index into a list that can be replaced.
  property var _alphabeticalPaths: ({})

  // Track used wallpapers for random mode (persisted across reboots)
  property var usedRandomWallpapers: ({})

  property bool isInitialized: false
  property string wallpaperCacheFile: ""

  readonly property bool scanning: (scanningCount > 0)
  property string defaultWallpaper: ""

  // Signals for reactive UI updates
  signal wallpaperChanged(string screenName, string path)
  // Emitted when a wallpaper changes
  signal wallpaperProcessingComplete(string screenName, string path, string cachedPath)
  // Emitted when wallpaper processing (resize/cache) is complete. cachedPath is the resized version.
  signal wallpaperDirectoryChanged(string screenName, string directory)
  // Emitted when a monitor's directory changes
  signal wallpaperListChanged(string screenName, int count)

  // Emitted when available wallpapers list changes

  // Browse mode: track current browse path per screen (separate from root directory)
  property var currentBrowsePaths: ({})

  // Wallpaper panel: which appearance slot (light/dark) new selections apply to — like picking a monitor tab
  property string wallpaperSelectionAppearance: "light"

  // After favoriting, refresh snapshot once theme colors finish transitioning
  property var pendingFavoriteSchemeRefresh: null

  // Signal emitted when browse path changes for a screen
  signal browsePathChanged(string screenName, string path)

  // Rescan when wallpaper pools register/unregister (plugin load happens
  // after the boot-time scan, so pools would otherwise never reach the lists)
  Connections {
    target: WallpaperProviderRegistry
    function onPoolsChanged() {
      root.refreshWallpapersList();
    }
  }

  Timer {
    id: favoriteSchemeDebounceTimer
    interval: 450
    repeat: false
    property string pendingPath: ""
    property string pendingSlot: ""
    onTriggered: {
      var p = pendingPath;
      var s = pendingSlot;
      pendingPath = "";
      pendingSlot = "";
      if (p && root.isFavorite(p)) {
        root.updateFavoriteColorScheme(p, s);
      }
    }
  }

  function scheduleFavoriteSchemeSnapshot(path, slot) {
    Qt.callLater(function () {
      if (root.isFavorite(path)) {
        root.updateFavoriteColorScheme(path, slot);
      }
    });
    favoriteSchemeDebounceTimer.pendingPath = path;
    favoriteSchemeDebounceTimer.pendingSlot = slot;
    favoriteSchemeDebounceTimer.restart();
    if (AtmoColor.isTransitioning) {
      root.pendingFavoriteSchemeRefresh = {
        "path": path,
        "slot": slot
      };
    }
  }

  Connections {
    target: Settings.data.wallpaper
    function onDirectoryChanged() {
      root.usedRandomWallpapers = {};
      root.refreshWallpapersList();
      // Emit directory change signals for monitors using the default directory
      if (!Settings.data.wallpaper.enableMultiMonitorDirectories) {
        // All monitors use the main directory
        for (var i = 0; i < Quickshell.screens.length; i++) {
          root.wallpaperDirectoryChanged(Quickshell.screens[i].name, root.defaultDirectory);
        }
      } else {
        // Only monitors without custom directories are affected
        for (var i = 0; i < Quickshell.screens.length; i++) {
          var screenName = Quickshell.screens[i].name;
          var monitor = root.getMonitorConfig(screenName);
          if (!monitor || !monitor.directory) {
            root.wallpaperDirectoryChanged(screenName, root.defaultDirectory);
          }
        }
      }
    }
    function onEnableMultiMonitorDirectoriesChanged() {
      root.usedRandomWallpapers = {};
      root.refreshWallpapersList();
      // Notify all monitors about potential directory changes
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name;
        root.wallpaperDirectoryChanged(screenName, root.getMonitorDirectory(screenName));
      }
    }
    function onAutomationEnabledChanged() {
      root.toggleRandomWallpaper();
    }
    function onRandomIntervalSecChanged() {
      root.restartRandomWallpaperTimer();
    }
    function onWallpaperChangeModeChanged() {
      root._alphabeticalPaths = {};
      if (Settings.data.wallpaper.automationEnabled) {
        root.restartRandomWallpaperTimer();
        root.setNextWallpaper(true);
      }
    }
    function onViewModeChanged() {
      // Reset browse paths to root when mode changes
      root.currentBrowsePaths = {};
      root.refreshWallpapersList();
    }
    function onShowHiddenFilesChanged() {
      root.refreshWallpapersList();
    }
    function onUseSolidColorChanged() {
      if (Settings.data.wallpaper.useSolidColor) {
        root._cancelWallpaperChanges();
        var solidPath = root.createSolidColorPath(Settings.data.wallpaper.solidColor.toString());
        for (var i = 0; i < Quickshell.screens.length; i++) {
          root.wallpaperChanged(Quickshell.screens[i].name, solidPath);
        }
      } else {
        for (var i = 0; i < Quickshell.screens.length; i++) {
          var screenName = Quickshell.screens[i].name;
          root.wallpaperChanged(screenName, root.getWallpaper(screenName) || root.defaultWallpaper);
        }
      }
    }
    function onSolidColorChanged() {
      if (Settings.data.wallpaper.useSolidColor) {
        root._cancelWallpaperChanges();
        var solidPath = root.createSolidColorPath(Settings.data.wallpaper.solidColor.toString());
        for (var i = 0; i < Quickshell.screens.length; i++) {
          root.wallpaperChanged(Quickshell.screens[i].name, solidPath);
        }
      }
    }
    function onSortOrderChanged() {
      root.refreshWallpapersList();
    }
    function onLinkLightAndDarkWallpapersChanged() {
      root._cancelWallpaperChanges();
      if (Settings.data.wallpaper.linkLightAndDarkWallpapers) {
        root.wallpaperSelectionAppearance = Settings.data.colorSchemes.darkMode ? "dark" : "light";
        root._syncWallpaperSlotsWhenLinking();
      }
      root._notifyAllWallpapersChanged();
    }
  }

  Connections {
    target: Settings.data.colorSchemes
    function onDarkModeChanged() {
      if (Settings.data.wallpaper.linkLightAndDarkWallpapers) {
        root.wallpaperSelectionAppearance = Settings.data.colorSchemes.darkMode ? "dark" : "light";
      }
      // Restore scheme from favorite for this light/dark slot before wallpaper refresh
      root.reapplyFavoriteThemeForActiveWallpaper();
      root._notifyAllWallpapersChanged();
    }
  }

  Connections {
    target: WallhavenService
    function onWallpaperDownloaded() {
      root.refreshWallpapersList();
    }
  }

  // -------------------------------------------------
  function init() {
    Logger.i("Wallpaper", "Service started");

    translateModels();
    Qt.callLater(root._dedupeWallpaperFavoritesByPath);

    // Initialize cache file path
    Qt.callLater(() => {
      if (typeof Settings !== 'undefined' && Settings.cacheDir) {
        wallpaperCacheFile = Settings.cacheDir + "wallpapers.json";
        wallpaperCacheView.path = wallpaperCacheFile;
      }
    });

    // Note: isInitialized will be set to true in wallpaperCacheView.onLoaded
    Logger.d("Wallpaper", "Triggering initial wallpaper scan");
    Qt.callLater(refreshWallpapersList);
  }

  // Cache restore updates currentWallpapers without _setWallpaper, so wallpaperChanged does not fire.
  function _scheduleThemeSyncFromCachedWallpaper() {
    Qt.callLater(function () {
      root.reapplyFavoriteThemeForActiveWallpaper();
      if (Settings.data.colorSchemes.useWallpaperColors) {
        AppThemeService.generate();
      }
    });
  }

  // -------------------------------------------------
  function translateModels() {
    // Wait for i18n to be ready by retrying every time
    if (!I18n.isLoaded) {
      Qt.callLater(translateModels);
      return;
    }

    // Populate fillModeModel with translated names
    fillModeModel.append({
                           "key": "center",
                           "name": I18n.tr("positions.center"),
                           "uniform": 0.0
                         });
    fillModeModel.append({
                           "key": "crop",
                           "name": I18n.tr("wallpaper.fill-modes.crop"),
                           "uniform": 1.0
                         });
    fillModeModel.append({
                           "key": "fit",
                           "name": I18n.tr("wallpaper.fill-modes.fit"),
                           "uniform": 2.0
                         });
    fillModeModel.append({
                           "key": "stretch",
                           "name": I18n.tr("wallpaper.fill-modes.stretch"),
                           "uniform": 3.0
                         });
    fillModeModel.append({
                           "key": "repeat",
                           "name": I18n.tr("wallpaper.fill-modes.repeat"),
                           "uniform": 4.0
                         });

    // Populate transitionsModel with translated names
    transitionsModel.append({
                              "key": "none",
                              "name": I18n.tr("common.none")
                            });
    transitionsModel.append({
                              "key": "random",
                              "name": I18n.tr("common.random")
                            });
    transitionsModel.append({
                              "key": "fade",
                              "name": I18n.tr("wallpaper.transitions.fade")
                            });
    transitionsModel.append({
                              "key": "disc",
                              "name": I18n.tr("wallpaper.transitions.disc")
                            });
    transitionsModel.append({
                              "key": "stripes",
                              "name": I18n.tr("wallpaper.transitions.stripes")
                            });
    transitionsModel.append({
                              "key": "wipe",
                              "name": I18n.tr("wallpaper.transitions.wipe")
                            });
    transitionsModel.append({
                              "key": "pixelate",
                              "name": I18n.tr("wallpaper.transitions.pixelate")
                            });
    transitionsModel.append({
                              "key": "honeycomb",
                              "name": I18n.tr("wallpaper.transitions.honeycomb")
                            });
  }

  // -------------------------------------------------------------------
  function getFillModeUniform() {
    for (var i = 0; i < fillModeModel.count; i++) {
      const mode = fillModeModel.get(i);
      if (mode.key === Settings.data.wallpaper.fillMode) {
        return mode.uniform;
      }
    }
    // Fallback to crop
    return 1.0;
  }

  // -------------------------------------------------------------------
  // Solid color helpers
  // -------------------------------------------------------------------
  function isSolidColorPath(path) {
    return path && typeof path === "string" && path.startsWith(solidColorPrefix);
  }

  function getSolidColor(path) {
    if (!isSolidColorPath(path)) {
      return null;
    }
    return path.substring(solidColorPrefix.length);
  }

  function createSolidColorPath(colorString) {
    return solidColorPrefix + colorString;
  }

  function setSolidColor(colorString) {
    _cancelWallpaperChanges();
    Settings.data.wallpaper.solidColor = String(colorString);
    Settings.data.wallpaper.useSolidColor = true;
  }

  // -------------------------------------------------------------------
  // Per-screen wallpaper: persisted as { light, dark } (legacy string loads are normalized)
  // -------------------------------------------------------------------
  function _isSplitWallpaperEntry(entry) {
    if (!entry || typeof entry !== "object") {
      return false;
    }
    return entry.light !== undefined || entry.dark !== undefined;
  }

  function _pathsFromEntry(entry) {
    if (!entry) {
      return {
        light: "",
        dark: ""
      };
    }
    if (typeof entry === "string") {
      return {
        light: entry,
        dark: entry
      };
    }
    return {
      light: entry.light || "",
      dark: entry.dark || ""
    };
  }

  function _cloneWallpaperEntry(entry) {
    if (typeof entry === "string") {
      return {
        light: entry,
        dark: entry
      };
    }
    var p = _pathsFromEntry(entry);
    return {
      light: p.light,
      dark: p.dark
    };
  }

  function _entriesEqual(a, b) {
    if (a === b) {
      return true;
    }
    if (typeof a === "string" && typeof b === "string") {
      return a === b;
    }
    if (typeof a === "string" || typeof b === "string") {
      return false;
    }
    if (!_isSplitWallpaperEntry(a) || !_isSplitWallpaperEntry(b)) {
      return false;
    }
    var pa = _pathsFromEntry(a);
    var pb = _pathsFromEntry(b);
    return pa.light === pb.light && pa.dark === pb.dark;
  }

  function _entryToEffectivePath(entry) {
    return WallpaperSelection.effective(entry, Settings.data.colorSchemes.darkMode);
  }

  function _normalizeAppearanceSlot(slot) {
    return slot === "dark" ? "dark" : "light";
  }

  function _defaultAppearanceSlotForChange(slot) {
    if (slot === "light" || slot === "dark") {
      return slot;
    }
    return Settings.data.colorSchemes.darkMode ? "dark" : "light";
  }

  function getWallpaperPathForSlot(screenName, appearanceSlot) {
    if (Settings.data.wallpaper.useSolidColor) {
      return createSolidColorPath(Settings.data.wallpaper.solidColor.toString());
    }
    var slot = _normalizeAppearanceSlot(appearanceSlot);
    var entry = currentWallpapers[screenName];
    if (!entry) {
      return "";
    }
    var p = _pathsFromEntry(entry);
    if (slot === "dark") {
      return p.dark || p.light || "";
    }
    return p.light || p.dark || "";
  }

  function getWallpapersEffectiveMap() {
    var out = {};
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var n = Quickshell.screens[i].name;
      out[n] = getWallpaper(n);
    }
    return out;
  }

  function _ensureObjectWallpaperEntries() {
    var names = {};
    Object.keys(currentWallpapers).forEach(function (k) {
      names[k] = true;
    });
    for (var i = 0; i < Quickshell.screens.length; i++) {
      names[Quickshell.screens[i].name] = true;
    }
    Object.keys(names).forEach(function (name) {
      var e = currentWallpapers[name];
      if (!e) {
        return;
      }
      if (typeof e === "string") {
        if (Settings.data.wallpaper.linkLightAndDarkWallpapers) {
          currentWallpapers[name] = {
            light: e,
            dark: e
          };
        } else {
          currentWallpapers[name] = {
            light: e,
            dark: e
          };
        }
      } else if (_isSplitWallpaperEntry(e)) {
        var p = _pathsFromEntry(e);
        if (Settings.data.wallpaper.linkLightAndDarkWallpapers) {
          currentWallpapers[name] = {
            light: p.light || p.dark || "",
            dark: p.dark || p.light || ""
          };
        } else {
          currentWallpapers[name] = {
            light: p.light || "",
            dark: p.dark || ""
          };
        }
      }
    });
    saveTimer.restart();
  }

  function _notifyAllWallpapersChanged() {
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var n = Quickshell.screens[i].name;
      root.wallpaperChanged(n, getWallpaper(n));
    }
  }

  // -------------------------------------------------------------------
  // Get specific monitor wallpaper data
  function getMonitorConfig(screenName) {
    var monitors = Settings.data.wallpaper.monitorDirectories;
    if (monitors !== undefined) {
      for (var i = 0; i < monitors.length; i++) {
        if (monitors[i].name !== undefined && monitors[i].name === screenName) {
          return monitors[i];
        }
      }
    }
  }

  // -------------------------------------------------------------------
  // Get specific monitor directory
  function getMonitorDirectory(screenName) {
    if (!Settings.data.wallpaper.enableMultiMonitorDirectories) {
      return root.defaultDirectory;
    }

    var monitor = getMonitorConfig(screenName);
    if (monitor !== undefined && monitor.directory !== undefined) {
      return Settings.preprocessPath(monitor.directory);
    }

    // Fall back to the main/single directory
    return root.defaultDirectory;
  }

  // -------------------------------------------------------------------
  // Set specific monitor directory
  function setMonitorDirectory(screenName, directory) {
    var monitors = Settings.data.wallpaper.monitorDirectories || [];
    var found = false;

    // Create a new array with updated values
    var newMonitors = monitors.map(function (monitor) {
      if (monitor.name === screenName) {
        found = true;
        return {
          "name": screenName,
          "directory": directory,
          "wallpaper": monitor.wallpaper || ""
        };
      }
      return monitor;
    });

    if (!found) {
      newMonitors.push({
                         "name": screenName,
                         "directory": directory,
                         "wallpaper": ""
                       });
    }

    // Update Settings with new array to ensure proper persistence
    Settings.data.wallpaper.monitorDirectories = newMonitors.slice();
    root.wallpaperDirectoryChanged(screenName, Settings.preprocessPath(directory));
  }

  // -------------------------------------------------------------------
  // Get specific monitor wallpaper - now from cache
  function getWallpaper(screenName) {
    // Return solid color path when in solid color mode
    if (Settings.data.wallpaper.useSolidColor) {
      return createSolidColorPath(Settings.data.wallpaper.solidColor.toString());
    }
    var entry = currentWallpapers[screenName];
    if (entry) {
      var effective = _entryToEffectivePath(entry);
      if (effective) {
        return effective;
      }
    }

    // Try to inherit wallpaper from another active screen
    var inherited = _inheritWallpaperFromExistingScreen(screenName);
    if (inherited) {
      return inherited;
    }

    var result = root.defaultWallpaper;
    Logger.i("Wallpaper", `getWallpaper(${screenName}) = "${result}" (defaultWallpaper)`);
    return result;
  }

  // -------------------------------------------------------------------
  function changeWallpaper(path, screenName, appearanceSlot, onComplete, retentionDirectory, onSettled, automatic) {
    // Setup supplies no explicit destination; capture the configured directory
    // with remote intent instead of submitting HTTP to local-only validation.
    if (!retentionDirectory && /^https?:\/\//i.test(String(path)))
      retentionDirectory = Settings.preprocessPath(Settings.data.wallpaper.directory) || Settings.defaultWallpapersDirectory;
    if (!path) {
      _rejectWallpaperChange(onSettled, "empty-source");
      return null;
    }
    var slot = _defaultAppearanceSlotForChange(appearanceSlot);
    var names = new Set();
    if (screenName !== undefined) {
      names.add(screenName);
    } else {
      Object.keys(currentWallpapers).forEach(name => names.add(name));
      for (var i = 0; i < Quickshell.screens.length; i++) {
        names.add(Quickshell.screens[i].name);
      }
    }
    if (!names.size) {
      _rejectWallpaperChange(onSettled, "no-target");
      return null;
    }
    var ticket = {
      id: String(++_wallpaperChangeSerial),
      automatic: automatic === true,
      path: String(path),
      slot: slot,
      slots: Settings.data.wallpaper.linkLightAndDarkWallpapers ? ["light", "dark"] : [slot],
      targets: Array.from(names),
      request: null,
      completed: onComplete,
      settled: onSettled,
      cancel: function () {
        root.cancelWallpaperChange(ticket);
      }
    };
    _wallpaperChanges[ticket.id] = ticket;
    ticket.targets.forEach(function (name) {
      ticket.slots.forEach(function (appearance) {
        root._wallpaperReservations[JSON.stringify([name, appearance])] = ticket.id;
      });
    });
    Object.keys(_wallpaperChanges).forEach(function (id) {
      var previous = root._wallpaperChanges[id];
      if (!root._wallpaperChangeTargets(previous).length)
        root.cancelWallpaperChange(previous, "superseded");
    });
    // A settlement observer can admit newer intent while this sweep is running.
    // A retired ticket must never start a new, now-unowned decoder interest.
    if (_wallpaperChanges[ticket.id] !== ticket)
      return ticket;
    if (isSolidColorPath(ticket.path)) {
      // callLater coalesces the same function; independent tickets must each settle.
      Qt.callLater(() => root._completeWallpaperChange(ticket, ticket.path, true, {
                                                         format: "solid"
                                                       }));
    } else if (retentionDirectory) {
      ticket.request = ImageCacheService.retainImage(ticket.path, retentionDirectory, function (output, success, detail) {
        root._completeWallpaperChange(ticket, output, success, detail);
      });
    } else {
      ticket.request = ImageCacheService.validateLocalImage(ticket.path, function (output, success, detail) {
        root._completeWallpaperChange(ticket, output, success, detail);
      });
    }
    return ticket;
  }

  function _wallpaperChangeTargets(ticket) {
    if (!ticket || _wallpaperChanges[ticket.id] !== ticket)
      return [];
    return ticket.targets.filter(function (name) {
      return ticket.slots.every(function (slot) {
        return root._wallpaperReservations[JSON.stringify([name, slot])] === ticket.id;
      });
    });
  }

  function _rejectWallpaperChange(callback, code) {
    if (typeof callback === "function")
      Qt.callLater(callback, {
                     state: "unavailable",
                     names: [],
                     targets: [],
                     detail: {
                       code: code
                     }
                   });
  }

  function _settleWallpaperChange(ticket, state, names, detail) {
    var callback = ticket.settled;
    ticket.settled = null;
    if (typeof callback === "function") {
      try {
        callback({
                   state: state,
                   names: names.slice(),
                   targets: ticket.targets.slice(),
                   detail: detail || {}
                 });
      } catch (error) {
        Logger.e("Wallpaper", "Wallpaper settlement callback failed");
      }
    }
  }

  function _releaseWallpaperChange(ticket) {
    if (!ticket || _wallpaperChanges[ticket.id] !== ticket)
      return false;
    delete _wallpaperChanges[ticket.id];
    ticket.targets.forEach(function (name) {
      ticket.slots.forEach(function (slot) {
        var key = JSON.stringify([name, slot]);
        if (root._wallpaperReservations[key] === ticket.id)
          delete root._wallpaperReservations[key];
      });
    });
    if (ticket.request)
      ticket.request.cancel();
    ticket.request = null;
    return true;
  }

  function cancelWallpaperChange(ticket, reason) {
    if (_releaseWallpaperChange(ticket))
      _settleWallpaperChange(ticket, "cancelled", [], {
                               code: reason || "cancelled"
                             });
  }

  function _cancelWallpaperChanges() {
    Object.keys(_wallpaperChanges).forEach(id => root.cancelWallpaperChange(root._wallpaperChanges[id], "superseded"));
  }

  function _completeWallpaperChange(ticket, output, success, detail) {
    if (_wallpaperChanges[ticket.id] !== ticket)
      return;
    var names = _wallpaperChangeTargets(ticket);
    // The callback renderer has already retired itself. Do not cancel it again.
    ticket.request = null;
    _releaseWallpaperChange(ticket);
    if (!names.length) {
      _settleWallpaperChange(ticket, "cancelled", [], {
                               code: "superseded"
                             });
      return;
    }
    if (!success || !output) {
      var reason = detail && detail.reason ? detail.reason : "The wallpaper could not be displayed";
      names.forEach(name => root.wallpaperChangeFailed(name, ticket.path, reason));
      Logger.w("Wallpaper", reason);
      ToastService.showError(I18n.tr("widgets.file-picker.preview-unavailable"), reason);
      try {
        if (ticket.completed)
          ticket.completed(false, names, detail);
      } finally {
        _settleWallpaperChange(ticket, "unavailable", names, detail);
      }
      return;
    }
    if (detail && detail.originalPath)
      ticket.path = detail.originalPath;
    else if (!isSolidColorPath(ticket.path))
      ticket.path = output;
    names.forEach(name => root._saveOutgoingFavorites(ticket.path, name, ticket.slot));
    if (Settings.data.wallpaper.useSolidColor)
      Settings.data.wallpaper.useSolidColor = false;
    names.forEach(name => root._setWallpaper(name, ticket.path, ticket.slot));
    try {
      if (ticket.completed)
        ticket.completed(true, names, detail);
    } finally {
      _settleWallpaperChange(ticket, "ready", names, detail);
    }
  }

  // UI selection applies its favorite theme only to an accepted color monitor.
  // Automation/IPC keep their existing changeWallpaper policy.
  function selectWallpaper(path, screenName, appearanceSlot) {
    var slot = _defaultAppearanceSlotForChange(appearanceSlot);
    return changeWallpaper(path, screenName, slot, function (success, names) {
      if (success)
        names.forEach(name => root.applyFavoriteTheme(path, name, slot));
    });
  }

  function selectRemoteWallpaper(source, directory, screenName, appearanceSlot, onComplete) {
    var slot = _defaultAppearanceSlotForChange(appearanceSlot);
    return changeWallpaper(source, screenName, slot, function (success, names, detail) {
      if (success)
        names.forEach(name => root.applyFavoriteTheme(detail.originalPath, name, slot));
      if (onComplete)
        onComplete(success, names, detail);
    }, directory);
  }

  // -------------------------------------------------------------------
  // Save the color scheme of any favorited wallpapers that are about
  // to be replaced, while the current settings still reflect them.
  function _saveOutgoingFavorites(newPath, screenName, appearanceSlot) {
    var paths = [];
    var slot = _normalizeAppearanceSlot(appearanceSlot);

    function collectFromEntry(e) {
      if (!e) {
        return;
      }
      if (typeof e === "string") {
        if (e && e !== newPath) {
          paths.push(e);
        }
        return;
      }
      if (!_isSplitWallpaperEntry(e)) {
        return;
      }
      var p = _pathsFromEntry(e);
      if (Settings.data.wallpaper.linkLightAndDarkWallpapers) {
        if (p.light && p.light !== newPath) {
          paths.push(p.light);
        }
        if (p.dark && p.dark !== newPath && p.dark !== p.light) {
          paths.push(p.dark);
        }
      } else {
        var old = slot === "dark" ? p.dark : p.light;
        if (old && old !== newPath) {
          paths.push(old);
        }
      }
    }

    if (screenName !== undefined) {
      collectFromEntry(currentWallpapers[screenName]);
    } else {
      var names = new Set(Object.keys(currentWallpapers));
      for (var i = 0; i < Quickshell.screens.length; i++) {
        names.add(Quickshell.screens[i].name);
      }
      names.forEach(function (name) {
        collectFromEntry(currentWallpapers[name]);
      });
    }

    var unique = [];
    for (var j = 0; j < paths.length; j++) {
      if (unique.indexOf(paths[j]) === -1) {
        unique.push(paths[j]);
      }
    }

    unique.forEach(function (path) {
      if (!path || path === newPath) {
        return;
      }
      var favIdx = _findAnyFavoriteIndexForPath(path);
      if (favIdx === _favoriteNotFound) {
        return;
      }
      var app = _favoriteAppearanceSlot(Settings.data.wallpaper.favorites[favIdx]);
      updateFavoriteColorScheme(path, app);
    });
  }

  // -------------------------------------------------------------------
  function _inheritWallpaperFromExistingScreen(screenName) {
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var otherName = Quickshell.screens[i].name;
      if (otherName === screenName) {
        continue;
      }
      var entry = currentWallpapers[otherName];
      if (!entry) {
        continue;
      }
      var cloned = _cloneWallpaperEntry(entry);
      if (_entriesEqual(currentWallpapers[screenName], cloned)) {
        return _entryToEffectivePath(cloned);
      }
      currentWallpapers[screenName] = cloned;
      saveTimer.restart();
      root.wallpaperChanged(screenName, _entryToEffectivePath(cloned));
      if (randomWallpaperTimer.running) {
        randomWallpaperTimer.restart();
      }
      return _entryToEffectivePath(cloned);
    }
    return "";
  }

  function _syncWallpaperSlotsWhenLinking() {
    var names = new Set(Object.keys(currentWallpapers));
    for (var i = 0; i < Quickshell.screens.length; i++) {
      names.add(Quickshell.screens[i].name);
    }
    names.forEach(function (name) {
      var e = currentWallpapers[name];
      if (!e) {
        return;
      }
      var eff = _entryToEffectivePath(e);
      if (!eff) {
        return;
      }
      var merged = {
        light: eff,
        dark: eff
      };
      if (_entriesEqual(e, merged)) {
        return;
      }
      currentWallpapers[name] = merged;
      saveTimer.restart();
      root.wallpaperChanged(name, eff);
    });
    if (randomWallpaperTimer.running) {
      randomWallpaperTimer.restart();
    }
  }

  function _setWallpaper(screenName, path, appearanceSlot) {
    if (path === "" || path === undefined) {
      return;
    }

    if (screenName === undefined) {
      Logger.w("Wallpaper", "setWallpaper", "no screen specified");
      return;
    }

    var slot = _normalizeAppearanceSlot(appearanceSlot);
    var oldEntry = currentWallpapers[screenName];
    var p = _pathsFromEntry(oldEntry);
    var newEntry;
    if (Settings.data.wallpaper.linkLightAndDarkWallpapers) {
      newEntry = {
        light: path,
        dark: path
      };
    } else if (slot === "dark") {
      newEntry = {
        light: p.light || "",
        dark: path
      };
    } else {
      newEntry = {
        light: path,
        dark: p.dark || ""
      };
    }

    if (_entriesEqual(oldEntry, newEntry)) {
      return;
    }

    currentWallpapers[screenName] = newEntry;
    saveTimer.restart();
    root.wallpaperChanged(screenName, _entryToEffectivePath(newEntry));

    if (randomWallpaperTimer.running) {
      randomWallpaperTimer.restart();
    }
  }

  // -------------------------------------------------------------------
  function setRandomWallpaper(screen, automatic) {
    Logger.d("Wallpaper", "setRandomWallpaper");

    if (Settings.data.wallpaper.enableMultiMonitorDirectories) {
      if (screen === undefined) {
        // Pick a random wallpaper per screen
        for (var i = 0; i < Quickshell.screens.length; i++) {
          var screenName = Quickshell.screens[i].name;
          var wallpaperList = getWallpapersList(screenName);

          if (wallpaperList.length > 0) {
            var randomPath = _pickUnusedRandom(screenName, wallpaperList);
            _changeRotatingWallpaper(randomPath, screenName, automatic);
          }
        }
      } else {
        // Pick a random wallpaper for the specified screen
        var wallpaperList = getWallpapersList(screen);
        if (wallpaperList.length > 0) {
          var randomPath = _pickUnusedRandom(screen, wallpaperList);
          _changeRotatingWallpaper(randomPath, screen, automatic);
        }
      }
    } else {
      // Pick a random wallpaper common to all screens
      // We can use any screenName here, so we just pick the primary one.
      var wallpaperList = getWallpapersList(Screen.name);
      if (wallpaperList.length > 0) {
        var randomPath = _pickUnusedRandom("all", wallpaperList);
        _changeRotatingWallpaper(randomPath, screen, automatic);
      }
    }
  }

  // -------------------------------------------------------------------
  // Pick a random wallpaper that hasn't been used yet in the current cycle.
  // Once all wallpapers have been shown, resets the pool (keeping only the
  // last-shown wallpaper to avoid an immediate repeat).
  function _pickUnusedRandom(key, wallpaperList) {
    var used = usedRandomWallpapers[key] || [];

    // Clean stale entries (files that were removed from the directory)
    var wallpaperSet = new Set(wallpaperList);
    used = used.filter(function (path) {
      return wallpaperSet.has(path);
    });

    // Filter to wallpapers that haven't been used yet
    var unused = wallpaperList.filter(function (path) {
      return used.indexOf(path) === -1;
    });

    // If all have been used, reset but keep the last one to avoid immediate repeat
    if (unused.length === 0) {
      var lastUsed = used.length > 0 ? used[used.length - 1] : "";
      used = lastUsed ? [lastUsed] : [];
      unused = wallpaperList.filter(function (path) {
        return used.indexOf(path) === -1;
      });
      // Edge case: only one wallpaper in the directory
      if (unused.length === 0) {
        unused = wallpaperList;
      }
      Logger.d("Wallpaper", "All wallpapers used for", key, "- resetting pool");
    }

    // Pick randomly from unused
    var randomIndex = Math.floor(Math.random() * unused.length);
    var picked = unused[randomIndex];

    // Record as used
    used.push(picked);
    usedRandomWallpapers[key] = used;

    // Persist
    saveTimer.restart();

    return picked;
  }

  // -------------------------------------------------------------------
  function _changeRotatingWallpaper(path, screen, automatic) {
    if (automatic !== true || Settings.data.wallpaper.automationEnabled)
      changeWallpaper(path, screen, undefined, undefined, undefined, undefined, automatic);
  }

  function _advanceAlphabeticalWallpaper(listScreen, changeScreen, automatic) {
    var list = getWallpapersList(listScreen);
    if (!list.length)
      return;
    var key = changeScreen === undefined ? "all" : changeScreen;
    var lastPath = _alphabeticalPaths[key];
    var index = lastPath === undefined ? -1 : list.indexOf(lastPath);
    if (index < 0)
      index = Math.max(0, list.indexOf(getWallpaper(listScreen) || ""));
    var nextPath = list[(index + 1) % list.length];
    // Advance on attempt as well as success so decoder errors cannot stall rotation.
    _alphabeticalPaths[key] = nextPath;
    _changeRotatingWallpaper(nextPath, changeScreen, automatic);
  }

  function setAlphabeticalWallpaper(automatic) {
    Logger.d("Wallpaper", "setAlphabeticalWallpaper");

    if (Settings.data.wallpaper.enableMultiMonitorDirectories) {
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name;
        _advanceAlphabeticalWallpaper(screenName, screenName, automatic);
      }
    } else
      _advanceAlphabeticalWallpaper(Screen.name, undefined, automatic);
  }

  // -------------------------------------------------------------------
  function toggleRandomWallpaper() {
    Logger.d("Wallpaper", "toggleRandomWallpaper");
    if (Settings.data.wallpaper.automationEnabled) {
      restartRandomWallpaperTimer();
      setNextWallpaper(true);
    } else {
      Object.keys(_wallpaperChanges).forEach(id => {
        var ticket = root._wallpaperChanges[id];
        if (ticket && ticket.automatic)
          root.cancelWallpaperChange(ticket, "automation-disabled");
      });
    }
  }

  // -------------------------------------------------------------------
  function setNextWallpaper(automatic) {
    var mode = Settings.data.wallpaper.wallpaperChangeMode || "random";
    if (mode === "alphabetical") {
      setAlphabeticalWallpaper(automatic);
    } else {
      setRandomWallpaper(undefined, automatic);
    }
  }

  // -------------------------------------------------------------------
  function restartRandomWallpaperTimer() {
    if (Settings.data.wallpaper.automationEnabled) {
      randomWallpaperTimer.restart();
    }
  }

  // -------------------------------------------------------------------
  function getWallpapersList(screenName) {
    if (screenName != undefined && wallpaperLists[screenName] != undefined) {
      return wallpaperLists[screenName];
    }
    return [];
  }

  // -------------------------------------------------------------------
  // Browse mode helper functions
  // -------------------------------------------------------------------
  function getCurrentBrowsePath(screenName) {
    if (currentBrowsePaths[screenName] !== undefined) {
      var stored = currentBrowsePaths[screenName];
      var root = getMonitorDirectory(screenName);
      if (root && stored.startsWith(root)) {
        return stored;
      }
      // Stored path is outside the root directory, reset it
      delete currentBrowsePaths[screenName];
    }
    return getMonitorDirectory(screenName);
  }

  function setBrowsePath(screenName, path) {
    if (!screenName)
      return;
    currentBrowsePaths[screenName] = path;
    browsePathChanged(screenName, path);
  }

  function navigateUp(screenName) {
    if (!screenName)
      return;
    var currentPath = getCurrentBrowsePath(screenName);
    var rootPath = getMonitorDirectory(screenName);

    // Don't navigate if root is invalid or we're already at root
    if (!rootPath || currentPath === rootPath)
      return;

    // Get parent directory
    var parentPath = currentPath.replace(/\/[^\/]+\/?$/, "");
    if (parentPath === "")
      parentPath = rootPath;

    // Don't go above root
    if (!parentPath.startsWith(rootPath)) {
      parentPath = rootPath;
    }

    setBrowsePath(screenName, parentPath);
  }

  function navigateToRoot(screenName) {
    if (!screenName)
      return;
    var rootPath = getMonitorDirectory(screenName);
    setBrowsePath(screenName, rootPath);
  }

  // Scan directory with optional directory listing (for browse mode)
  // callback receives { files: [], directories: [] }
  function scanDirectoryWithDirs(screenName, directory, callback) {
    if (!directory || directory === "") {
      callback({
                 files: [],
                 directories: []
               });
      return;
    }

    var result = {
      files: [],
      directories: []
    };
    var pendingScans = 2;

    function checkComplete() {
      pendingScans--;
      if (pendingScans === 0) {
        // Files are already sorted by _scanDirectoryInternal according to sortOrder setting
        // Only sort directories alphabetically
        result.directories.sort();
        callback(result);
      }
    }

    // Scan for files
    _scanDirectoryInternal(screenName, directory, false, false, function (files) {
      result.files = files;
      checkComplete();
    });

    // Scan for directories
    _scanForDirectories(directory, function (dirs) {
      result.directories = dirs;
      checkComplete();
    });
  }

  function _scanForDirectories(directory, callback) {
    var findArgs = ["find", "-L", directory, "-maxdepth", "1", "-mindepth", "1", "-type", "d", "-print0"];
    var processObject = directoryScanComponent.createObject(root, {
                                                              command: findArgs
                                                            });

    processObject.exited.connect(function (exitCode) {
      var dirs = [];
      if (exitCode === 0) {
        var lines = processObject.stdout.text.split('\0');
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i];
          if (line !== '') {
            var showHidden = Settings.data.wallpaper.showHiddenFiles;
            var name = line.split('/').pop();
            if (showHidden || !name.startsWith('.')) {
              dirs.push(line);
            }
          }
        }
      }
      callback(dirs);
      processObject.destroy();
    });

    processObject.running = true;
  }

  // -------------------------------------------------------------------
  // Publication belongs to a captured refresh group, never an individual find.
  // Browse-only callers own independent processes and cannot retire this group.
  property var _wallpaperListScans: ({})

  Component {
    id: directoryScanComponent
    Process {
      stdout: StdioCollector {}
      stderr: StdioCollector {}
    }
  }

  function _retireWallpaperListScan(screenName) {
    var scan = _wallpaperListScans[screenName];
    if (!scan)
      return;
    delete _wallpaperListScans[screenName];
    --scanningCount;
    scan.jobs.forEach(job => job.cancel());
  }

  function _publishWallpaperList(screenName, files) {
    wallpaperLists[screenName] = files;
    wallpaperListChanged(screenName, files.length);
  }

  function _startWallpaperListScan(screenName, directories) {
    _retireWallpaperListScan(screenName);
    var scan = {
      pending: directories.length,
      results: [],
      jobs: []
    };
    _wallpaperListScans[screenName] = scan;
    ++scanningCount;
    directories.forEach(function (directory, index) {
      var job = root._scanDirectoryInternal(screenName, directory.path, directory.recursive, false, function (files) {
        if (root._wallpaperListScans[screenName] !== scan)
          return;
        scan.results[index] = files;
        if (--scan.pending)
          return;
        delete root._wallpaperListScans[screenName];
        --root.scanningCount;
        // Main directory first, followed by each pool's existing sort order.
        var merged = [];
        var seen = new Set();
        scan.results.forEach(paths => paths.forEach(function (path) {
          if (!seen.has(path)) {
            seen.add(path);
            merged.push(path);
          }
        }));
        root._publishWallpaperList(screenName, merged);
      });
      if (job)
        scan.jobs.push(job);
    });
  }

  function refreshWallpapersList() {
    if (typeof WallpaperProviderRegistry === "undefined") {
      // Services not ready yet, retry
      Qt.callLater(refreshWallpapersList);
      return;
    }

    var mode = Settings.data.wallpaper.viewMode;
    Logger.d("Wallpaper", "refreshWallpapersList", "viewMode:", mode);
    Object.keys(_wallpaperListScans).forEach(name => root._retireWallpaperListScan(name));

    for (var i = 0; i < Quickshell.screens.length; i++) {
      var screenName = Quickshell.screens[i].name;
      var directories = [
            {
              path: mode === "browse" ? getCurrentBrowsePath(screenName) : getMonitorDirectory(screenName),
              recursive: mode === "recursive"
            }
          ];

      // Scan active pack pools
      var activePools = WallpaperProviderRegistry.getActivePools(screenName);
      for (var p = 0; p < activePools.length; p++) {
        var pool = activePools[p];
        if (pool.source === "plugin") {
          directories.push({
                             path: pool.dir,
                             recursive: false
                           });
        }
      }
      _startWallpaperListScan(screenName, directories);
    }
  }

  // Internal scan function
  // recursive: whether to scan subdirectories
  // updateList: whether to update wallpaperLists and emit signal
  // callback: optional callback with files array
  function _scanDirectoryInternal(screenName, directory, recursive, updateList, callback) {
    if (updateList) {
      _startWallpaperListScan(screenName, [
                                {
                                  path: directory,
                                  recursive: recursive
                                }
                              ]);
      return null;
    }
    if (!directory || directory === "") {
      Logger.w("Wallpaper", "Empty directory for", screenName);
      if (callback)
        callback([]);
      return null;
    }
    Logger.i("Wallpaper", "Starting scan for", screenName, "in", directory, "recursive:", recursive);

    // Build find command args dynamically from ImageCacheService filters
    var filters = ImageCacheService.imageFilters;
    var findArgs = ["find", "-L", directory];

    // Add depth limit for non-recursive
    if (!recursive) {
      findArgs.push("-maxdepth", "1", "-mindepth", "1");
    }

    findArgs.push("-type", "f", "(");
    for (var i = 0; i < filters.length; i++) {
      if (i > 0) {
        findArgs.push("-o");
      }
      findArgs.push("-iname");
      findArgs.push(filters[i]);
    }
    findArgs.push(")");
    // Add printf to get modification time
    findArgs.push("-printf", "%T@|%p\\0");
    var processObject = directoryScanComponent.createObject(root, {
                                                              command: findArgs
                                                            });
    var ticket = {
      process: processObject,
      cancel: function () {
        if (!ticket.process)
          return;
        ticket.process.exited.disconnect(handler);
        ticket.process.running = false;
        ticket.process.destroy();
        ticket.process = null;
      }
    };

    var handler = function (exitCode) {
      Logger.d("Wallpaper", "Process exited with code", exitCode, "for", screenName);

      var files = [];
      if (exitCode === 0) {
        var lines = processObject.stdout.text.split('\0');
        var parsedFiles = [];

        for (var i = 0; i < lines.length; i++) {
          var line = lines[i];
          if (line !== '') {
            var parts = line.split('|');
            if (parts.length >= 2) { // Handle potential extra pipes in filename by joining rest
              var timestamp = parseFloat(parts[0]);
              var path = parts.slice(1).join('|');

              var showHidden = Settings.data.wallpaper.showHiddenFiles;
              var name = path.split('/').pop();
              if (showHidden || !name.startsWith('.')) {
                parsedFiles.push({
                                   path: path,
                                   time: timestamp,
                                   name: name
                                 });
              }
            } else if (line.indexOf('|') === -1) {
              // Fallback for unexpected output format or old find versions (unlikely but safe)
              var path = line;
              var showHidden = Settings.data.wallpaper.showHiddenFiles;
              var name = path.split('/').pop();
              if (showHidden || !name.startsWith('.')) {
                parsedFiles.push({
                                   path: path,
                                   time: 0,
                                   name: name
                                 });
              }
            }
          }
        }
        // Sort files based on settings
        var sortOrder = Settings.data.wallpaper.sortOrder || "name";

        // Fischer-Yates shuffle
        if (sortOrder === "random") {
          for (let i = parsedFiles.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const temp = parsedFiles[i];
            parsedFiles[i] = parsedFiles[j];
            parsedFiles[j] = temp;
          }
        } else {
          parsedFiles.sort(function (a, b) {
            if (sortOrder === "date_desc") { // Newest first
              return b.time - a.time;
            } else if (sortOrder === "date_asc") { // Oldest first
              return a.time - b.time;
            } else if (sortOrder === "name_desc") {
              return b.name.localeCompare(a.name);
            } else { // name (asc)
              return a.name.localeCompare(b.name);
            }
          });
        }

        // Map back to string array
        files = parsedFiles.map(f => f.path);
      } else {
        Logger.w("Wallpaper", "Scan failed for", screenName, "exit code:", exitCode, "(directory might not exist)");
      }

      // Clean up
      ticket.process = null;
      if (callback)
        callback(files);
      processObject.destroy();
    };

    processObject.exited.connect(handler);
    Logger.d("Wallpaper", "Starting process for", screenName);
    processObject.running = true;
    return ticket;
  }

  // -------------------------------------------------------------------
  function scanDirectoryRecursive(screenName, directory) {
    _scanDirectoryInternal(screenName, directory, true, true, null);
  }

  // -------------------------------------------------------------------
  // Favorites
  // -------------------------------------------------------------------
  // TODO (~few weeks): Remove per-favorite `darkMode` (the boolean on each
  // Settings.data.wallpaper.favorites[] entry). It duplicates `appearance` and is
  // unrelated to Settings.data.colorSchemes.darkMode (global shell light/dark).
  // Plan: one-time migration, then drop writes and the fallback in _favoriteAppearanceSlot.
  // -------------------------------------------------------------------
  readonly property int _favoriteNotFound: -1

  // -------------------------------------------------------------------
  function _favoriteAppearanceSlot(f) {
    if (f.appearance === "light" || f.appearance === "dark") {
      return f.appearance;
    }
    return f.darkMode ? "dark" : "light";
  }

  function _findFavoriteIndex(path, appearanceSlot) {
    var favorites = Settings.data.wallpaper.favorites;
    var searchPath = Settings.preprocessPath(path);
    var slot = _normalizeAppearanceSlot(appearanceSlot);
    for (var i = 0; i < favorites.length; i++) {
      if (Settings.preprocessPath(favorites[i].path) !== searchPath) {
        continue;
      }
      if (_favoriteAppearanceSlot(favorites[i]) === slot) {
        return i;
      }
    }
    return _favoriteNotFound;
  }

  function _findAnyFavoriteIndexForPath(path) {
    var favorites = Settings.data.wallpaper.favorites;
    var searchPath = Settings.preprocessPath(path);
    for (var i = 0; i < favorites.length; i++) {
      if (Settings.preprocessPath(favorites[i].path) === searchPath) {
        return i;
      }
    }
    return _favoriteNotFound;
  }

  function _dedupeWallpaperFavoritesByPath() {
    var favorites = Settings.data.wallpaper.favorites;
    if (!favorites || !favorites.length) {
      return;
    }
    var seen = {};
    var out = [];
    for (var i = 0; i < favorites.length; i++) {
      var key = Settings.preprocessPath(favorites[i].path);
      if (!key || seen[key]) {
        continue;
      }
      seen[key] = true;
      out.push(favorites[i]);
    }
    if (out.length !== favorites.length) {
      Settings.data.wallpaper.favorites = out;
    }
  }

  // -------------------------------------------------------------------
  function _createFavoriteEntry(path, appearanceSlot) {
    var app = _normalizeAppearanceSlot(appearanceSlot);
    return {
      "path": path,
      "appearance": app,
      "colorScheme": Settings.data.colorSchemes.predefinedScheme,
      "darkMode": app === "dark" // TODO: remove per-favorite field (see Favorites section note)
                  ,
      "useWallpaperColors": Settings.data.colorSchemes.useWallpaperColors,
      "generationMethod": Settings.data.colorSchemes.generationMethod,
      "paletteColors": [AtmoColor.mPrimary.toString(), AtmoColor.mSecondary.toString(), AtmoColor.mTertiary.toString(), AtmoColor.mError.toString()]
    };
  }

  // -------------------------------------------------------------------
  // Favorites are per (path, light|dark): at most one entry per path, tagged with the tab you starred from.
  function isFavorite(path, appearanceSlot) {
    if (appearanceSlot === undefined || appearanceSlot === null || appearanceSlot === "") {
      return _findAnyFavoriteIndexForPath(path) !== _favoriteNotFound;
    }
    return _findFavoriteIndex(path, appearanceSlot) !== _favoriteNotFound;
  }

  // Bindings track the settings list read during lookup. Writers replace the
  // list (including for palette updates), so consumers need no revision counter.
  // Use _favoriteAppearanceSlot(entry) for the light or dark slot it was starred under.
  function favoriteEntryForPath(path) {
    var idx = _findAnyFavoriteIndexForPath(path);
    if (idx === _favoriteNotFound) {
      return null;
    }
    return Settings.data.wallpaper.favorites[idx];
  }

  // -------------------------------------------------------------------
  function toggleFavorite(path, appearanceSlot, screenName) {
    var slot;
    if (appearanceSlot !== undefined && appearanceSlot !== null && appearanceSlot !== "") {
      slot = _normalizeAppearanceSlot(appearanceSlot);
    } else {
      slot = _normalizeAppearanceSlot(root.wallpaperSelectionAppearance);
    }
    var index = _findAnyFavoriteIndexForPath(path);
    var entry = index === _favoriteNotFound ? null : Settings.data.wallpaper.favorites[index];
    var selectsWallpaper = !entry || (Settings.data.wallpaper.linkLightAndDarkWallpapers && _favoriteAppearanceSlot(entry) !== slot);
    if (!selectsWallpaper) {
      _removeFavorite(path, index);
      return null;
    }
    var scr = Settings.data.wallpaper.setWallpaperOnAllMonitors ? undefined : (screenName || (Quickshell.screens.length ? Quickshell.screens[0].name : undefined));
    return changeWallpaper(path, scr, slot, function (success, names) {
      if (!success)
        return;
      root._commitFavorite(path, slot);
      names.forEach(name => root.applyFavoriteTheme(path, name, slot));
    });
  }

  function _removeFavorite(path, index) {
    var favorites = Settings.data.wallpaper.favorites.slice();
    favorites.splice(index, 1);
    Logger.d("Wallpaper", "Removed favorite:", path);
    if (favoriteSchemeDebounceTimer.pendingPath === path) {
      favoriteSchemeDebounceTimer.stop();
      favoriteSchemeDebounceTimer.pendingPath = "";
      favoriteSchemeDebounceTimer.pendingSlot = "";
    }
    if (root.pendingFavoriteSchemeRefresh && root.pendingFavoriteSchemeRefresh.path === path)
      root.pendingFavoriteSchemeRefresh = null;
    _publishFavorites(favorites, path);
  }

  function _commitFavorite(path, slot) {
    var favorites = Settings.data.wallpaper.favorites.slice();
    var index = _findAnyFavoriteIndexForPath(path);
    if (index !== _favoriteNotFound && _favoriteAppearanceSlot(favorites[index]) === slot)
      return;
    if (index === _favoriteNotFound) {
      favorites.push(_createFavoriteEntry(path, slot));
      Logger.d("Wallpaper", "Added favorite:", path, slot);
    } else {
      favorites[index] = _createFavoriteEntry(path, slot);
      Logger.d("Wallpaper", "Moved favorite to other appearance:", path, slot);
      if (root.pendingFavoriteSchemeRefresh && root.pendingFavoriteSchemeRefresh.path === path)
        root.pendingFavoriteSchemeRefresh = {
          path: path,
          slot: slot
        };
    }
    root.scheduleFavoriteSchemeSnapshot(path, slot);
    _publishFavorites(favorites, path);
  }

  function _publishFavorites(favorites, path) {
    Settings.data.wallpaper.favorites = favorites;

    favoritesChanged(path);
  }

  // Apply saved scheme from a favorite. Optional appearanceSlotOverride sets light vs dark target (UI tab or system mode).
  function _applyFavoriteThemeFromEntry(favorite, appearanceSlotOverride) {
    if (!favorite) {
      return;
    }

    var favApp;
    if (appearanceSlotOverride !== undefined && appearanceSlotOverride !== null && appearanceSlotOverride !== "") {
      favApp = _normalizeAppearanceSlot(appearanceSlotOverride);
    } else {
      favApp = _favoriteAppearanceSlot(favorite);
    }
    var targetDark = favApp === "dark";

    var generationMethodChanging = Settings.data.colorSchemes.generationMethod !== favorite.generationMethod;
    var darkModeChanging = Settings.data.colorSchemes.darkMode !== targetDark;
    var useWallpaperColorsChanging = Settings.data.colorSchemes.useWallpaperColors !== favorite.useWallpaperColors;

    Settings.data.colorSchemes.useWallpaperColors = favorite.useWallpaperColors;
    Settings.data.colorSchemes.predefinedScheme = favorite.colorScheme;
    Settings.data.colorSchemes.generationMethod = favorite.generationMethod;
    Settings.data.colorSchemes.darkMode = targetDark;

    // If nothing triggered AppThemeService via change handlers, regenerate once.
    if (!generationMethodChanging && !darkModeChanging && !useWallpaperColorsChanging) {
      AppThemeService.generate();
    } else if (!generationMethodChanging && !darkModeChanging && useWallpaperColorsChanging) {
      AppThemeService.generate();
    }
  }

  // When light/dark changes (or on startup), re-load scheme from the favorite for the wallpaper now shown for that slot.
  function reapplyFavoriteThemeForActiveWallpaper() {
    var effectiveMonitor = Settings.data.colorSchemes.monitorForColors;
    if (effectiveMonitor === "" || effectiveMonitor === undefined) {
      effectiveMonitor = Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }
    var wp = getWallpaper(effectiveMonitor);
    if (!wp || isSolidColorPath(wp)) {
      return;
    }
    var slot = Settings.data.colorSchemes.darkMode ? "dark" : "light";
    var favorite = favoriteEntryForPath(wp);
    if (!favorite) {
      return;
    }
    _applyFavoriteThemeFromEntry(favorite, slot);
  }

  // -------------------------------------------------------------------
  function applyFavoriteTheme(path, screenName, appearanceSlot) {
    // Only apply theme if the wallpaper is on the monitor driving colors
    var effectiveMonitor = Settings.data.colorSchemes.monitorForColors;
    if (effectiveMonitor === "" || effectiveMonitor === undefined) {
      effectiveMonitor = Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }
    if (screenName !== undefined && screenName !== effectiveMonitor) {
      return;
    }

    var slot;
    if (appearanceSlot !== undefined && appearanceSlot !== null && appearanceSlot !== "") {
      slot = _normalizeAppearanceSlot(appearanceSlot);
    } else {
      slot = _normalizeAppearanceSlot(root.wallpaperSelectionAppearance);
    }
    var favorite = favoriteEntryForPath(path);
    if (!favorite) {
      return;
    }

    var schemeSlot = slot;
    if (Settings.data.wallpaper.linkLightAndDarkWallpapers) {
      schemeSlot = _favoriteAppearanceSlot(favorite);
    }
    _applyFavoriteThemeFromEntry(favorite, schemeSlot);
  }

  // -------------------------------------------------------------------
  function updateFavoriteColorScheme(path, appearanceSlot) {
    var slot = _normalizeAppearanceSlot(appearanceSlot);
    var existingIndex = _findFavoriteIndex(path, slot);
    if (existingIndex === _favoriteNotFound) {
      return;
    }

    var favorites = Settings.data.wallpaper.favorites.slice();
    favorites[existingIndex] = _createFavoriteEntry(favorites[existingIndex].path, slot);
    Settings.data.wallpaper.favorites = favorites;
    Logger.d("Wallpaper", "Updated color scheme for favorite:", path, slot);
  }

  signal favoritesChanged(string path)

  // Auto-update favorite palette colors when theme colors finish transitioning
  Connections {
    target: AtmoColor
    function onIsTransitioningChanged() {
      if (!AtmoColor.isTransitioning) {
        _updateCurrentWallpaperFavorites();
      }
    }
  }

  function _updateCurrentWallpaperFavorites() {
    var effectiveMonitor = Settings.data.colorSchemes.monitorForColors;
    if (effectiveMonitor === "" || effectiveMonitor === undefined) {
      effectiveMonitor = Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }
    var wp = getWallpaper(effectiveMonitor);
    if (!wp) {
      return;
    }
    var favIdx = _findAnyFavoriteIndexForPath(wp);
    if (favIdx === _favoriteNotFound) {
      return;
    }
    var app = _favoriteAppearanceSlot(Settings.data.wallpaper.favorites[favIdx]);
    updateFavoriteColorScheme(wp, app);
  }

  // -------------------------------------------------------------------
  // -------------------------------------------------------------------
  // -------------------------------------------------------------------
  Timer {
    id: randomWallpaperTimer
    interval: Settings.data.wallpaper.randomIntervalSec * 1000
    running: Settings.data.wallpaper.automationEnabled && !PowerProfileService.atmospheraPerformanceMode
    repeat: true
    onTriggered: setNextWallpaper(true)
    triggeredOnStart: false
  }

  // -------------------------------------------------------------------
  // Cache file persistence
  // -------------------------------------------------------------------
  FileView {
    id: wallpaperCacheView
    printErrors: false
    watchChanges: false

    adapter: JsonAdapter {
      id: wallpaperCacheAdapter
      property var wallpapers: ({})
      property string defaultWallpaper: ""
      property var usedRandomWallpapers: ({})
    }

    onLoaded: {
      // Load wallpapers from cache file
      root.currentWallpapers = wallpaperCacheAdapter.wallpapers || {};
      root.usedRandomWallpapers = wallpaperCacheAdapter.usedRandomWallpapers || {};

      root._ensureObjectWallpaperEntries();

      if (Settings.data.wallpaper.linkLightAndDarkWallpapers) {
        root.wallpaperSelectionAppearance = Settings.data.colorSchemes.darkMode ? "dark" : "light";
        root._syncWallpaperSlotsWhenLinking();
      }

      // Load default wallpaper from cache if it exists, otherwise use the bundled default
      if (wallpaperCacheAdapter.defaultWallpaper && wallpaperCacheAdapter.defaultWallpaper !== "") {
        root.defaultWallpaper = wallpaperCacheAdapter.defaultWallpaper;
        Logger.d("Wallpaper", "Loaded default wallpaper from cache:", wallpaperCacheAdapter.defaultWallpaper);
      } else {
        root.defaultWallpaper = "";
        Logger.d("Wallpaper", "No default wallpaper set");
      }

      Logger.d("Wallpaper", "Loaded wallpapers from cache file:", Object.keys(root.currentWallpapers).length, "screens");
      root.isInitialized = true;
      root._scheduleThemeSyncFromCachedWallpaper();
    }

    onLoadFailed: error => {
      // File doesn't exist yet or failed to load - initialize with empty state
      root.currentWallpapers = {};
      Logger.d("Wallpaper", "Cache file doesn't exist or failed to load, starting with empty wallpapers");
      root.isInitialized = true;
      root._scheduleThemeSyncFromCachedWallpaper();
    }
  }

  Timer {
    id: saveTimer
    interval: 500
    repeat: false
    onTriggered: {
      wallpaperCacheAdapter.wallpapers = root.currentWallpapers;
      wallpaperCacheAdapter.defaultWallpaper = root.defaultWallpaper;
      wallpaperCacheAdapter.usedRandomWallpapers = root.usedRandomWallpapers;
      wallpaperCacheView.writeAdapter();
      Logger.d("Wallpaper", "Saved wallpapers to cache file");
    }
  }
}
