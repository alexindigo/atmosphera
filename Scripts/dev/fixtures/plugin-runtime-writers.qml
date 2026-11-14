import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins

// Actual plugin Main writers -> native completion -> consumer; disk/cold oracle
// is in the guest runner. No page API or fabricated persistence result.
ShellRoot {
  id: root
  readonly property string name: Quickshell.env("I5_RUNTIME_PLUGIN")
  readonly property bool cold: Quickshell.env("I5_RUNTIME_COLD") === "1"
  property bool started: false
  property var api: null
  property var main: null
  property string phase: "opening"
  property int saved: 0
  function check(ok, label) { if (!ok) throw new Error("I5_RUNTIME_WRITER_ASSERT: " + name + " " + phase + " " + label); }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function begin() {
    if (started || !Settings.isLoaded) return;
    started = true;
    Service._openSettingsOwner(name, function (owner) {
      try {
        root.check(owner !== null, "actual native owner opened");
        var manifest = JSON.parse(Quickshell.env("I5_RUNTIME_MANIFEST"));
        root.api = Service.createPluginAPI(root.name, manifest, owner, {}, {}, {});
        var loaded = Object.assign({}, Service.loadedPlugins); loaded[root.name] = {api: root.api}; Service.loadedPlugins = loaded;
        owner.completed.connect(function (receipt) {
          console.log("I5_RUNTIME_WRITER_RECEIPT", root.name, root.phase, JSON.stringify(receipt));
          if (receipt.status === "saved") root.saved++;
          if (receipt.status === "failed") root.fail("I5_RUNTIME_WRITER_ASSERT: actual writer failed");
        });
        var component = Qt.createComponent("file://" + Registry.getPluginDir(root.name) + "/Main.qml");
        root.check(component.status === Component.Ready, component.errorString());
        root.main = component.createObject(root, {pluginApi: root.api});
        root.check(root.main !== null, "actual runtime Main created");
        root.phase = root.cold ? "cold" : root.name === "todo" ? "todo-initial" : "writer";
      } catch (error) { root.fail(error); }
    });
  }
  function drive() {
    if (!main) return;
    var cfg = api.pluginSettings;
    if (phase === "todo-initial") {
      check(main.rawPages.length === 2 && main.rawTodos.length === 2, "actual initial runtime arrays");
      saved = 0; phase = "writer";
      check(main.deletePage(7), "actual runtime page deletion accepted");
      return;
    }
    if (!cold && saved === 0) return;
    if (name === "todo") {
      check(cfg.pages.length === 1 && cfg.pages[0].id === 0, "deleted page absent from native namespace");
      check(cfg.current_page_id === 0 && cfg.count === 2 && cfg.completedCount === 1, "dependent native leaves reach consumers");
      check(main.rawPages.length === 1 && main.rawTodos.length === 2 && main.rawTodos.every(function (row) { return row.pageId === 0; }), "runtime arrays reflect reassignment");
      check(cfg.todos.every(function (row) { return row.pageId === 0 && row.opaque.keep; }), "moved todos retain opaque payload");
    } else if (name === "hermes-agent") {
      if (main.state.summary.model.name !== "runtime-model") return;
      check(cfg.configured && cfg.defaultModel === "runtime-model" && cfg.defaultProvider === "runtime-provider", "autoConfigure writes declared leaves");
      check(main.hermesCommand === "runtime-hermes" && main.expandedHermesHome === Quickshell.env("I5_RUNTIME_HOME"), "actual command/home consumers");
    } else {
      check(cfg.weekStart === "1" && cfg.timeFormat === "24h" && cfg.lineColorType === "mOutline", "initializer writes native leaves");
      check(main.firstDayOfWeek === 1 && !main.use12hourFormat && main.hourLineOpacitySetting === 0.5 && main.dayLineOpacitySetting === 1, "actual calendar consumers");
    }
    console.log("I5_RUNTIME_WRITERS: PASS", name, cold ? "cold" : "saved"); Qt.exit(0);
  }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Component.onCompleted: Qt.callLater(begin)
  Timer { interval: 50; repeat: true; running: true; onTriggered: { try { root.drive(); } catch (error) { root.fail(error); } } }
  Timer { interval: 25000; running: true; onTriggered: root.fail("I5_RUNTIME_WRITER_ASSERT: watchdog " + root.phase) }
}
