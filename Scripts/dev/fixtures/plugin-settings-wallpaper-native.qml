// Real generic pages/native documents -> originating inert wallpaper engines.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_WALLPAPER_PLUGIN")
  readonly property string scope: Quickshell.env("PHA_WALLPAPER_SCOPE")
  readonly property string mode: Quickshell.env("PHA_WALLPAPER_MODE")
  readonly property string boundary: Quickshell.env("PHA_WALLPAPER_BOUNDARY")
  readonly property bool toolOrigin: Quickshell.env("PHA_WALLPAPER_TOOL_ORIGIN") === "1"
  readonly property bool callerProof: Quickshell.env("PHA_WALLPAPER_CALLER_PROOF") === "1"
  readonly property string base: Quickshell.env("PHA_WALLPAPER_CASE")
  readonly property bool lwe: plugin === "linux-wallpaperengine-controller"
  readonly property string field: lwe ? "defaultFps" : "profile"
  property bool started: false
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: {
    since = Date.now();
    console.log("WALLPAPER_NATIVE_PHASE " + plugin + "/" + scope + "/" + mode + " " + phase + " " + since);
  }
  property var api: null
  property var contexts: []
  property var bars: []
  property var main: null
  property var receipt: null
  property string afterDisk: ""
  property string diskBoundary: ""
  property string actionBoundary: ""
  property int requestCount: 0
  property double actionSince: 0
  readonly property var target: scope === "shared" ? api : contexts[0]
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/" + root.plugin + "/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/" + root.plugin + "/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expected
    path: root.base + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete native documents: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  Process {
    id: release
    onExited: code => {
      if (code !== 0)
        root.fail("finite endpoint release failed: " + code);
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1280
    implicitHeight: 900
    Item {
      id: content
      width: 1280
      height: 900
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("WALLPAPER_NATIVE_ASSERT: " + plugin + "/" + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate, seen) {
    if (!object)
      return null;
    seen = seen || new Set();
    if (seen.has(object))
      return null;
    seen.add(object);
    if (object && predicate(object))
      return object;
    if (object?.item) {
      const result = find(object.item, predicate, seen);
      if (result)
        return result;
    }
    if (typeof object?.objectAt === "function" && typeof object.count === "number") {
      for (var index = 0; index < object.count; ++index) {
        const result = find(object.objectAt(index), predicate, seen);
        if (result)
          return result;
      }
    }
    for (const list of [object?.data, object?.children, object?.instances]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (const child of list) {
        const result = find(child, predicate, seen);
        if (result)
          return result;
      }
    }
    return null;
  }
  function create(entry, context) {
    const component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    const item = PluginLoader.createObject(plugin, entry, component, content, context, {
                                             screen: Quickshell.screens[0]
                                           });
    check(item, "actual " + entry + " constructs");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    const descriptor = JSON.parse(manifest.text()), translations = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      [plugin]: descriptor
    };
    Service._openSettingsOwner(plugin, function (owner) {
      try {
        check(owner, "native plugin owner");
        api = Service.createPluginAPI(plugin, descriptor, owner, translations, translations, {});
        Service.loadedPlugins = {
          [plugin]: {
            api: api
          }
        };
        if (lwe || mode !== "cold") {
          main = create("main", api);
          api.mainInstance = main;
        }
        contexts = [0, 1, 2].map(index => PluginInstances.apiFor(plugin, {
                                                                   kind: "bar",
                                                                   list: "global",
                                                                   section: "left",
                                                                   index: index
                                                                 }));
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function values(name) {
    expected.reload();
    expected.waitForJob();
    const document = JSON.parse(expected.text())[name];
    const shared = Object.assign({}, api.manifest.metadata.defaultSettings, document.shared);
    return [shared].concat(document.bar.widgets.left.map(row => Object.assign({}, shared, row.instanceSettings || {})));
  }
  function ready(name) {
    return [api].concat(contexts).every((context, index) => context.pluginSettings[field] === values(name)[index][field]) && (!lwe || !main.checkingEngine);
  }
  function probe(name, next) {
    diskBoundary = name;
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_WALLPAPER_DISK"), base, Quickshell.env("PHA_WALLPAPER_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, target, "settings"), "actual scoped page opens");
    phase = next;
  }
  function edit() {
    const control = find(popup.settingsPage, item => item.label === api.tr(lwe ? "settings.defaultFps.label" : "settings.profile.label") && (lwe ? item.valueModified !== undefined : item.selected !== undefined));
    check(control, "actual preference control");
    if (lwe)
      control.valueModified(29);
    else
      control.selected("fast");
    check(popup._pageApi.field(field).value === (lwe ? 29 : "fast"), "actual control intent");
    for (const key of Object.keys(api.manifest.metadata.settingsSchema.fields)) {
      if (key === field)
        continue;
      if (api.manifest.metadata.settingsSchema.fields[key].editorUsage === "configuration") {
        const handle = popup._pageApi.field(key);
        check(handle && !handle.pendingIntent, "untouched field: " + key);
      }
    }
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return String(requests.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function createColdPlayback() {
    // The cold reader owns the real playback child, but neither a runtime writer
    // nor Main's cache producer. Baseline effects are explicit inert collaborators;
    // their shared publication has its own individual lifetime gate.
    const source = `import QtQuick
import Qt.labs.folderlistmodel
import "file://${api.pluginDir}/main" as Product
Item {
  property var context
  readonly property var cfg: context?.settingsView ?? ({})
  FolderListModel { id: folder; showDirs: false }
  Product.Thumbnails {
    id: thumbnails; pluginApi: null; currentWallpaper: parent.cfg.currentWallpaper || ""; thumbCacheReady: true; folderModel: folder
    function startColorGen(context, path) { console.log("WALLPAPER_COLD_COLOR: inert " + path); }
  }
  Product.InnerService {
    id: baseline; pluginApi: null; currentWallpaper: parent.cfg.currentWallpaper || ""; oldWallpapers: ({}); thumbnails: thumbnails
    function saveOldWallpapers() { console.log("WALLPAPER_COLD_BASELINE: inert capture"); }
    function applyOldWallpapers() { console.log("WALLPAPER_COLD_BASELINE: inert restore"); }
  }
  Product.Mpvpaper {
    pluginApi: null; settingsContext: parent.context; runtimeWriter: null
    active: !!parent.context?.current() && (parent.cfg.active || false)
    currentWallpaper: parent.cfg.currentWallpaper || ""
    hardwareAcceleration: parent.cfg.hardwareAcceleration || false
    isPlaying: parent.cfg.isPlaying || false; isMuted: parent.cfg.isMuted || false
    mpvSocket: parent.cfg.mpvSocket || ""; profile: parent.cfg.profile || "default"
    fillMode: parent.cfg.fillMode || "fit"; volume: parent.cfg.volume || 100
    thumbnails: thumbnails; innerService: baseline
  }
}`;

    main = Qt.createQmlObject(source, content, "wallpaper-cold-playback");
    check(main, "actual playback child without cache/native writer");
    main.context = target.settingsContext;
  }
  function startAction(name) {
    actionBoundary = name;
    requestCount = rows().length;
    actionSince = Date.now();
    console.log("WALLPAPER_NATIVE_POLICY admission " + JSON.stringify({
                                                                        stored: target.pluginSettings[field],
                                                                        view: target.settingsContext.settingsView[field],
                                                                        derived: main?.profile,
                                                                        selected: main?.policyContext === target.settingsContext
                                                                      }));
    if (lwe) {
      if (mode === "cold")
        main.reload(false, target.settingsContext);
      else {
        const menu = find(bars[scope === "shared" ? 0 : 1], item => item.triggered !== undefined);
        check(menu, "originating Bar menu");
        menu.triggered("start", null);
      }
    } else if (mode === "cold")
      createColdPlayback();
    else if (callerProof) {
      // Establish a different current owner before the real selected view's
      // action. The caller must select its own policy, not retain Main's last.
      main.activatePolicy(api.settingsContext);
      const menu = find(bars[1], item => item.triggered !== undefined);
      check(menu, "originating Bar play menu");
      menu.triggered("play", null);
    } else {
      const menu = find(bars[scope === "shared" ? 0 : 1], item => item.triggered !== undefined);
      check(menu, "originating Bar menu");
      if (target.pluginSettings.active)
        menu.triggered("toggle", null);
      const processes = rows().filter(row => row.endpoint === "mpvpaper");
      release.command = ["python3", "-c",
                         "import json,sys,time; from pathlib import Path; b=Path(sys.argv[1]); p=json.loads(sys.argv[2]); (b/'release-engine').touch(); live=lambda r: (s:=Path('/proc')/str(r['pid'])/'stat').exists() and s.read_text().split(') ',1)[1].split()[19]==r['start']; end=time.monotonic()+5\nwhile any(live(r) for r in p):\n if time.monotonic()>end: raise SystemExit('previous playback endpoint survived')\n time.sleep(.02)\n(b/'release-engine').unlink()",
                         base, JSON.stringify(processes)];
      release.running = true;
      phase = "disabled";
      return;
    }
    phase = "effect";
  }
  function effect() {
    const endpoint = rows().slice(requestCount).filter(row => row.endpoint === (lwe ? "linux-wallpaperengine" : "mpvpaper") && !row.argv.includes("--help")).pop();
    if (!endpoint || Date.now() - actionSince < 350)
      return;
    const value = values(actionBoundary)[scope === "shared" ? 0 : 1][field];
    console.log("WALLPAPER_NATIVE_POLICY endpoint " + JSON.stringify({
                                                                       stored: target.pluginSettings[field],
                                                                       view: target.settingsContext.settingsView[field],
                                                                       derived: main?.profile,
                                                                       selected: main?.policyContext === target.settingsContext,
                                                                       request: endpoint
                                                                     }));
    check(lwe ? endpoint.argv[endpoint.argv.indexOf("--fps") + 1] === String(value) : endpoint.argv.join(" ").includes("profile='" + value + "'"), "actual selected wallpaper policy reaches inert engine");
    console.log("WALLPAPER_NATIVE_EFFECT " + JSON.stringify({
                                                              boundary: actionBoundary,
                                                              request: endpoint
                                                            }));
    // An inert endpoint has a finite lifetime; production playback is a
    // continuing operation. Admit its normal explicit Stop before releasing it,
    // rather than manufacture a recorder/engine crash at the read boundary.
    if (lwe)
      main.stopAll();
    if (mode === "cold")
      phase = "release";
    else {
      phase = "settling";
      Service.waitForPluginSaves(target, result => {
        try {
          check(["saved", "nothing_to_save"].includes(result.status), "originating action publication completes");
          Service.waitForPluginSaves(api, sharedResult => {
            try {
              check(["saved", "nothing_to_save"].includes(sharedResult.status), "shared operational publication completes");
              probe(actionBoundary, "release");
            } catch (error) {
              fail(error);
            }
          }, false);
        } catch (error) {
          fail(error);
        }
      }, false);
    }
  }
  function drive() {
    check(Date.now() - since < 18000, "finite native/action phase deadline");
    if (phase === "runtime" && contexts.every(context => context.settingsReady)) {
      if (mode !== "cold" && !toolOrigin)
        bars = [api].concat(contexts).map(context => create("barWidget", context));
      phase = "initial";
    } else if (phase === "initial") {
      const name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name) || (mode !== "cold" && Date.now() - since < 350))
        return;
      if (mode === "cold")
        startAction(name);
      else
        phase = mode === "edit" ? "initial-disk" : mode === "follow" ? "change-base" : "open-reset";
    } else if (phase === "initial-disk")
      probe("initial", "open-discard");
    else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "construction has no intent");
      edit();
      check(!popup.requestClose(), "dirty close refuses");
      popup.confirmDiscard();
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor)
      probe("discarded", "open-edit");
    else if (phase === "open-edit")
      open("edit-page");
    else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
      edit();
      apply("applied");
    } else if (phase === "applied" && accepted() && ready("edited"))
      probe("edited", toolOrigin ? "tool-action" : "edited-effect");
    else if (phase === "tool-action") {
      const tools = find(popup.settingsPage, item => typeof item.toggleMute === "function" && typeof item.clear === "function");
      const clear = find(tools, item => item.icon === "clear-all" && item.clicked !== undefined);
      check(clear, "actual Settings Clear control without runtime view");
      clear.clicked();
      check(popup._pageApi.field("currentWallpaper").value === "" && popup.dirty, "Clear stages selected field and page preview");
      check(api.pluginSettings.currentWallpaper === values("edited")[0].currentWallpaper, "staged Clear does not touch shared runtime values");
      probe("edited", "tool-discard");
    } else if (phase === "tool-discard") {
      check(!popup.requestClose(), "staged Clear refuses unconfirmed Close");
      popup.confirmDiscard();
      phase = "tool-discarded";
    } else if (phase === "tool-discarded" && !popup.opened && !popup._editor)
      probe("edited", "tool-reopen");
    else if (phase === "tool-reopen")
      open("tool-apply-page");
    else if (phase === "tool-apply-page" && popup.opened && popup.settingsPage) {
      const tools = find(popup.settingsPage, item => typeof item.toggleMute === "function" && typeof item.clear === "function");
      const clear = find(tools, item => item.icon === "clear-all" && item.clicked !== undefined);
      check(clear, "reopened actual Clear control");
      clear.clicked();
      check(popup._pageApi.field("currentWallpaper").value === "", "reopened Clear preview");
      apply("tool-applied");
    } else if (phase === "tool-applied" && accepted())
      probe("tool-clear", "tool-done");
    else if (phase === "tool-done") {
      console.log("WALLPAPER_NATIVE: PASS " + plugin + " " + scope + " " + mode + " " + boundary);
      Qt.exit(0);
    } else if (phase === "edited-effect")
      startAction("edited");
    else if (phase === "open-reset")
      open("reset-page");
    else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field(field).reset(), "native staged Reset");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-effect");
    else if (phase === "reset-effect")
      startAction("reset");
    else if (phase === "change-base") {
      api.pluginSettings[field] = lwe ? 37 : "high-quality";
      phase = "base-saving";
      api.saveSettings(result => {
        try {
          check(result.status === "saved", "native inherited publication");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following"))
      probe("following", "following-effect");
    else if (phase === "following-effect")
      startAction("following");
    else if (phase === "disabled" && !target.pluginSettings.active && !release.running) {
      const menu = find(bars[scope === "shared" ? 0 : 1], item => item.triggered !== undefined);
      menu.triggered("toggle", null);
      phase = "effect";
    } else if (phase === "effect")
      effect();
    else if (phase === "release") {
      release.command = ["touch", base + "/release-engine"];
      release.running = true;
      phase = "finish";
    } else if (phase === "finish" && !release.running) {
      console.log("WALLPAPER_NATIVE: PASS " + plugin + " " + scope + " " + mode + " " + boundary);
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 40
    running: true
    repeat: true
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
