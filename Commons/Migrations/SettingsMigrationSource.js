.pragma library

// A standalone worker function, not a stringified QML closure. Historical
// compatibility never changes writable raw data or stamps the legacy file.
var transform = `function(input) {
  var raw = input.raw;
  var values = input.values;
  var compatibilityRaw = input.compatibilityRaw;
  var effects = [];
  var has = Object.prototype.hasOwnProperty;

  function object(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }
  function own(value, key) {
    return object(value) && has.call(value, key);
  }
  function read(value, path) {
    for (var i = 0; i < path.length; ++i) {
      if (!own(value, path[i]))
        return undefined;
      value = value[path[i]];
    }
    return value;
  }
  function put(value, path, item) {
    for (var i = 0; i < path.length - 1; ++i) {
      if (!own(value, path[i]) || !object(value[path[i]]))
        value[path[i]] = Object.create(null);
      value = value[path[i]];
    }
    value[path[path.length - 1]] = item;
  }
  function decimal(value) {
    // Only the version selector and v38's two numeric calculations unwrap
    // worker atoms. All other numbers, including unknown ones, retain identity.
    return typeof value === "number" ? value :
      (object(value) && Object.isFrozen(value) && typeof value.decimal === "string" ? Number(value.decimal) : NaN);
  }
  function effect(version, action) {
    effects.push({effectId: "settings-migration-" + version, version: version,
                  action: action, arguments: {}});
  }
  function wifi(path) {
    var displayed = read(values, path);
    if (!Array.isArray(displayed))
      displayed = read(input.lowerValues, path);
    if (!Array.isArray(displayed))
      return;
    var original = read(raw, path);
    var result = displayed.slice();
    var changed = false;
    for (var i = 0; i < result.length; ++i) {
      var item = original && original[i] !== undefined ? original[i] : result[i];
      if (item === "WiFi") {
        result[i] = "Network";
        changed = true;
      } else if (object(item)) {
        var id = item.id !== undefined ? item.id : item.widgetId;
        if (id === "WiFi") {
          var replacement = Object.create(null);
          Object.keys(item).forEach(function(key) { replacement[key] = item[key]; });
          if (replacement.id !== undefined)
            replacement.id = "Network";
          else if (replacement.widgetId !== undefined)
            replacement.widgetId = "Network";
          result[i] = replacement;
          changed = true;
        }
      }
    }
    if (changed)
      put(values, path, result);
  }

  if (input.source.presence !== "present")
    return {values: values, compatibilityRaw: compatibilityRaw, effects: [], diagnostics: []};

  var version = decimal(raw.settingsVersion);
  if (!Number.isFinite(version))
    version = 0;
  var bar = raw.bar;
  var wallpaper = raw.wallpaper;
  var keybinds = read(raw, ["general", "keybinds"]);
  if (version < 27 && read(raw, ["ui", "settingsPanelAttachToBar"]) !== undefined)
    put(values, ["ui", "settingsPanelMode"], raw.ui.settingsPanelAttachToBar === true ? "attached" : "centered");
  if (version < 28) {
    ["left", "center", "right"].forEach(function(section) {
      var widgets = read(raw, ["bar", "widgets", section]);
      if (!Array.isArray(widgets))
        return;
      var updated = widgets.map(function(widget) {
        if (!widget || widget.id !== "TaskbarGrouped")
          return widget;
        return {id: "Workspace", showApplications: true,
                labelMode: widget.labelMode || "index",
                hideUnoccupied: widget.hideUnoccupied || false,
                showLabelsOnlyWhenOccupied: widget.showLabelsOnlyWhenOccupied === undefined || widget.showLabelsOnlyWhenOccupied === null ? true : widget.showLabelsOnlyWhenOccupied,
                colorizeIcons: widget.colorizeIcons || false};
      });
      put(values, ["bar", "widgets", section], updated);
    });
  }
  if (version < 32 && read(raw, ["systemMonitor", "enableNvidiaGpu"]) !== undefined)
    put(values, ["systemMonitor", "enableDgpuMonitoring"], raw.systemMonitor.enableNvidiaGpu);
  // v33 intentionally seeded random for missing and false too.
  if (version < 33)
    put(values, ["wallpaper", "wallpaperChangeMode"], "random");
  if (version < 35 && bar && bar.transparent === true) {
    put(values, ["bar", "backgroundOpacity"], 0);
    put(values, ["bar", "useSeparateOpacity"], true);
  }
  if (version < 36)
    effect(36, "clear-emoji-usage");
  if (version < 37) {
    ["left", "center", "right"].forEach(function(section) { wifi(["bar", "widgets", section]); });
    ["left", "right"].forEach(function(section) { wifi(["controlCenter", "shortcuts", section]); });
  }
  if (version < 38 && bar) {
    ["marginVertical", "marginHorizontal"].forEach(function(key) {
      var number = decimal(bar[key]);
      if (Number.isFinite(number) && number <= 1.0)
        put(values, ["bar", key], Math.round(number * 18));
    });
  }
  if (version < 40 && raw.templates && !Array.isArray(raw.templates.activeTemplates)) {
    var templateIds = ["gtk", "qt", "kcolorscheme", "alacritty", "kitty", "ghostty", "foot", "wezterm", "fuzzel", "discord", "pywalfox", "vicinae", "walker", "code", "spicetify", "telegram", "cava", "yazi", "emacs", "niri", "hyprland", "mango", "zed", "helix", "zenBrowser"];
    put(values, ["templates", "activeTemplates"], templateIds.filter(function(id) {
      return raw.templates[id] === true;
    }).map(function(id) { return {id: id, enabled: true}; }));
  }
  if (version < 42 && wallpaper && wallpaper.automationEnabled === undefined)
    put(values, ["wallpaper", "automationEnabled"], wallpaper.randomEnabled === undefined || wallpaper.randomEnabled === null ? false : wallpaper.randomEnabled);
  if (version < 43 && wallpaper && wallpaper.viewMode === undefined)
    put(values, ["wallpaper", "viewMode"], wallpaper.recursiveSearch ? "recursive" : "single");
  if (version < 44)
    effect(44, "create-legacy-pam");
  if (version < 45)
    put(values, ["bar", "barType"], bar && bar.floating ? "floating" : "simple");
  if (version < 46)
    effect(46, "remove-legacy-pam");
  if (version < 47)
    effect(47, "clear-network-stats");
  if (version < 48) {
    ["batteryWarningThreshold", "batteryCriticalThreshold"].forEach(function(key) {
      if (read(raw, ["notifications", key]) !== undefined)
        put(values, ["systemMonitor", key], raw.notifications[key]);
    });
  }
  if (version < 49)
    effect(49, "clear-launcher-usage");
  if (version < 50 && keybinds) {
    ["keyUp", "keyDown", "keyLeft", "keyRight", "keyEnter", "keyEscape"].forEach(function(key) {
      if (typeof keybinds[key] === "string")
        put(values, ["general", "keybinds", key], [keybinds[key]]);
    });
  }
  if (version < 53) {
    var powerOptions = read(raw, ["sessionMenu", "powerOptions"]);
    if (Array.isArray(powerOptions) && !powerOptions.some(function(option) { return option.keybind && option.keybind !== ""; })) {
      var defaults = {lock: "1", suspend: "2", hibernate: "3", reboot: "4", logout: "5", shutdown: "6"};
      var currentOptions = read(values, ["sessionMenu", "powerOptions"]);
      if (Array.isArray(currentOptions)) {
        currentOptions = currentOptions.map(function(option, index) {
          var action = powerOptions[index].action;
          if (!has.call(defaults, action))
            return option;
          var replacement = Object.create(null);
          Object.keys(option).forEach(function(key) { replacement[key] = option[key]; });
          replacement.keybind = defaults[action];
          return replacement;
        });
        put(values, ["sessionMenu", "powerOptions"], currentOptions);
      }
    }
  }
  if (version < 54 && keybinds && Array.isArray(keybinds.keyEnter) && keybinds.keyEnter[0] === "Return" && keybinds.keyEnter.indexOf("Enter") === -1) {
    var enter = keybinds.keyEnter.slice();
    enter.splice(1, 0, "Enter");
    put(values, ["general", "keybinds", "keyEnter"], enter);
  }
  // v55 changes raw compatibility only. Do not feed it back into values.
  if (version < 55 && read(raw, ["controlCenter", "openAtMouseOnBarRightClick"]) !== undefined) {
    put(compatibilityRaw, ["bar", "rightClickFollowMouse"], raw.controlCenter.openAtMouseOnBarRightClick);
    delete compatibilityRaw.controlCenter.openAtMouseOnBarRightClick;
  }
  if (version < 56)
    effect(56, "migrate-color-schemes");
  if (version < 57 && read(raw, ["audio", "cavaFrameRate"]) !== undefined)
    put(values, ["audio", "spectrumFrameRate"], raw.audio.cavaFrameRate);
  if (version < 58 && read(raw, ["dock", "dockType"]) === "static")
    put(values, ["dock", "dockType"], "attached");
  if (version < 59 && wallpaper && typeof wallpaper.transitionType === "string") {
    var transition = wallpaper.transitionType;
    put(values, ["wallpaper", "transitionType"], transition === "random" ? ["fade", "disc", "stripes", "wipe", "pixelate", "honeycomb"] : transition === "none" ? [] : [transition]);
  }
  if (version < 60 && typeof read(raw, ["bindings", "environment"]) !== "string")
    put(values, ["bindings", "environment"], "none");
  if (version < 61) {
    var inputMethod = object(raw.inputMethod) ? raw.inputMethod : Object.create(null);
    ["switches", "nextKeys"].forEach(function(key) {
      if (!Array.isArray(inputMethod[key]))
        put(values, ["inputMethod", key], []);
    });
    if (typeof inputMethod.launchFcitx5 !== "boolean")
      put(values, ["inputMethod", "launchFcitx5"], true);
    if (typeof inputMethod.legacyI18nChecked !== "boolean")
      put(values, ["inputMethod", "legacyI18nChecked"], false);
  }
  if (version < 62 && keybinds && Array.isArray(keybinds.keyRemove) && keybinds.keyRemove.length === 1 && keybinds.keyRemove[0] === "Del")
    put(values, ["general", "keybinds", "keyRemove"], ["Shift+Del"]);
  values.settingsVersion = 62;
  return {values: values, compatibilityRaw: compatibilityRaw, effects: effects, diagnostics: []};
}`;
