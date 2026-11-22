import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_CONTEXT_SCOPE")
  readonly property bool original: Quickshell.env("PHA_CONTEXT_ORIGINAL") === "1"
  property bool started: false
  property string phase: "opening"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var owner: null
  property var api: null
  property var placed: null
  property var context: null
  property var replacement: null
  property var descriptor: null
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/catwalk/manifest.json"
    blockLoading: true
  }
  Component {
    id: placementFactory
    PluginInstanceApi {}
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("CONTEXT_ASSERT: " + scope + "/" + phase + ": " + message);
  }
  function fail(error) {
    driver.stop();
    console.error(String(error));
    Qt.exit(2);
  }
  function shared() {
    const result = Service.createPluginAPI("catwalk", descriptor, owner, {}, {}, {});
    Service.loadedPlugins = {
      catwalk: {
        api: result
      }
    };
    return result;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    descriptor = JSON.parse(manifest.text());
    Registry.installedPlugins = {
      catwalk: descriptor
    };
    Service._openSettingsOwner("catwalk", opened => {
      try {
        check(opened, "actual native owner");
        owner = opened;
        api = shared();
        if (scope === "instance")
          placed = placementFactory.createObject(root, {
                                                   base: api,
                                                   placement: {
                                                     kind: "bar",
                                                     list: "global",
                                                     section: "left",
                                                     index: 0
                                                   }
                                                 });
        phase = "ready";
      } catch (error) {
        fail(error);
      }
    });
  }
  function retired() {
    let current, values, currentError = "", readError = "";
    // Independent callbacks: a failing current() must not mask a failing getter.
    try {
      current = context.current();
    } catch (error) {
      currentError = String(error);
    }
    try {
      values = context.settingsView;
    } catch (error) {
      readError = String(error);
    }
    if (original) {
      console.log("CONTEXT_ORIGINAL_OBSERVATION " + JSON.stringify({
                                                                     scope: scope,
                                                                     current: current,
                                                                     currentType: typeof current,
                                                                     currentError: currentError,
                                                                     readError: readError,
                                                                     keys: values ? Object.keys(values) : null
                                                                   }));
      if (scope === "instance") {
        check(currentError.indexOf("TypeError: Cannot read property") === 0 && readError.indexOf("TypeError: Cannot read property") === 0, "original placement callbacks dereference destroyed QObject");
      } else {
        check(!currentError && current === undefined && !readError && Object.keys(values).length === 0, "original shared current has no explicit refusal result");
      }
      console.log("CONTEXT_RED: " + scope + " reproduced");
    } else {
      check(!currentError && !readError, "retained callbacks never throw");
      check(current === false, "retired current explicitly false");
      check(values && Object.keys(values).length === 0 && Object.isFrozen(values), "retired read explicitly empty and immutable");
      check(Object.isFrozen(context), "retained capability remains immutable");
    }
  }
  function drive() {
    check(Date.now() - since < 15000, "finite native lifetime phase");
    if (phase === "ready" && api.settingsReady && (scope !== "instance" || placed.settingsReady)) {
      const target = scope === "instance" ? placed : api;
      context = target.settingsContext;
      check(context === target.settingsContext && context.current(), "stable live context");
      check(context.settingsView.minimumThreshold === (scope === "instance" ? 30 : 20), "actual selected native values");
      check(Object.isFrozen(context.settingsView), "live read is immutable");
      if (scope === "shared" && !original) {
        // Registration loss retires both callbacks before QObject destruction.
        Service.loadedPlugins = {};
        retired();
      }
      target.destroy();
      phase = "destroyed";
    } else if (phase === "destroyed" && Date.now() - since > 100) {
      check(scope === "instance" ? !placed : !api, "API QObject is actually gone");
      retired();
      if (original) {
        driver.stop();
        console.log("CONTEXT_LIFETIME: PASS " + scope);
        Qt.exit(0);
        return;
      }
      if (scope === "shared")
        api = shared();
      replacement = scope === "instance" ? placementFactory.createObject(root, {
                                                                           base: api,
                                                                           placement: {
                                                                             kind: "bar",
                                                                             list: "global",
                                                                             section: "left",
                                                                             index: 0
                                                                           }
                                                                         }) : api;
      phase = "replacement";
    } else if (phase === "replacement" && replacement.settingsReady) {
      check(replacement.settingsContext !== context && replacement.settingsContext.current(), "replacement has independent live identity");
      check(replacement.settingsContext.settingsView.minimumThreshold === (scope === "instance" ? 30 : 20), "replacement native read remains usable");
      retired();
      replacement.destroy();
      phase = "joined";
    } else if (phase === "joined" && Date.now() - since > 100) {
      retired();
      driver.stop();
      console.log("CONTEXT_LIFETIME: PASS " + scope);
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  SettingsBootstrap {}
  Timer {
    id: driver
    interval: 40
    repeat: true
    running: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Component.onCompleted: begin()
}
