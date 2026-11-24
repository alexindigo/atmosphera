// Catalog page witness: each listed generic Settings entry in both scopes,
// through the actual popup/session/native owners. One real control's own user
// signal carries intent; files are read back after Apply and Reset.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property bool started: false
  property string phase: "opening"
  property var ids: Quickshell.env("PHA_CATALOG_IDS").split(",").filter(function (id) {
    return id.length > 0;
  })
  property var manifests: ({})
  property var apis: ({})
  property int pluginIndex: 0
  property int scopeIndex: 0
  property var row: null
  property var receipt: null
  property var chosen: null
  property var queue: []
  property int waited: 0
  // Native preflight durably retains evidence. Measured all-10 retention was
  // 6331 ms, plus all-14 ordinary open max 3289 ms. A finite 15000 ms opening
  // budget includes loaded-disk headroom; it is never renewed by polling.
  readonly property int nativeOpenBudgetMs: 15000
  readonly property int nativeResultBudgetMs: 18000
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  readonly property var scopes: ["plugin", "instance"]
  readonly property string pluginId: ids[pluginIndex] || ""
  readonly property string scopeName: scopes[scopeIndex]
  FileView {
    id: reader
    blockLoading: true
    printErrors: false
  }
  PanelWindow {
    id: host
    visible: true
    implicitWidth: 1280
    implicitHeight: 800
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: function (result) {
        root.receipt = result;
      }
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error(message);
  }
  function elapsed() {
    return Date.now() - phaseStarted;
  }
  function fail(error) {
    console.error("CATALOG_FATAL " + String(error));
    Qt.exit(2);
  }
  function readJson(path) {
    reader.path = "";
    reader.path = path;
    reader.waitForJob();
    var text = reader.text();
    return text ? JSON.parse(text) : null;
  }
  function sharedFile() {
    return Settings.configDir + "settings/plugins/" + pluginId + ".json";
  }
  function placementRow() {
    var rows = readJson(Settings.configDir + "settings/bar.json").widgets.left;
    return rows[pluginIndex];
  }
  function stored() {
    if (scopeName === "plugin") {
      var values = readJson(sharedFile());
      return values;
    }
    return placementRow().instanceSettings || {};
  }
  function find(object, predicate, all) {
    var found = [];
    var visited = [];
    function walk(item) {
      if (!item || visited.indexOf(item) !== -1)
        return;
      visited.push(item);
      if (predicate(item)) {
        found.push(item);
        if (!all)
          return;
      }
      for (var list of [item.data || item.children, item.contentItem ? [item.contentItem] : null]) {
        if (!list)
          continue;
        for (var i = 0; i < list.length; i++) {
          walk(list[i]);
          if (found.length && !all)
            return;
        }
      }
    }
    walk(object);
    return all ? found : (found[0] || null);
  }
  function chromes() {
    return find(popup.settingsPage, function (item) {
      return item.field !== undefined && item.content !== undefined;
    }, true);
  }
  function pendingSets() {
    var keys = [];
    for (var chrome of chromes())
      if (chrome.field && chrome.field.pendingIntent === "set" && keys.indexOf(chrome.field.key) === -1)
        keys.push(chrome.field.key);
    return keys;
  }
  function jsonValue(value) {
    return JSON.stringify(value, function (_, item) {
      if (!item || typeof item !== "object" || Array.isArray(item))
        return item;
      var ordered = Object.create(null);
      for (var key of Object.keys(item).sort())
        ordered[key] = item[key];
      return ordered;
    });
  }
  function captureApplyIntent(keys) {
    // Store detached JSON text, not fields whose getters follow the refreshed draft.
    return keys.map(function (key) {
      var field = popup._pageApi.field(key);
      var value = jsonValue(field.value);
      check(value !== undefined, "pending Set without a JSON value " + key);
      return {
        key: key,
        value: value,
        omitted: scopeName === "instance" && field.inheritedPresent && jsonValue(field.inheritedValue) === value
      };
    });
  }
  function kind(item) {
    if (typeof item.toggled === "function" && typeof item.checked === "boolean")
      return "toggle";
    if (typeof item.selected === "function" && item.currentKey !== undefined && (item.model !== undefined || item.diameter !== undefined))
      return "choice";
    if (typeof item.inputEditCommitted === "function")
      return "textButton";
    if (typeof item.editCommitted === "function" && item.text !== undefined)
      return "text";
    if (typeof item.submitValue === "function" && item.value !== undefined)
      return "spin";
    if (typeof item.moved === "function" && item.value !== undefined && item.from !== undefined)
      return "slider";
    return "";
  }
  function choiceKeys(control) {
    // NColorChoice renders the shared color-key model rather than a model property.
    return modelKeys(control.model !== undefined ? control.model : AtmoColor.colorKeyModel);
  }
  function usable(control) {
    if (kind(control) !== "choice")
      return true;
    return choiceKeys(control).some(function (key) {
      return key !== String(control.currentKey);
    });
  }
  function controlsOf(chrome) {
    return find(chrome, function (item) {
      return item !== chrome && kind(item) !== "";
    }, true);
  }
  // Field-bound controls, visible/enabled ones first. A control whose own
  // signal yields no intent (e.g. a picker's search box) is skipped.
  function candidates() {
    var visible = [];
    var rest = [];
    for (var chrome of chromes()) {
      if (!chrome.field || !chrome.enabled)
        continue;
      for (var control of controlsOf(chrome).filter(usable)) {
        var candidate = {
          chrome: chrome,
          control: control,
          field: chrome.field
        };
        if (chrome.visible && control.visible && control.enabled)
          visible.push(candidate);
        else
          rest.push(candidate);
      }
    }
    return visible.concat(rest);
  }
  function modelKeys(model) {
    var keys = [];
    var count = model.length !== undefined ? model.length : (model.count || 0);
    for (var i = 0; i < count; i++) {
      var entry = model.length !== undefined ? model[i] : model.get(i);
      if (entry && entry.key !== undefined)
        keys.push(String(entry.key));
    }
    return keys;
  }
  // The control's own user-interaction signal; never a page/field setter.
  function interact(control) {
    var type = kind(control);
    if (type === "toggle") {
      control.toggled(!control.checked);
      return type;
    }
    if (type === "choice") {
      var other = choiceKeys(control).filter(function (key) {
        return key !== String(control.currentKey);
      });
      check(other.length > 0, "choice control without an alternative key");
      control.selected(other[0]);
      return type;
    }
    if (type === "text" || type === "textButton") {
      var value = /^-?\d+(\.\d+)?$/.test(String(control.text)) ? String(Number(control.text) + 1) : String(control.text) + "1";
      control.text = value;
      if (type === "text")
        control.editCommitted();
      else
        control.inputEditCommitted();
      return type;
    }
    var step = control.stepSize > 0 ? control.stepSize : 1;
    var next = control.value + step <= control.to ? control.value + step : control.value - step;
    if (type === "spin")
      control.submitValue(next);
    else {
      control.value = next;
      control.moved(next);
    }
    return type;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    var placements = [];
    for (var id of ids) {
      reader.path = Settings.configDir + "plugins/" + id + "/manifest.json";
      reader.waitForJob();
      manifests[id] = JSON.parse(reader.text());
      placements.push({
                        id: "plugin:" + id
                      });
    }
    Registry.installedPlugins = manifests;
    Settings.data.bar.widgets.left = placements;
    Settings.saveSelected([["bar", "widgets", "left"]], function (result) {
      try {
        check(result.status !== "failed", "seed placements");
        openOwner(0);
      } catch (error) {
        fail(error);
      }
    });
  }
  function openOwner(index) {
    if (index >= ids.length) {
      var loaded = {};
      for (var key of ids)
        loaded[key] = {
          api: apis[key]
        };
      Service.loadedPlugins = loaded;
      phase = "next";
      return;
    }
    Service._openSettingsOwner(ids[index], function (owner) {
      try {
        check(owner !== null, "native owner " + ids[index]);
        apis[ids[index]] = Service.createPluginAPI(ids[index], manifests[ids[index]], owner, {}, {}, {});
        openOwner(index + 1);
      } catch (error) {
        fail(error);
      }
    });
  }
  function emit(status, detail) {
    row.status = status;
    if (detail)
      row.detail = String(detail);
    console.log("CATALOG_ROW " + JSON.stringify(row));
    row = null;
    phase = "closing";
  }
  function open() {
    receipt = null;
    chosen = null;
    waited = 0;
    row = {
      plugin: pluginId,
      scope: scopeName,
      instanceOpenMs: scopeName === "instance" ? elapsed() : 0,
      nativeOpenBudgetMs: nativeOpenBudgetMs
    };
    var api = apis[pluginId];
    var placementApi = scopeName === "instance" ? PluginInstances.apiFor(pluginId, {
                                                                           kind: "bar",
                                                                           list: "global",
                                                                           section: "left",
                                                                           index: pluginIndex
                                                                         }) : null;
    row.before = stored();
    check(scopeName === "plugin" ? popup.openPluginSettings(manifests[pluginId], "settings") : popup.openInstanceSettings(manifests[pluginId], placementApi, "settings"), "popup refused opening");
    phase = "page";
  }
  function drive() {
    if (phase === "next") {
      if (pluginIndex >= ids.length) {
        console.log("CATALOG_DONE");
        Qt.exit(0);
        return;
      }
      if (scopeName === "instance") {
        var selected = PluginInstances.apiFor(pluginId, {
                                                kind: "bar",
                                                list: "global",
                                                section: "left",
                                                index: pluginIndex
                                              });
        if (!selected || !selected.settingsReady) {
          if (elapsed() >= nativeOpenBudgetMs) {
            var base = apis[pluginId];
            var mainInfo = Settings.store.info(["bar", "widgets", "left"]);
            var counters = {};
            for (var key of base.settingsOwner.store.settingsKeys) {
              var info = base.settingsHandle.info([key]);
              counters[key] = {
                latestInput: info.latestInput,
                workerCovered: info.workerCovered
              };
            }
            fail("instance api " + pluginId + ": " + (selected ? selected.settingsError : "missing") + ", elapsedMs=" + elapsed() + ", budgetMs=" + nativeOpenBudgetMs + ", baseReady=" + base.settingsReady + ", runtime=" + !!selected?.runtime + ", owningLeaf=" + JSON.stringify({
                                                                                                                                                                                                                                                                                       latestInput: mainInfo.latestInput,
                                                                                                                                                                                                                                                                                       workerCovered: mainInfo.workerCovered
                                                                                                                                                                                                                                                                                     }) + ", baseCounters=" + JSON.stringify(counters));
          }
          return;
        }
      }
      open();
    } else if (phase === "page") {
      if (elapsed() >= nativeOpenBudgetMs) {
        emit("FAIL", "page did not open: " + popup._editor?.error + ", elapsedMs=" + elapsed() + ", budgetMs=" + nativeOpenBudgetMs);
        return;
      }
      if (!popup.opened || !popup.settingsPage)
        return;
      row.pageOpenMs = elapsed();
      row.constructionIntent = popup.dirty || (popup._editor && popup._editor.dirty);
      row.pageType = String(popup.settingsPage).split("(")[0];
      if (row.constructionIntent) {
        emit("FAIL", "page construction submitted intent");
        return;
      }
      queue = candidates();
      chosen = queue.shift() || null;
      row.fieldChromes = chromes().length;
      // Environment-bound pages (e.g. hardware-populated choices) still prove
      // clean construction and a nonpublishing Close, but are not PASS.
      var declared = Object.keys(manifests[pluginId].metadata?.settingsSchema?.fields || {}).length;
      // An informational page declares no preferences: clean construction and
      // a nonpublishing Close are its whole contract.
      if (!chosen && declared === 0) {
        emit("INFORMATIONAL", "page declares no settings fields");
        return;
      }
      if (!chosen) {
        emit(row.fieldChromes > 0 ? "UNEXERCISED" : "FAIL", "no usable field-bound control in this environment");
        return;
      }
      row.key = chosen.field.key;
      row.inherited = chosen.field.overridden === false;
      row.control = interact(chosen.control);
      row.skipped = 0;
      waited = 0;
      phase = "intent";
    } else if (phase === "intent") {
      if (chosen.field.pendingIntent !== "set") {
        if (++waited <= 15)
          return;
        if (pendingSets().length || popup.dirty) {
          emit("FAIL", "control intent landed on another field");
          return;
        }
        var next = queue.shift();
        if (!next || ++row.skipped > 12) {
          emit("FAIL", "control signal produced no field intent");
          return;
        }
        chosen = next;
        row.key = chosen.field.key;
        row.control = interact(chosen.control);
        waited = 0;
        return;
      }
      queue = [];
      row.intentKeys = pendingSets();
      row.applyIntent = captureApplyIntent(row.intentKeys);
      row.intentValue = JSON.parse(row.applyIntent.find(intent => intent.key === row.key).value);
      check(popup.applySettings(), "Apply refused");
      waited = 0;
      phase = "applied";
    } else if (phase === "applied") {
      if (!receipt || popup.busy) {
        if (elapsed() >= nativeResultBudgetMs)
          emit("FAIL", "no Apply receipt");
        return;
      }
      row.applyMs = elapsed();
      if (receipt.status !== "saved" || receipt.refreshState !== "current") {
        emit("FAIL", "Apply receipt " + JSON.stringify(receipt));
        return;
      }
      row.afterApply = stored();
      for (var intent of row.applyIntent) {
        var present = Object.prototype.hasOwnProperty.call(row.afterApply, intent.key);
        if (present === intent.omitted || (present && jsonValue(row.afterApply[intent.key]) !== intent.value)) {
          emit("FAIL", "persisted value differs from intent " + intent.key);
          return;
        }
      }
      var touched = Object.keys(row.afterApply).concat(Object.keys(row.before)).filter(function (key, index, all) {
        return all.indexOf(key) === index && jsonValue(row.afterApply[key]) !== jsonValue(row.before[key]);
      });
      if (touched.indexOf(row.key) === -1 || touched.some(function (key) {
        return row.intentKeys.indexOf(key) === -1;
      })) {
        emit("FAIL", "Apply touched " + JSON.stringify(touched) + " for intents " + JSON.stringify(row.intentKeys));
        return;
      }
      receipt = null;
      waited = 0;
      row.resetRequested = [];
      phase = "staging-reset";
    } else if (phase === "staging-reset") {
      // One Reset control at a time, as a user would: native staging holds the draft busy.
      var waiting = row.intentKeys.filter(function (key) {
        return popup._pageApi.field(key).pendingIntent !== "reset";
      });
      if (waiting.length) {
        if (elapsed() >= nativeOpenBudgetMs) {
          emit("FAIL", "Reset not staged " + JSON.stringify(waiting));
          return;
        }
        if (popup._editor.busy || row.resetRequested.indexOf(waiting[0]) !== -1)
          return;
        row.resetRequested.push(waiting[0]);
        check(popup._pageApi.field(waiting[0]).reset(), "field Reset refused " + waiting[0]);
        return;
      }
      if (popup._editor.busy)
        return;
      check(popup.applySettings(), "Reset Apply refused");
      waited = 0;
      phase = "reset-applied";
    } else if (phase === "reset-applied") {
      if (!receipt || popup.busy) {
        if (elapsed() >= nativeResultBudgetMs)
          emit("FAIL", "no Reset receipt");
        return;
      }
      row.resetMs = elapsed();
      if (receipt.status !== "saved" || receipt.refreshState !== "current") {
        emit("FAIL", "Reset receipt " + JSON.stringify(receipt));
        return;
      }
      row.afterReset = stored();
      if (jsonValue(row.afterReset) !== jsonValue(row.before)) {
        emit("FAIL", "Reset did not restore stored state");
        return;
      }
      emit("PASS");
    } else if (phase === "closing") {
      if (popup.busy)
        return;
      if (popup.opened) {
        if (!popup.requestClose()) {
          popup.keepEditing();
          popup.confirmDiscard();
        }
        return;
      }
      if (popup._editor)
        return;
      waited = 0;
      if (scopeIndex + 1 < scopes.length) {
        scopeIndex++;
        phase = "next";
        return;
      }
      // Every live placement consumer on the shared owning leaf is refreshed
      // natively after each placement publication. Retire this plugin's
      // finished instance consumers through their owner, as a removed widget
      // would be, so later rows do not inherit an unbounded refresh backlog.
      phase = "retiring";
      PluginInstances.settlePlugin(pluginId, function (result) {
        try {
          root.check(result.status !== "failed", "retire instance consumers " + root.pluginId);
          root.scopeIndex = 0;
          root.pluginIndex++;
          root.phase = "next";
        } catch (error) {
          root.fail(error);
        }
      });
    } else if (phase === "retiring") {
      if (elapsed() >= nativeResultBudgetMs)
        fail("instance consumers of " + pluginId + " did not retire");
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 60
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        if (root.row)
          root.emit("FAIL", error);
        else
          root.fail(error);
      }
    }
  }
  Component.onCompleted: begin()
}
