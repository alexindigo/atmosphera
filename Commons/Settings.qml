pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../Helpers/OwnedProcess.js" as OwnedProcess
import "../Helpers/QtObj2JS.js" as QtObj2JS
import "../Helpers/SettingsModel.js" as SettingsModel
import qs.Commons
import qs.Commons.Migrations
import qs.Modules.OSD
import qs.Services.Plugins
import qs.Services.UI

Singleton {
  id: root

  property bool isLoaded: false
  property bool reloadSettings: false
  property bool directoriesCreated: false
  property bool shouldOpenSetupWizard: false
  property bool isFreshInstall: false

  /*
  Shell directories.
  - Default config directory: ~/.config/atmosphera
  - Default cache directory: ~/.cache/atmosphera
  */
  readonly property alias data: settingsAdapter  // Used to access via Settings.data.xxx.yyy
  readonly property int settingsVersion: 60
  property bool isDebug: Quickshell.env("ATMOSPHERA_DEBUG") === "1"
  readonly property string shellName: "atmosphera"
  readonly property string configDir: ensureTrailingSlash(Quickshell.env("ATMOSPHERA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/" + shellName + "/")
  readonly property string cacheDir: ensureTrailingSlash(Quickshell.env("ATMOSPHERA_CACHE_DIR") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/" + shellName + "/")

  readonly property string settingsFile: Quickshell.env("ATMOSPHERA_SETTINGS_FILE") || (configDir + "settings.json")
  readonly property string defaultAvatar: Quickshell.env("HOME") + "/.face"
  readonly property string defaultVideosDirectory: Quickshell.env("HOME") + "/Videos"
  readonly property string defaultWallpapersDirectory: Quickshell.env("HOME") + "/Pictures/Wallpapers"

  signal settingsLoaded
  signal settingsSaved
  signal settingsSaveFailed(string message)
  signal settingsReloaded
  signal settingExternallyChanged(string path)
  signal bindingsEnvironmentRequested(string environment)
  signal effectiveSettingsChanged(string section)

  // The typed QObject graph and transports live here. SettingsModel owns all
  // acceptance/capture/attempt bookkeeping behind its transition entrance.
  readonly property string _persistSession: Date.now() + "-" + Math.random().toString(16).substring(2)
  readonly property string sectionIoHelper: Quickshell.shellDir + "/Scripts/python/src/settings/section-io.py"
  readonly property var _model: SettingsModel.create({
                                                       "settingsFile": root.settingsFile,
                                                       "overridesDir": root.overridesDir,
                                                       "cacheDir": root.cacheDir,
                                                       "session": root._persistSession
                                                     })
  property int _modelRevision: 0
  property int _bridgeDepth: 0
  property int _callbackSerial: 0
  property var _callbacks: ({})

  function _queryModel(name, args) {
    void root._modelRevision;
    return root._model.query(name, args);
  }

  function _inspectModel() {
    return root._model.inspect();
  }

  function _registerCallback(callback) {
    if (typeof callback !== "function")
      return null;
    var token = "callback-" + (++root._callbackSerial);
    root._callbacks[token] = callback;
    return token;
  }

  function _takeCallback(token) {
    var callback = root._callbacks[token];
    delete root._callbacks[token];
    return callback;
  }

  function _dispatchModel(event) {
    // Every boundary observes the actual QObject, including synchronous
    // listeners and opaque edits. The owner never holds an adapter reference.
    event.current = QtObj2JS.qtObjectToPlainObject(settingsAdapter);
    root._bridgeDepth++;
    try {
      var result = root._model.transition(event);
      root._modelRevision++;
      for (var i = 0; i < result.orderedEffects.length; i++)
        root._executeModelEffect(result.orderedEffects[i]);
      return result.returnValue;
    } finally {
      root._bridgeDepth--;
      if (root._bridgeDepth === 0 && (event.type !== "pump" || root._queryModel("pumpReady")))
        root._dispatchModel({
                              "type": "pump"
                            });
    }
  }

  function _executeModelEffect(effect) {
    if (effect.kind === "log") {
      if (effect.level === "w")
        Logger.w("Settings", effect.message, effect.path);
      else
        Logger.e("Settings", effect.message, effect.path);
    } else if (effect.kind === "io") {
      root._runModelIo(effect);
    } else if (effect.kind === "reload") {
      var view = effect.section === "legacy" ? settingsFileView : root._sectionViews[effect.section];
      if (view)
        view.reload();
      else
        root.finishObservedRead(effect.section);
    } else if (effect.kind === "effective") {
      try {
        for (var si = 0; si < effect.sections.length; si++)
          root.effectiveSettingsChanged(effect.sections[si]);
      } finally {
        root._dispatchModel({
                              "type": "effectiveDelivered"
                            });
      }
    } else if (effect.kind === "observed") {
      try {
        var notification;
        while ((notification = root._dispatchModel({
                                                     "type": "observedNext"
                                                   })) !== null) {
          if (notification.kind === "environment")
            root.bindingsEnvironmentRequested(notification.value);
          else if (notification.kind === "changed")
            root.settingExternallyChanged(notification.value);
          else
            root.settingsReloaded();
        }
      } finally {
        root._dispatchModel({
                              "type": "observedDelivered"
                            });
      }
    } else if (effect.kind === "observation") {
      var paths = root._dispatchModel({
                                        "type": "observationBegin",
                                        "token": effect.token
                                      });
      try {
        for (var pi = 0; pi < paths.length; pi++)
          root._dispatchModel({
                                "type": "observationLeaf",
                                "token": effect.token,
                                "path": paths[pi]
                              });
      } finally {
        root._dispatchModel({
                              "type": "observationEnd",
                              "token": effect.token
                            });
      }
    } else if (effect.kind === "applyValue") {
      root.applyObservedValue(effect.path, effect.value);
    } else if (effect.kind === "readNext") {
      root._dispatchModel({
                            "type": "readNext",
                            "token": effect.token
                          });
    } else if (effect.kind === "readCallback") {
      var callback = root._takeCallback(effect.callbackToken), failed = false;
      try {
        if (typeof callback === "function")
          callback(effect.success, effect.state, effect.error);
      } catch (exception) {
        failed = true;
      } finally {
        root._dispatchModel({
                              "type": "readNext",
                              "token": effect.token,
                              "callbackError": failed
                            });
      }
    } else if (effect.kind === "saveDelivery") {
      // Detach the old callback before signals can reenter an empty save.
      var callback = root._takeCallback(effect.callbackToken);
      var notification = root._dispatchModel({
                                               "type": "saveDeliveryBegin",
                                               "token": effect.token
                                             });
      try {
        if (notification === "failed")
          root.settingsSaveFailed(effect.error);
        else if (notification === "saved")
          root.settingsSaved();
        if (typeof callback === "function") {
          try {
            callback(effect.success, effect.error);
          } catch (exception) {
            Logger.e("Settings", "Save completion callback failed");
          }
        }
      } finally {
        root._dispatchModel({
                              "type": "saveDelivered",
                              "token": effect.token
                            });
      }
    } else if (effect.kind === "saveFailed") {
      root.settingsSaveFailed(effect.error);
    } else {
      throw new Error("Unknown Settings effect: " + effect.kind);
    }
  }

  function _runModelIo(effect) {
    var token = effect.token;
    var owner = effect.owner;
    var command = ["python3", root.sectionIoHelper, root.filePathFor(effect.section)];
    command.splice(2, 0, effect.mode);
    if (effect.temporary)
      command.push(effect.temporary);
    OwnedProcess.run(root, command, effect.input === undefined ? null : JSON.stringify(effect.input), function (result) {
      var payload = null;
      try {
        payload = JSON.parse(result.stdout);
      } catch (ignored) {}
      root._dispatchModel({
                            "type": "ioCompleted",
                            "token": token,
                            "owner": owner,
                            "success": result.success && payload && payload.ok === true,
                            "payload": payload,
                            "error": payload && payload.error ? payload.error : result.error
                          });
    });
  }

  function beginManagedBindings() {
    root._dispatchModel({
                          "type": "managed"
                        });
  }

  function setBindingsUnresolved(unresolved) {
    root._dispatchModel({
                          "type": "unresolved",
                          "value": unresolved
                        });
  }

  // Runtime invalidation is independent of the capture/durable baselines.
  function notifyEffectiveChanges() {
    root._dispatchModel({
                          "type": "effective"
                        });
  }

  function finishCapture() {
    root._dispatchModel({
                          "type": "captureEnd"
                        });
  }

  // Debounce external reload requests (file watcher + directory watcher)
  // so atomic replacements only trigger one reload.
  Timer {
    id: externalReloadTimer
    running: false
    interval: 200
    onTriggered: {
      if (settingsFileView.path !== undefined) {
        Logger.d("Settings", "Reloading settings after external change detection");
        reloadSettings = true;
        settingsFileView.reload();
      }
    }
  }

  function scheduleExternalReload() {
    if (!directoriesCreated || settingsFileView.path === undefined) {
      return;
    }
    // Suppress feedback from our own override writes (tmp+mv shows up as a
    // file change); genuine external edits still reload after the window.
    // Owned writes are reconciled by confirmed content/identity. A watcher
    // event is never dropped because it falls inside a timing window.
    externalReloadTimer.restart();
  }

  // -----------------------------------------------------
  // -----------------------------------------------------
  // Ensure directories exist before FileView tries to read files
  Component.onCompleted: {
    // ensure settings dirs exist
    Quickshell.execDetached(["mkdir", "-p", configDir]);
    Quickshell.execDetached(["mkdir", "-p", overridesDir]);
    Quickshell.execDetached(["mkdir", "-p", cacheDir]);

    // This should only be activated once when the settings structure has changed
    // Then it should be commented out again, regular users don't need to generate
    // default settings on every start
    if (isDebug) {
      generateDefaultSettings();
      generateWidgetDefaultSettings();
    }

    // Patch-in the local default, resolved to user's home
    settingsAdapter.general.avatarImage = defaultAvatar;
    settingsAdapter.wallpaper.directory = defaultWallpapersDirectory;
    settingsAdapter.ui.fontDefault = Qt.application.font.family;
    settingsAdapter.ui.fontFixed = "monospace";

    // Sections = settingsAdapter root keys (minus the version marker)
    var plain = QtObj2JS.qtObjectToPlainObject(settingsAdapter);
    // The same serialization is the adapter-derived settings structure used
    // to recognize declared setting paths (own properties only — QObject
    // bookkeeping and prototype names are not settings).
    root._dispatchModel({
                          "type": "schema",
                          "schema": plain
                        });
    var keys = [];
    for (var k in plain) {
      if (k !== "settingsVersion") {
        keys.push(k);
        sectionsModel.append({
                               "name": k
                             });
      }
    }

    // Mark directories as created and trigger the legacy file load; section
    // files load after the legacy layer lands (they take precedence).
    directoriesCreated = true;

    // Attach the adapter only to the path-less update watch (save trigger).
    // The legacy FileView stays text-mode: all file->adapter application
    // flows through the manual layer-ordered path below, so the invariant
    // section > legacy > schema holds identically at startup and on reload.
    adapterUpdateWatch.adapter = settingsAdapter;
  }

  // Don't write settings to disk immediately
  // This avoid excessive IO when a variable changes rapidly (ex: sliders)
  Timer {
    id: saveTimer
    running: false
    interval: 500
    onTriggered: {
      root.saveImmediate(undefined, true);
    }
  }

  // Change-notification-only adapter attachment: forwards adapter updates
  // to the save debounce. It has no path and never loads, so it applies
  // nothing — the manual layer-ordered path is the single applicator.
  FileView {
    id: adapterUpdateWatch
    printErrors: false
    watchChanges: false
    onAdapterUpdated: {
      root.notifyEffectiveChanges();
      saveTimer.start();
    }
  }

  FileView {
    id: settingsFileView
    path: directoriesCreated ? settingsFile : undefined
    printErrors: false
    watchChanges: true

    onFileChanged: scheduleExternalReload()

    // Trigger initial load when path changes from empty to actual path
    onPathChanged: {
      if (path !== undefined) {
        reload();
      }
    }
    onLoaded: function () {
      if (!isLoaded) {
        Logger.i("Settings", "Legacy settings file loaded");

        // Load raw JSON for migrations (settingsAdapter doesn't expose removed properties)
        var rawJson = null;
        try {
          rawJson = JSON.parse(settingsFileView.text());
        } catch (e) {
          Logger.w("Settings", "Could not parse raw JSON for migrations");
        }

        // Single applicator: the legacy layer applies through the same
        // schema-aware manual path as the section files (unknown keys warn
        // and are skipped). Section files load next and keep precedence —
        // no precedence-blind native application runs ahead of the layering.
        if (rawJson) {
          deepApply(settingsAdapter, rawJson, "");
        }

        // Run versioned migrations immediately, don't move it in upgradeSettings
        runVersionedMigrations(rawJson);

        // Finally, update our local settings version
        settingsAdapter.settingsVersion = settingsVersion;

        // The legacy monolith is the bottom override layer: adopted as-is,
        // never rewritten. Section files (settings/<section>.json) load on
        // top of it next and take precedence.
        root._dispatchModel({
                              "type": "initialFile",
                              "section": "legacy",
                              "raw": settingsFileView.text(),
                              "exists": true,
                              "data": rawJson || {},
                              "sawFile": true
                            });

        beginSectionLoads();
      } else {
        // The helper supplies existence and full identity before acceptance;
        // FileView text alone must not publish a partially settled choice.
        root.finishObservedRead("legacy");
      }
    }
    onLoadFailed: function (error) {
      if (reloadSettings) {
        reloadSettings = false;
        if (root.isLoaded)
          root.finishObservedRead("legacy", error);
        return;
      }
      if (error.toString().includes("No such file") || error === 2) {
        if (root.isLoaded) {
          root.finishObservedRead("legacy", error);
          return;
        }
        // No legacy monolith — normal for fresh installs and post-split
        // setups. Section files load next; freshness is decided there.
        root._dispatchModel({
                              "type": "initialFile",
                              "section": "legacy",
                              "raw": "",
                              "exists": false,
                              "data": {}
                            });
        settingsAdapter.settingsVersion = settingsVersion;
        beginSectionLoads();
      }
    }
  }

  // -----------------------------------------------------
  // Section override files: <configDir>/settings/<section>.json, one per
  // settingsAdapter root key. Text-mode FileViews (no settingsAdapter attachment — the
  // legacy view owns the root settingsAdapter); applied manually via deepApply.
  // The model is gated on sectionsReady so delegates are created only
  // after the legacy layer lands (section files take precedence).
  ListModel {
    id: sectionsModel
  }

  Instantiator {
    model: root.sectionsReady ? sectionsModel : []

    delegate: FileView {
      id: sectionView

      // `required` makes the Instantiator assign the role before component
      // completion — without it, delegate-declared bindings evaluate too
      // early and see undefined (verified against DankMaterialShell /
      // caelestia delegate patterns).
      required property string name
      property string section: name

      path: root.overridesDir + name + ".json"
      printErrors: false
      watchChanges: true

      Component.onCompleted: {
        root._sectionViews[name] = sectionView;
      }

      onPathChanged: {
        if (path !== undefined) {
          reload();
        }
      }

      onFileChanged: {
        reload();
      }

      onLoaded: function () {
        var parsed = null;
        try {
          parsed = JSON.parse(sectionView.text());
        } catch (e) {
          Logger.w("Settings", "Corrupt section file, using defaults for: " + section);
        }

        if (!root.isLoaded) {
          root._dispatchModel({
                                "type": "initialFile",
                                "section": section,
                                "raw": sectionView.text(),
                                "exists": true,
                                "data": parsed || {},
                                "sawFile": !!parsed
                              });
          if (parsed) {
            deepApply(settingsAdapter[section], parsed, section);
          }
          root.sectionSettled();
        } else {
          // Accept the helper's coherent raw/existence/identity observation.
          root.finishObservedRead(section);
        }
      }

      onLoadFailed: function (error) {
        if (!root.isLoaded) {
          root._dispatchModel({
                                "type": "initialFile",
                                "section": section,
                                "raw": "",
                                "exists": false,
                                "data": {}
                              });
          root.sectionSettled();
        } else {
          root.finishObservedRead(section, error);
        }
      }
    }
  }

  // Trigger section file loads once the legacy layer has landed
  function beginSectionLoads() {
    if (root._sections.length === 0) {
      finishLoad();
      return;
    }
    root.sectionsReady = true;
  }

  // Called by each section FileView when its initial read settles
  function sectionSettled() {
    root._sectionsSettled++;
    if (root._sectionsSettled >= root._sections.length) {
      finishLoad();
    }
  }

  // All layers have landed: baseline and go live
  function finishLoad() {
    if (root.isLoaded) {
      return;
    }
    root._dispatchModel({
                          "type": "loaded"
                        });
    root.isLoaded = true;
    root.settingsLoaded();
    upgradeSettings();

    if (!root._queryModel("sawFile")) {
      // No legacy file, no section files: genuine first start
      root.isFreshInstall = true;
      root.shouldOpenSetupWizard = true;
    }
  }

  // Baseline the detached intended leaf at the assignment boundary. Synchronous
  // property listeners may then capture a different local value, including a save.
  function applyObservedValue(fullPath, value) {
    var prepared = root._dispatchModel({
                                         "type": "leafPrepare",
                                         "path": fullPath,
                                         "value": value
                                       });
    if (!prepared)
      return;
    if (prepared.children) {
      for (var i = 0; i < prepared.children.length; i++)
        root.applyObservedValue(prepared.children[i].path, prepared.children[i].value);
      return;
    }
    var applied = false;
    try {
      applied = root.setPathValue(settingsAdapter, fullPath, prepared.value, "");
    } finally {
      root._dispatchModel({
                            "type": "leafAssigned",
                            "token": prepared.token,
                            "applied": applied
                          });
    }
  }

  // Watch parent config directory as a fallback for declarative setups where
  // settings.json may be replaced atomically (e.g., symlink/store-path swap).
  FileView {
    id: settingsDirWatcher
    path: directoriesCreated ? configDir : undefined
    printErrors: false
    watchChanges: true
    onFileChanged: scheduleExternalReload()
  }

  // Watch the settings/ directory for the same reason (section files swapped
  // atomically). Section reloads are content-gated, so noise is harmless.
  FileView {
    id: overridesDirWatcher
    path: directoriesCreated ? overridesDir : undefined
    printErrors: false
    watchChanges: true
    onFileChanged: {
      for (var i = 0; i < root._sections.length; i++) {
        var view = root._sectionViews[root._sections[i]];
        if (view && view.path !== undefined) {
          view.reload();
        }
      }
    }
  }

  // FileView to load default settings for comparison
  FileView {
    id: defaultSettingsFileView
    path: Quickshell.shellDir + "/Configs/defaults.json"
    printErrors: false
    watchChanges: false
  }

  // Per-panel (per-section) override layout:
  //   <configDir>/settings/<section>.json   — sparse user overrides per panel
  //   <configDir>/settings.json             — legacy monolith, bottom layer,
  //                                           adopted as-is, never rewritten
  // Precedence: section file > legacy file > schema defaults.
  readonly property string overridesDir: configDir + "settings/"

  // Detached topology projection and actual QObject view/lifecycle ownership.
  readonly property var _sections: root._queryModel("sections")
  property bool sectionsReady: false
  property int _sectionsSettled: 0
  property var _sectionViews: ({})

  // Load default settings when file is loaded
  Connections {
    target: defaultSettingsFileView
    function onLoaded() {
      try {
        root._dispatchModel({
                              "type": "defaults",
                              "value": JSON.parse(defaultSettingsFileView.text())
                            });
      } catch (e) {
        Logger.w("Settings", "Failed to parse default settings file: " + e);
        root._dispatchModel({
                              "type": "defaults",
                              "value": null
                            });
      }
    }
  }

  JsonAdapter {
    id: settingsAdapter

    property int settingsVersion: 0

    // bar
    property JsonObject bar: JsonObject {
      property string barType: "framed" // "simple", "floating", "framed"
      property string position: "top" // "top", "bottom", "left", or "right"
      property list<string> monitors: [] // holds bar visibility per monitor
      property string density: "default" // "compact", "default", "comfortable"
      property bool showOutline: false
      property bool showCapsule: false
      property real capsuleOpacity: 0.70
      property string capsuleColorKey: "none"
      property int widgetSpacing: 6
      property int contentPadding: 2
      property real fontScale: 1.0
      property bool enableExclusionZoneInset: true

      // Bar background opacity settings
      property real backgroundOpacity: 0.70
      property bool useSeparateOpacity: false

      // Floating bar settings
      property int marginVertical: 4
      property int marginHorizontal: 4

      // Framed bar settings
      property int frameThickness: 8
      property int frameRadius: 12

      // Bar outer corners (inverted/concave corners at bar edges when not floating)
      property bool outerCorners: true

      // Hide bar/panels when compositor overview is active
      property bool hideOnOverview: false

      // Auto-hide settings
      property string displayMode: "always_visible"
      property int autoHideDelay: 500 // ms before hiding after mouse leaves
      property int autoShowDelay: 150 // ms before showing when mouse enters
      property bool showOnWorkspaceSwitch: true // show bar briefly on workspace switch

      // Widget configuration for modular bar system
      property JsonObject widgets
      widgets: JsonObject {
        property list<var> left: [
          {
            "id": "Launcher"
          },
          {
            "id": "Clock"
          },
          {
            "id": "SystemMonitor"
          },
          {
            "id": "ActiveWindow"
          },
          {
            "id": "MediaMini"
          }
        ]
        property list<var> center: [
          {
            "id": "Workspace"
          }
        ]
        property list<var> right: [
          {
            "id": "Tray"
          },
          {
            "id": "NotificationHistory"
          },
          {
            "id": "Battery"
          },
          {
            "id": "Volume"
          },
          {
            "id": "Brightness"
          },
          {
            "id": "ControlCenter"
          }
        ]
      }
      property string mouseWheelAction: "none"
      property bool reverseScroll: false
      property bool mouseWheelWrap: true
      property string middleClickAction: "none"
      property bool middleClickFollowMouse: false
      property string middleClickCommand: ""
      property string rightClickAction: "controlCenter"
      property bool rightClickFollowMouse: true
      property string rightClickCommand: ""
      // Per-screen overrides for position and widgets
      // Format: [{ "name": "HDMI-1", "position": "left" }, { "name": "DP-1", "position": "bottom", "widgets": {...} }]
      property list<var> screenOverrides: []
    }

    // general
    property JsonObject general: JsonObject {
      property string avatarImage: ""
      property real dimmerOpacity: 0.2
      property bool showScreenCorners: false
      property bool forceBlackScreenCorners: false
      property real scaleRatio: 1.0
      property real radiusRatio: 1.0
      property real iRadiusRatio: 1.0
      property real boxRadiusRatio: 1.0
      property real screenRadiusRatio: 1.0
      property real animationSpeed: 1.0
      property bool animationDisabled: false
      property bool compactLockScreen: false
      property bool lockScreenAnimations: false
      property bool lockOnSuspend: true
      property bool showSessionButtonsOnLockScreen: true
      property bool showHibernateOnLockScreen: false
      property bool enableLockScreenMediaControls: false
      property bool enableShadows: true
      property bool enableBlurBehind: true
      property string shadowDirection: "bottom_right"
      property int shadowOffsetX: 2
      property int shadowOffsetY: 3
      property string language: ""
      property bool allowPanelsOnScreenWithoutBar: true
      property bool showChangelogOnStartup: true
      property bool enableLockScreenCountdown: true
      property int lockScreenCountdownDuration: 10000
      property bool autoStartAuth: false
      property bool allowPasswordWithFprintd: false
      property string clockStyle: "custom"
      property string clockFormat: "HH:mm"
      property bool passwordChars: false
      property list<string> lockScreenMonitors: [] // holds lock screen visibility per monitor
      property string lockScreenPlugin: "" // plugin ID for custom lock screen UI, empty = default
      property bool lockScreenEnabled: true // false = no lock actuation anywhere (idle, manual, suspend prep)
      property real lockScreenBlur: 0.0
      property real lockScreenTint: 0.0
      property string externalLockCommand: ""   // standalone locker command — spawned detached in "external" plugin mode (swaylock-style) and in "service" mode (contract locker binary, spawned on demand)
      property JsonObject keybinds: JsonObject {
        property list<string> keyUp: ["Up"]
        property list<string> keyDown: ["Down"]
        property list<string> keyLeft: ["Left"]
        property list<string> keyRight: ["Right"]
        property list<string> keyEnter: ["Return", "Enter"]
        property list<string> keyEscape: ["Esc"]
        property list<string> keyRemove: ["Del"]
      }
      property bool reverseScroll: false
      property bool smoothScrollEnabled: true
    }

    // bindings
    property JsonObject bindings: JsonObject {
      // Which shortcut environment to apply. "none" leaves the system untouched.
      // Values: "none" | "macos"  (future: "windows", "kde")
      property string environment: "none"
    }

    // ui
    property JsonObject ui: JsonObject {
      property string fontDefault: ""
      property string fontFixed: ""
      property real fontDefaultScale: 1.0
      property real fontFixedScale: 1.0
      property bool tooltipsEnabled: true
      property bool scrollbarAlwaysVisible: true
      property bool boxBorderEnabled: false
      property real panelBackgroundOpacity: 0.55
      property bool translucentWidgets: false
      property bool panelsAttachedToBar: true
      property string settingsPanelMode: "attached" // "centered", "attached", "window"
      property bool settingsPanelSideBarCardStyle: false
    }

    // location
    property JsonObject location: JsonObject {
      property string name: ""
      property bool weatherEnabled: true
      property bool weatherShowEffects: true
      property bool weatherTaliaMascotAlways: false
      property bool useFahrenheit: false
      property bool use12hourFormat: false
      property bool showWeekNumberInCalendar: false
      property bool showCalendarEvents: true
      property bool showCalendarWeather: true
      property bool analogClockInCalendar: false
      property int firstDayOfWeek: -1 // -1 = auto (use locale), 0 = Sunday, 1 = Monday, 6 = Saturday
      property bool hideWeatherTimezone: false
      property bool hideWeatherCityName: false
      property bool autoLocate: false
    }

    // calendar
    property JsonObject calendar: JsonObject {
      property list<var> cards: [
        {
          "id": "calendar-header-card",
          "enabled": true
        },
        {
          "id": "calendar-month-card",
          "enabled": true
        },
        {
          "id": "weather-card",
          "enabled": true
        }
      ]
    }

    // wallpaper
    property JsonObject wallpaper: JsonObject {
      property bool enabled: true
      property bool overviewEnabled: true
      property string directory: ""
      property list<var> monitorDirectories: []
      property bool enableMultiMonitorDirectories: false
      property bool showHiddenFiles: false
      property string viewMode: "browse" // "single" | "recursive" | "browse"
      property bool setWallpaperOnAllMonitors: true
      property bool linkLightAndDarkWallpapers: true
      property string fillMode: "crop"
      property color fillColor: "#000000"
      property bool useSolidColor: false
      property color solidColor: "#1a1a2e"
      property bool automationEnabled: false
      property string wallpaperChangeMode: "random" // "random" or "alphabetical"
      property int randomIntervalSec: 300 // 5 min
      property int transitionDuration: 1500 // 1500 ms
      property list<string> transitionType: ["fade", "disc", "stripes", "wipe", "pixelate", "honeycomb"]
      property bool skipStartupTransition: false
      property real transitionEdgeSmoothness: 0.05
      property string panelPosition: "follow_bar"
      property bool hideWallpaperFilenames: false
      property bool useOriginalImages: false
      property real overviewBlur: 0.4
      property real overviewTint: 0.6
      // Wallhaven settings
      property bool useWallhaven: false
      property string wallhavenQuery: ""
      property string wallhavenSorting: "relevance"
      property string wallhavenOrder: "desc"
      property string wallhavenCategories: "111" // general,anime,people
      property string wallhavenPurity: "100" // sfw only
      property string wallhavenRatios: ""
      property string wallhavenApiKey: ""
      property string wallhavenResolutionMode: "atleast" // "atleast" or "exact"
      property string wallhavenResolutionWidth: ""

      property string wallhavenResolutionHeight: ""
      property string sortOrder: "name" // "name", "name_desc", "date", "date_desc", "random"
      property list<var> monitorPools: []
      // Format: [{ "name": "eDP-1", "pools": [{ "id": "user:/path", "active": true, "rotate": true }] }]
      property list<var> favorites: []
      // Format: [{ "path": "...", "appearance": "light"|"dark", "colorScheme": "...", "darkMode": bool, "useWallpaperColors": bool, "generationMethod": "...", "paletteColors": [...] }]
      // Legacy entries omit "appearance" and use darkMode to infer light vs dark slot.
    }

    // applauncher
    property JsonObject appLauncher: JsonObject {
      property bool enableClipboardHistory: false
      property bool autoPasteClipboard: false
      property bool enableClipPreview: true
      property bool clipboardWrapText: true
      property bool enableClipboardSmartIcons: true
      property bool enableClipboardChips: true
      property string clipboardWatchTextCommand: "wl-paste --type text --watch cliphist store"
      property string clipboardWatchImageCommand: "wl-paste --type image --watch cliphist store"
      property string position: "center"  // Position: center, top_left, top_right, bottom_left, bottom_right, bottom_center, top_center
      property list<string> pinnedApps: []
      property bool sortByMostUsed: true
      property string terminalCommand: "alacritty -e"
      property bool customLaunchPrefixEnabled: false
      property string customLaunchPrefix: ""
      // View mode: "list" or "grid"
      property string viewMode: "list"
      property bool showCategories: true
      // Icon mode: "tabler" or "native"
      property string iconMode: "tabler"
      property bool showIconBackground: false
      property bool enableSettingsSearch: true
      property bool enableWindowsSearch: true
      property bool enableSessionSearch: true
      property bool ignoreMouseInput: false
      property string screenshotAnnotationTool: ""
      property bool overviewLayer: false
      property string density: "default" // "compact", "default", "comfortable"
    }

    // control center
    property JsonObject controlCenter: JsonObject {
      // Position: close_to_bar_button, center, top_left, top_right, bottom_left, bottom_right, bottom_center, top_center
      property string position: "close_to_bar_button"
      property string diskPath: "/"
      property JsonObject shortcuts
      shortcuts: JsonObject {
        property list<var> left: [
          {
            "id": "Network"
          },
          {
            "id": "Bluetooth"
          },
          {
            "id": "WallpaperSelector"
          },
          {
            "id": "AtmospheraPerformance"
          }
        ]
        property list<var> right: [
          {
            "id": "Notifications"
          },
          {
            "id": "PowerProfile"
          },
          {
            "id": "KeepAwake"
          },
          {
            "id": "NightLight"
          }
        ]
      }
      property list<var> cards: [
        {
          "id": "profile-card",
          "enabled": true
        },
        {
          "id": "shortcuts-card",
          "enabled": true
        },
        {
          "id": "audio-card",
          "enabled": true
        },
        {
          "id": "brightness-card",
          "enabled": false
        },
        {
          "id": "weather-card",
          "enabled": true
        },
        {
          "id": "media-sysmon-card",
          "enabled": true
        }
      ]
    }

    // system monitor
    property JsonObject systemMonitor: JsonObject {
      property int cpuWarningThreshold: 80
      property int cpuCriticalThreshold: 90
      property int tempWarningThreshold: 80
      property int tempCriticalThreshold: 90
      property int gpuWarningThreshold: 80
      property int gpuCriticalThreshold: 90
      property int memWarningThreshold: 80
      property int memCriticalThreshold: 90
      property int swapWarningThreshold: 80
      property int swapCriticalThreshold: 90
      property int diskWarningThreshold: 80
      property int diskCriticalThreshold: 90
      property int diskAvailWarningThreshold: 20
      property int diskAvailCriticalThreshold: 10
      property int batteryWarningThreshold: 20
      property int batteryCriticalThreshold: 5
      property bool enableDgpuMonitoring: false // Opt-in: reading dGPU sysfs/nvidia-smi wakes it from D3cold, draining battery
      property bool useCustomColors: false
      property string warningColor: ""
      property string criticalColor: ""
      property string externalMonitor: "resources || missioncenter || jdsystemmonitor || corestats || system-monitoring-center || gnome-system-monitor || plasma-systemmonitor || mate-system-monitor || ukui-system-monitor || deepin-system-monitor || pantheon-system-monitor"
    }

    // hardware health (thermal early-warning, unclean-shutdown notice, history log)
    property JsonObject hardwareHealth: JsonObject {
      property bool thermalWarnings: true
      property int warnOffsetC: 15
      property int sustainedPolls: 3
      property bool uncleanShutdownNotice: true
      property bool enableHistoryLog: true
    }

    // performance
    property JsonObject atmospheraPerformance: JsonObject {
      property bool disableWallpaper: true
      property bool disableDesktopWidgets: true
    }

    // dock
    property JsonObject dock: JsonObject {
      property bool enabled: true
      property string position: "bottom" // "top", "bottom", "left", "right"
      property string displayMode: "auto_hide" // "always_visible", "auto_hide", "exclusive"
      property string dockType: "floating" // "floating", "attached"
      property real backgroundOpacity: 1.0
      property real floatingRatio: 1.0
      property real size: 1
      property bool onlySameOutput: true
      property list<string> monitors: [] // holds dock visibility per monitor
      property list<string> pinnedApps: [] // Desktop entry IDs pinned to the dock (e.g., "org.kde.konsole", "firefox.desktop")
      property bool colorizeIcons: false
      property bool showLauncherIcon: false
      property string launcherPosition: "end" // "start", "end"
      property bool launcherUseDistroLogo: false
      property string launcherIcon: ""
      property string launcherIconColor: "none"
      property bool pinnedStatic: false
      property bool inactiveIndicators: false
      property bool groupApps: false
      property string groupContextMenuMode: "extended" // "list", "extended"
      property string groupClickAction: "cycle" // "cycle", "list"
      property string groupIndicatorStyle: "dots" // "number", "dots"
      property double deadOpacity: 0.6
      property real animationSpeed: 1.0 // Speed multiplier for hide/show animations (0.1 = slowest, 2.0 = fastest)
      property bool sitOnFrame: false
      property bool showDockIndicator: false
      property int indicatorThickness: 3
      property string indicatorColor: "primary"
      property real indicatorOpacity: 0.6
    }

    // network
    property JsonObject network: JsonObject {
      property bool bluetoothRssiPollingEnabled: false  // Opt-in Bluetooth RSSI polling (uses bluetoothctl)
      property int bluetoothRssiPollIntervalMs: 60000 // Polling interval in milliseconds for RSSI queries
      property string networkPanelView: "wifi"
      property string wifiDetailsViewMode: "grid"   // "grid" or "list"
      property string bluetoothDetailsViewMode: "grid" // "grid" or "list"
      property bool bluetoothHideUnnamedDevices: false
      property bool disableDiscoverability: false
      property bool bluetoothAutoConnect: true
    }

    // session menu
    property JsonObject sessionMenu: JsonObject {
      property bool enableCountdown: true
      property int countdownDuration: 10000
      property string position: "center"
      property bool showHeader: true
      property bool showKeybinds: true
      property bool largeButtonsStyle: true
      property string largeButtonsLayout: "single-row"
      property list<var> powerOptions: [
        {
          "action": "lock",
          "enabled": true,
          "keybind": "1"
        },
        {
          "action": "suspend",
          "enabled": true,
          "keybind": "2"
        },
        {
          "action": "hibernate",
          "enabled": true,
          "keybind": "3"
        },
        {
          "action": "reboot",
          "enabled": true,
          "keybind": "4"
        },
        {
          "action": "logout",
          "enabled": true,
          "keybind": "5"
        },
        {
          "action": "shutdown",
          "enabled": true,
          "keybind": "6"
        },
        {
          "action": "rebootToUefi",
          "enabled": true,
          "keybind": "7"
        }
      ]
      property bool useSharedOpacity: true
      property real backgroundOpacity: 0.93
    }

    // icons
    property JsonObject icons: JsonObject {
      property list<string> setOrder: []
    }

    // notifications
    property JsonObject notifications: JsonObject {
      property bool enabled: true
      property bool enableMarkdown: false
      property string density: "default" // "default", "compact"
      property list<string> monitors: [] // holds notifications visibility per monitor
      property string location: "top_right"
      property bool overlayLayer: true
      property real backgroundOpacity: 1.0
      property bool respectExpireTimeout: false
      property int lowUrgencyDuration: 3
      property int normalUrgencyDuration: 8
      property int criticalUrgencyDuration: 15
      property bool clearDismissed: true
      property JsonObject saveToHistory: JsonObject {
        property bool low: true
        property bool normal: true
        property bool critical: true
      }
      property JsonObject sounds: JsonObject {
        property bool enabled: false
        property real volume: 0.5
        property bool separateSounds: false
        property string criticalSoundFile: ""
        property string normalSoundFile: ""
        property string lowSoundFile: ""
        property string excludedApps: "discord,firefox,chrome,chromium,edge"
      }
      property bool enableMediaToast: false
      property bool enableKeyboardLayoutToast: true
      property bool enableBatteryToast: true
    }

    // on-screen display
    property JsonObject osd: JsonObject {
      property bool enabled: true
      property string location: "top_right"
      property int autoHideMs: 2000
      property bool overlayLayer: true
      property real backgroundOpacity: 1.0
      property list<var> enabledTypes: [OSD.Type.Volume, OSD.Type.InputVolume, OSD.Type.Brightness]
      property list<string> monitors: [] // holds osd visibility per monitor
    }

    // audio
    property JsonObject audio: JsonObject {
      property int volumeStep: 5
      property bool volumeOverdrive: false
      property int spectrumFrameRate: 30
      property string visualizerType: "linear"
      property bool spectrumMirrored: true
      property list<string> mprisBlacklist: []
      property string preferredPlayer: ""
      property bool volumeFeedback: false
      property string volumeFeedbackSoundFile: ""
    }

    // brightness
    property JsonObject brightness: JsonObject {
      property int brightnessStep: 5
      property bool enforceMinimum: true
      property bool enableDdcSupport: false
      property list<var> backlightDeviceMappings: []
      // Format: [{ "output": "eDP-1", "device": "/sys/class/backlight/intel_backlight" }]
    }

    property JsonObject colorSchemes: JsonObject {
      property bool useWallpaperColors: true
      property string predefinedScheme: "MacOS"
      property bool darkMode: true
      property string schedulingMode: "off"
      property string manualSunrise: "06:30"
      property string manualSunset: "18:30"
      property string generationMethod: "tonal-spot"
      property string monitorForColors: ""
      property bool syncGsettings: true
    }

    // templates toggles
    property JsonObject templates: JsonObject {
      property list<var> activeTemplates: []
      // Format: [{ "id": "gtk", "enabled": true }, { "id": "qt", "enabled": true }, ...]
      property bool enableUserTheming: false
    }

    // night light
    property JsonObject nightLight: JsonObject {
      property bool enabled: false
      property bool forced: false
      property bool autoSchedule: true
      property string nightTemp: "4000"
      property string dayTemp: "6500"
      property string manualSunrise: "06:30"
      property string manualSunset: "18:30"
    }

    // hooks
    property JsonObject hooks: JsonObject {
      property bool enabled: false
      property string wallpaperChange: ""
      property string darkModeChange: ""
      property string screenLock: ""
      property string screenUnlock: ""
      property string performanceModeEnabled: ""
      property string performanceModeDisabled: ""
      property string startup: ""
      property string session: ""
      property string colorGeneration: ""
      property string desktopLeftClick: ""
      property string desktopRightClick: ""
      property string desktopMiddleClick: ""

      property JsonObject handlers: JsonObject {
        property JsonObject suspendAction: JsonObject {
          property string command: ""
          property bool exclusive: false
        }
        property JsonObject hibernateAction: JsonObject {
          property string command: ""
          property bool exclusive: false
        }
        property JsonObject lockAction: JsonObject {
          property string command: ""
          property bool exclusive: false
        }
        property JsonObject screenOffAction: JsonObject {
          property string command: ""
          property bool exclusive: false
        }
        property JsonObject shutdownAction: JsonObject {
          property string command: ""
          property bool exclusive: false
        }
        property JsonObject rebootAction: JsonObject {
          property string command: ""
          property bool exclusive: false
        }
        property JsonObject userspaceRebootAction: JsonObject {
          property string command: ""
          property bool exclusive: false
        }
        property JsonObject rebootToUefiAction: JsonObject {
          property string command: ""
          property bool exclusive: false
        }
        property JsonObject desktopLeftClick: JsonObject {
          property string command: ""
          property bool exclusive: false
        }
        property JsonObject desktopRightClick: JsonObject {
          property string command: ""
          property bool exclusive: false
        }
        property JsonObject desktopMiddleClick: JsonObject {
          property string command: ""
          property bool exclusive: false
        }
      }

      property JsonObject listeners: JsonObject {
        property string startup: ""
        property string wallpaperChange: ""
        property string colorGeneration: ""
        property string darkModeChange: ""
        property string screenLock: ""
        property string screenUnlock: ""
        property string performanceModeEnabled: ""
        property string performanceModeDisabled: ""
      }
    }

    // plugins
    property JsonObject plugins: JsonObject {
      property bool autoUpdate: false
      property bool notifyUpdates: true
    }

    // idle management
    property JsonObject idle: JsonObject {
      property bool enabled: false
      property int screenOffTimeout: 600    // seconds, 0 = disabled
      property int lockTimeout: 660         // seconds, 0 = disabled
      property int suspendTimeout: 1800     // seconds, 0 = disabled
      property int fadeDuration: 5       // seconds of fade-to-black before action fires
      property string screenOffCommand: ""
      property string lockCommand: ""
      property string suspendCommand: ""
      property string resumeScreenOffCommand: ""
      property string resumeLockCommand: ""
      property string resumeSuspendCommand: ""
      property string customCommands: "[]" // JSON array of {timeout, command, resumeCommand}
    }

    // desktop widgets
    property JsonObject desktopWidgets: JsonObject {
      property bool enabled: false
      property bool overviewEnabled: true
      property bool gridSnap: false
      property bool gridSnapScale: false
      property real iconBlendStrength: 1.0
      property real iconHueAdjustment: 0.0
      property real widgetContentPadding: 0.0
      property list<var> monitorWidgets: []
      // Format: [{ "name": "DP-1", "widgets": [...] }, { "name": "HDMI-1", "widgets": [...] }]
    }

    property JsonObject desktopContextMenu: JsonObject {
      property bool enabled: true
      property list<var> items: [
        {
          "id": "add-app-shortcut"
        },
        {
          "id": "divider"
        },
        {
          "id": "change-wallpaper"
        },
        {
          "id": "display-settings"
        },
        {
          "id": "toggle-edit-mode"
        }
      ]
    }
  }

  // -----------------------------------------------------
  // Preprocess paths by adding trailing "/"
  function ensureTrailingSlash(path) {
    return path.endsWith("/") ? path : path + "/";
  }

  // -----------------------------------------------------
  // Preprocess paths by expanding "~" to user's home directory
  function preprocessPath(path) {
    if (typeof path !== "string" || path === "") {
      return path;
    }

    // Expand "~" to user's home directory
    if (path.startsWith("~/")) {
      return Quickshell.env("HOME") + path.substring(1);
    } else if (path === "~") {
      return Quickshell.env("HOME");
    }

    return path;
  }

  // -----------------------------------------------------
  // Get default value for a setting path (e.g., "general.scaleRatio" or "bar.position")
  // Returns undefined if not found
  function getDefaultValue(path) {
    return root._queryModel("default", {
                              "path": path
                            });
  }

  // -----------------------------------------------------
  // Compare current value with default value
  // Returns true if values differ, false if they match or default is not found
  function isValueChanged(path, currentValue) {
    var defaultValue = getDefaultValue(path);
    if (defaultValue === undefined) {
      return false; // Can't compare if default not found
    }

    // Deep comparison for objects and arrays
    if (typeof currentValue === "object" && typeof defaultValue === "object") {
      return JSON.stringify(currentValue) !== JSON.stringify(defaultValue);
    }

    // Simple comparison for primitives
    return currentValue !== defaultValue;
  }

  // -----------------------------------------------------
  // Format default value for tooltip display
  // Returns a human-readable string representation of the default value
  function formatDefaultValueForTooltip(path) {
    var defaultValue = getDefaultValue(path);
    if (defaultValue === undefined) {
      return "";
    }

    // Format based on type
    if (typeof defaultValue === "boolean") {
      return defaultValue ? "true" : "false";
    } else if (typeof defaultValue === "number") {
      return defaultValue.toString();
    } else if (typeof defaultValue === "string") {
      return defaultValue === "" ? "(empty)" : defaultValue;
    } else if (Array.isArray(defaultValue)) {
      return defaultValue.length === 0 ? "(empty)" : "[" + defaultValue.length + " items]";
    } else if (typeof defaultValue === "object") {
      return "(object)";
    }

    return String(defaultValue);
  }

  // -----------------------------------------------------
  // Helper to find a screen override entry by name in the array
  // Format: [{ "name": "HDMI-A-1", "position": "left" }, ...]
  // Note: QML's list<var> is not a true JS array, so we check for .length instead of Array.isArray()
  function _findScreenOverride(screenName) {
    var overrides = data.bar.screenOverrides;
    if (!screenName || !overrides || overrides.length === undefined) {
      return null;
    }
    for (var i = 0; i < overrides.length; i++) {
      if (overrides[i] && overrides[i].name === screenName) {
        return overrides[i];
      }
    }
    return null;
  }

  // Helper to find index of a screen override entry
  function _findScreenOverrideIndex(screenName) {
    var overrides = data.bar.screenOverrides;
    if (!screenName || !overrides || overrides.length === undefined) {
      return -1;
    }
    for (var i = 0; i < overrides.length; i++) {
      if (overrides[i] && overrides[i].name === screenName) {
        return i;
      }
    }
    return -1;
  }

  // -----------------------------------------------------
  // Check if a screen's overrides are enabled
  // Returns true if enabled flag is true or undefined (backward compat)
  // Returns false only if enabled is explicitly false
  function isScreenOverrideEnabled(screenName) {
    var override = _findScreenOverride(screenName);
    if (!override) {
      return false;
    }
    return override.enabled !== false;
  }

  // -----------------------------------------------------
  // Get effective bar position for a screen (with inheritance)
  // If the screen has a position override and overrides are enabled, use it; otherwise use global default
  function getBarPositionForScreen(screenName) {
    var override = _findScreenOverride(screenName);
    if (override && override.enabled !== false && override.position !== undefined) {
      return override.position;
    }
    return data.bar.position || "top";
  }

  // -----------------------------------------------------
  // Get effective bar widgets for a screen (with inheritance)
  // If the screen has widget overrides and overrides are enabled, use them; otherwise use global defaults
  function getBarWidgetsForScreen(screenName) {
    var override = _findScreenOverride(screenName);
    if (override && override.enabled !== false && override.widgets !== undefined) {
      return override.widgets;
    }
    return data.bar.widgets;
  }

  // -----------------------------------------------------
  // Get effective bar density for a screen (with inheritance)
  // If the screen has a density override and overrides are enabled, use it; otherwise use global default
  function getBarDensityForScreen(screenName) {
    var override = _findScreenOverride(screenName);
    if (override && override.enabled !== false && override.density !== undefined) {
      return override.density;
    }
    return data.bar.density || "default";
  }

  // -----------------------------------------------------
  // Get effective bar display mode for a screen (with inheritance)
  // If the screen has a displayMode override and overrides are enabled, use it; otherwise use global default
  function getBarDisplayModeForScreen(screenName) {
    var override = _findScreenOverride(screenName);
    if (override && override.enabled !== false && override.displayMode !== undefined) {
      return override.displayMode;
    }
    return data.bar.displayMode || "always_visible";
  }

  // -----------------------------------------------------
  // Check if a screen has any overrides, optionally for a specific property
  function hasScreenOverride(screenName, property) {
    var override = _findScreenOverride(screenName);
    if (!override) {
      return false;
    }
    if (property) {
      return override[property] !== undefined;
    }
    // Check if screen has any override property (besides "name")
    var keys = Object.keys(override);
    return keys.length > 1 || (keys.length === 1 && keys[0] !== "name");
  }

  // -----------------------------------------------------
  // Get the screen override entry directly (for in-place modifications)
  // Returns the actual entry object from the array, not a copy
  function getScreenOverrideEntry(screenName) {
    return _findScreenOverride(screenName);
  }

  // -----------------------------------------------------
  // Set a per-screen override
  function setScreenOverride(screenName, property, value) {
    if (!screenName)
      return;

    var overrides = JSON.parse(JSON.stringify(data.bar.screenOverrides || []));
    if (overrides.length === undefined) {
      overrides = [];
    }

    var index = -1;
    for (var i = 0; i < overrides.length; i++) {
      if (overrides[i] && overrides[i].name === screenName) {
        index = i;
        break;
      }
    }

    if (index === -1) {
      // Create new entry
      var newEntry = {
        "name": screenName
      };
      newEntry[property] = value;
      overrides.push(newEntry);
    } else {
      // Update existing entry
      overrides[index][property] = value;
    }
    data.bar.screenOverrides = overrides;
  }

  // -----------------------------------------------------
  // Clear a per-screen override (revert to global default)
  // If property is null, clears all overrides for that screen
  function clearScreenOverride(screenName, property) {
    if (!screenName)
      return;

    var overrides = data.bar.screenOverrides;
    if (!overrides || overrides.length === undefined) {
      return;
    }

    overrides = JSON.parse(JSON.stringify(overrides));

    var index = -1;
    for (var i = 0; i < overrides.length; i++) {
      if (overrides[i] && overrides[i].name === screenName) {
        index = i;
        break;
      }
    }

    if (index === -1) {
      return;
    }

    if (property) {
      delete overrides[index][property];
      // Remove screen entry if only "name" remains
      var keys = Object.keys(overrides[index]);
      if (keys.length <= 1 && (keys.length === 0 || keys[0] === "name")) {
        overrides.splice(index, 1);
      }
    } else {
      overrides.splice(index, 1);
    }
    data.bar.screenOverrides = overrides;
  }

  // -----------------------------------------------------
  // Public function to trigger immediate settings saving.
  // Tracked-set write: diff the settingsAdapter against the last snapshot and merge
  // only the changed leaf paths into the per-section override trees, then
  // write those section files. A change to a value matching today's default
  // is STILL recorded — an explicit user choice always lands in the file.
  function saveImmediate(onComplete, automatic) {
    var token = root._registerCallback(onComplete);
    root._dispatchModel({
                          "type": "captureBegin"
                        });
    try {
      root._dispatchModel({
                            "type": "save",
                            "callbackToken": token,
                            "automatic": automatic === true
                          });
    } finally {
      root.finishCapture();
    }
  }

  // The retained identity owns its capture across retries. A stopped binding
  // intent is never recaptured by an unrelated save or a later queue choice.
  function saveBindingsEnvironment(environment, onComplete, identity) {
    var token = root._registerCallback(onComplete);
    var begin = root._dispatchModel({
                                      "type": "bindingBegin",
                                      "identity": identity
                                    });
    try {
      if (!begin.captured)
        settingsAdapter.bindings.environment = environment;
      root._dispatchModel({
                            "type": "bindingSubmit",
                            "identity": begin.identity,
                            "environment": environment,
                            "callbackToken": token
                          });
    } finally {
      root.finishCapture();
    }
    return begin.identity;
  }

  function saveSetupWork(work, onComplete, requestId) {
    if (!requestId) {
      onComplete(false, "Setup request identity is missing");
      return;
    }
    var token = root._registerCallback(onComplete);
    var captured = root._dispatchModel({
                                         "type": "setupBegin",
                                         "identity": requestId
                                       });
    try {
      if (!captured) {
        settingsAdapter.general.scaleRatio = work.scaleRatio;
        settingsAdapter.bar.position = work.barPosition;
        settingsAdapter.wallpaper.directory = work.wallpaperDirectory;
      }
      root._dispatchModel({
                            "type": "setupSubmit",
                            "identity": requestId,
                            "callbackToken": token
                          });
    } finally {
      root.finishCapture();
    }
  }

  // -----------------------------------------------------
  // Merge settingsAdapter changes since the last snapshot into the per-section
  // override trees (no file write). Returns the list of touched sections.
  function mergePendingChanges() {
    return root._dispatchModel({
                                 "type": "merge"
                               });
  }

  // -----------------------------------------------------
  // Write (or delete, when empty) each touched section's override file.
  // An empty tree means no user choices remain for that panel: the file is
  // removed so "file exists" always means "user chose something here".
  // Writes are tmp+mv so a crash mid-write cannot truncate the file.
  function persistSections(sections, onComplete, managed, fullSave, automatic) {
    var token = root._registerCallback(onComplete);
    root._dispatchModel({
                          "type": "persist",
                          "sections": sections,
                          "callbackToken": token,
                          "managed": managed,
                          "fullSave": fullSave,
                          "automatic": automatic
                        });
  }

  function filePathFor(section) {
    return root._queryModel("path", {
                              "section": section
                            });
  }

  function effectiveDiskEnvironment() {
    return root._queryModel("environment");
  }

  function finishObservedRead(section, loadError) {
    root._dispatchModel({
                          "type": "readDispatch",
                          "section": section
                        });
  }

  function refreshAccepted(section, complete, job, settlement) {
    var token = root._registerCallback(complete);
    root._dispatchModel({
                          "type": "readRequest",
                          "section": section,
                          "callbackToken": token,
                          "settlement": settlement === true
                        });
  }

  // -----------------------------------------------------
  // Recursively collect leaf-path differences between two plain objects.
  // Arrays are treated as leaves (replaced wholesale). Objects present in
  // `before` but missing in `after` are reported as deletions.
  function diffLeaves(before, after, prefix, out) {
    SettingsModel.diffLeaves(before, after, prefix, out);
  }

  // -----------------------------------------------------
  // Set a dotted path (e.g. "bar.position") inside a plain object tree
  function deepSet(obj, path, value) {
    SettingsModel.deepSet(obj, path, value);
  }

  // -----------------------------------------------------
  // Read a dotted path from a (possibly JsonObject-based) tree
  function getPathValue(obj, path) {
    var parts = path.split(".");
    var current = obj;
    for (var i = 0; i < parts.length; i++) {
      if (current === undefined || current === null) {
        return undefined;
      }
      current = current[parts[i]];
    }
    return current;
  }

  // -----------------------------------------------------
  // Adapter-derived schema lookup: is `path` (dotted, e.g.
  // "general.keybinds.keyUp") a declared setting? Own-property membership
  // only — an object's inherited names, QObject bookkeeping (objectName,
  // signals/methods) and arbitrary source keys are not settings. Arrays and
  // their records are opaque setting values: any path at or below an array
  // node counts as declared. Never truthiness-tested: declared
  // false/zero/empty-string values must still apply.
  function isKnownSchemaPath(path) {
    return root._queryModel("known", {
                              "path": path
                            });
  }

  // -----------------------------------------------------
  // Write a dotted path on a (possibly JsonObject-based) tree.
  // `prefix` qualifies section-relative paths so the schema check and
  // warnings use the full setting name (e.g. "general.lockScreenMode").
  // Returns true when the value was applied.
  function setPathValue(obj, path, value, prefix) {
    var fullPath = prefix ? prefix + "." + path : path;
    if (!isKnownSchemaPath(fullPath)) {
      Logger.w("Settings", "Ignoring unknown setting: " + fullPath);
      return false;
    }
    var parts = path.split(".");
    var current = obj;
    for (var i = 0; i < parts.length - 1; i++) {
      current = current[parts[i]];
      if (current === undefined || current === null) {
        return false;
      }
    }
    current[parts[parts.length - 1]] = value;
    return true;
  }

  // -----------------------------------------------------
  // Delete a dotted path from a plain object tree (prunes empty parents)
  function deepDelete(obj, path) {
    SettingsModel.deepDelete(obj, path);
  }

  // -----------------------------------------------------
  // Deep-apply a plain-object tree onto a JsonObject subtree (used to
  // restore defaults for a section). Arrays replace; plain objects recurse.
  // `prefix` is the dotted path of `target` within the settings tree; keys
  // absent from the adapter-derived schema are warned about and skipped
  // instead of throwing on assignment to a non-existent QObject property.
  // Returns the number of leaf assignments actually applied.
  function deepApply(target, source, prefix, appliedPaths) {
    var applied = 0;
    for (var key in source) {
      if (!Object.prototype.hasOwnProperty.call(source, key)) {
        continue;
      }
      var fullPath = prefix ? prefix + "." + key : key;
      if (!isKnownSchemaPath(fullPath)) {
        Logger.w("Settings", "Ignoring unknown setting: " + fullPath);
        continue;
      }
      var value = source[key];
      if (value !== null && typeof value === "object" && !Array.isArray(value) && target[key] !== undefined && target[key] !== null && typeof target[key] === "object") {
        applied += deepApply(target[key], value, fullPath, appliedPaths);
      } else {
        target[key] = value;
        applied++;
        if (appliedPaths)
          appliedPaths.push(fullPath);
      }
    }
    return applied;
  }

  // -----------------------------------------------------
  // Reset one section (panel root key, e.g. "bar") to shipped defaults:
  // drop the section's override tree, delete its file, re-apply defaults.
  function resetSection(key) {
    if (key === "bindings" && root._queryModel("managed")) {
      root.bindingsEnvironmentRequested(getDefaultValue("bindings.environment") || "none");
      return;
    }
    if (!root._queryModel("hasSnapshot")) {
      return;
    }
    // Flush pending debounced changes first so they are not lost
    var touched = mergePendingChanges();
    touched = root._dispatchModel({
                                    "type": "resetBegin",
                                    "path": key,
                                    "sectionReset": true,
                                    "touched": touched
                                  });
    var defaults = getDefaultValue(key);
    if (defaults !== undefined && settingsAdapter[key] !== undefined) {
      deepApply(settingsAdapter[key], defaults, key);
    }
    // The restored defaults are the new baseline for this section; the
    // emptied tree deletes the file.
    root._dispatchModel({
                          "type": "resetEnd",
                          "sections": touched
                        });
  }

  // -----------------------------------------------------
  // Reset a single setting path (e.g. "bar.position") to its shipped default:
  // drop that key from the section's override tree and re-apply the default.
  function resetValue(path) {
    if (path === "bindings.environment" && root._queryModel("managed")) {
      root.bindingsEnvironmentRequested(getDefaultValue(path) || "none");
      return;
    }
    if (!root._queryModel("hasSnapshot")) {
      return;
    }
    // Flush pending debounced changes first so they are not lost
    var touched = mergePendingChanges();
    touched = root._dispatchModel({
                                    "type": "resetBegin",
                                    "path": path,
                                    "sectionReset": false,
                                    "touched": touched
                                  });
    var defaultValue = getDefaultValue(path);
    if (defaultValue !== undefined) {
      setPathValue(settingsAdapter, path, defaultValue, "");
    }
    root._dispatchModel({
                          "type": "resetEnd",
                          "sections": touched
                        });
  }

  // -----------------------------------------------------
  // Generate default settings: for reference only, not used by the shell
  function generateDefaultSettings() {
    try {
      Logger.d("Settings", "Generating Configs/defaults.json");

      // Prepare a clean JSON
      var plainAdapter = QtObj2JS.qtObjectToPlainObject(settingsAdapter);
      var jsonData = JSON.stringify(plainAdapter, null, 2);

      var defaultPath = Quickshell.shellDir + "/Configs/defaults.json";

      Quickshell.execDetached(["sh", "-c", `cat > "${defaultPath}" << 'ATMOSPHERA_EOF'\n${jsonData}\nATMOSPHERA_EOF`]);
    } catch (error) {
      Logger.e("Settings", "Failed to generate default settings file: " + error);
    }
  }

  // -----------------------------------------------------
  // Generate default widget settings: for reference only, not used by the shell
  function generateWidgetDefaultSettings() {
    try {
      Logger.d("Settings", "Generating settings-widgets-default.json");

      var output = {
        "bar": QtObj2JS.qtObjectToPlainObject(BarWidgetRegistry.widgetMetadata),
        "controlCenter": QtObj2JS.qtObjectToPlainObject(ControlCenterWidgetRegistry.widgetMetadata),
        "desktop": QtObj2JS.qtObjectToPlainObject(DesktopWidgetRegistry.widgetMetadata)
      };
      var jsonData = JSON.stringify(output, null, 2);

      var defaultPath = Quickshell.shellDir + "/Assets/settings-widgets-default.json";

      Quickshell.execDetached(["sh", "-c", `cat > "${defaultPath}" << 'ATMOSPHERA_EOF'\n${jsonData}\nATMOSPHERA_EOF`]);
    } catch (error) {
      Logger.e("Settings", "Failed to generate widget default settings file: " + error);
    }
  }

  // -----------------------------------------------------
  // Run versioned migrations using MigrationRegistry
  // rawJson is the parsed JSON file content (before settingsAdapter filtering)
  function runVersionedMigrations(rawJson) {
    // Skip migrations on fresh installs (no prior settings file)
    if (!rawJson || root.isFreshInstall) {
      Logger.i("Settings", "Fresh install detected, skipping migrations");
      return;
    }

    const currentVersion = settingsAdapter.settingsVersion;
    const migrations = MigrationRegistry.migrations;

    Logger.i("Settings", "settingsAdapter.settingsVersion:", settingsAdapter.settingsVersion);

    // Get all migration versions and sort them
    const versions = Object.keys(migrations).map(v => parseInt(v)).sort((a, b) => a - b);

    // Run migrations in order for versions newer than current
    for (var i = 0; i < versions.length; i++) {
      const version = versions[i];

      if (currentVersion < version) {
        // Create migration instance and run it
        const migrationComponent = migrations[version];
        const migration = migrationComponent.createObject(root);

        if (migration && typeof migration.migrate === "function") {
          const success = migration.migrate(settingsAdapter, Logger, rawJson);
          if (!success) {
            Logger.e("Settings", "Migration to v" + version + " failed");
          }
        } else {
          Logger.e("Settings", "Invalid migration for v" + version);
        }

        // Clean up migration instance
        if (migration) {
          migration.destroy();
        }
      }
    }
  }

  // -----------------------------------------------------
  // If the settings structure has changed, ensure
  // backward compatibility by upgrading the settings
  function upgradeSettings() {
    // Wait for PluginService to finish loading plugins first
    // This prevents deleting plugin widgets during reload before plugins are registered
    if (!Service.initialized || !Service.pluginsFullyLoaded) {
      Logger.d("Settings", "Plugins not fully loaded yet, deferring upgrade");
      Qt.callLater(upgradeSettings);
      return;
    }

    // Wait for BarWidgetRegistry to be ready
    if (!BarWidgetRegistry.widgets || Object.keys(BarWidgetRegistry.widgets).length === 0) {
      Logger.d("Settings", "BarWidgetRegistry not ready, deferring upgrade");
      Qt.callLater(upgradeSettings);
      return;
    }

    // Flush any user changes that landed during the startup window BEFORE
    // housekeeping runs — the re-baseline at the end must absorb only
    // housekeeping mutations, never user edits.
    var userTouchedSections = mergePendingChanges();

    // -----------------
    const sections = ["left", "center", "right"];

    // 1. remove any non existing bar widget type
    var removedWidget = false;
    for (var s = 0; s < sections.length; s++) {
      const sectionName = sections[s];
      const widgets = settingsAdapter.bar.widgets[sectionName];
      // Iterate backward through the widgets array, so it does not break when removing a widget
      for (var i = widgets.length - 1; i >= 0; i--) {
        var widget = widgets[i];
        if (!BarWidgetRegistry.hasWidget(widget.id)) {
          // Mark-and-remember: a plugin widget whose plugin is still
          // installed but momentarily unloadable (load error, mid-startup)
          // is KEPT — the bar renders a placeholder and the real widget
          // returns when the plugin does. Only widgets whose plugin is
          // genuinely gone are deleted.
          var pluginKey = BarWidgetRegistry.isPluginWidget(widget.id) ? widget.id.substring(7) : "";
          if (pluginKey !== "" && Registry.isPluginDownloaded(pluginKey)) {
            Logger.i("Settings", "Keeping bar widget for installed but unloadable plugin:", widget.id);
            continue;
          }
          Logger.w(`Settings`, `!!! Deleted invalid bar widget ${widget.id} !!!`);
          widgets.splice(i, 1);
          removedWidget = true;
        }
      }
    }

    // -----------------
    // 2. remove any non existing control center widget type
    const ccSections = ["left", "right"];
    for (var s = 0; s < ccSections.length; s++) {
      const sectionName = ccSections[s];
      const shortcuts = settingsAdapter.controlCenter.shortcuts[sectionName];
      for (var i = shortcuts.length - 1; i >= 0; i--) {
        var shortcut = shortcuts[i];
        if (!ControlCenterWidgetRegistry.hasWidget(shortcut.id)) {
          Logger.w(`Settings`, `!!! Deleted invalid control center widget ${shortcut.id} !!!`);
          shortcuts.splice(i, 1);
          removedWidget = true;
        }
      }
    }

    // -----------------
    // 3. remove any non existing desktop widget type
    const monitorWidgets = settingsAdapter.desktopWidgets.monitorWidgets;
    for (var m = 0; m < monitorWidgets.length; m++) {
      const monitor = monitorWidgets[m];
      if (!monitor.widgets)
        continue;
      for (var i = monitor.widgets.length - 1; i >= 0; i--) {
        var desktopWidget = monitor.widgets[i];
        if (!DesktopWidgetRegistry.hasWidget(desktopWidget.id)) {
          Logger.w(`Settings`, `!!! Deleted invalid desktop widget ${desktopWidget.id} !!!`);
          monitor.widgets.splice(i, 1);
          removedWidget = true;
        }
      }
    }

    // -----------------
    // 4. upgrade user widget settings
    for (var s = 0; s < sections.length; s++) {
      const sectionName = sections[s];
      for (var i = 0; i < settingsAdapter.bar.widgets[sectionName].length; i++) {
        var widget = settingsAdapter.bar.widgets[sectionName][i];

        // Check if widget registry supports user settings, if it does not, then there is nothing to do
        if (BarWidgetRegistry.widgetMetadata[widget.id] === undefined) {
          continue;
        }

        if (upgradeWidget(widget)) {
          Logger.d("Settings", `Upgraded ${widget.id} widget:`, JSON.stringify(widget));
        }
      }
    }

    // Housekeeping (widget pruning / metadata injection) stays in-memory
    // only: re-baseline the snapshot so it is never persisted to the
    // user's override files. User changes flushed above are written now.
    root._dispatchModel({
                          "type": "rebaseline"
                        });
    if (userTouchedSections.length > 0) {
      persistSections(userTouchedSections);
    }
  }

  // -----------------------------------------------------
  // Function to clean up deprecated user/custom bar widgets settings
  function upgradeWidget(widget) {
    // Backup the widget definition before altering
    const widgetBefore = JSON.stringify(widget);

    // Get all existing custom settings keys
    const keys = Object.keys(BarWidgetRegistry.widgetMetadata[widget.id]);

    // Delete deprecated user settings from the wiget
    for (const k of Object.keys(widget)) {
      if (k === "id") {
        continue;
      }
      if (!keys.includes(k)) {
        delete widget[k];
      }
    }

    // Inject missing default setting (metaData) from BarWidgetRegistry
    for (var i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (k === "id") {
        continue;
      }

      if (widget[k] === undefined) {
        widget[k] = BarWidgetRegistry.widgetMetadata[widget.id][k];
      }
    }

    // Compare settings, to detect if something has been upgraded
    const widgetAfter = JSON.stringify(widget);
    return (widgetAfter !== widgetBefore);
  }
}
