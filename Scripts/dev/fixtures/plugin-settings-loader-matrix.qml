// Named-guest construction matrix. The admitted page capability comes from a
// real selected native session; runtime APIs must fail before page creation.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  property bool started: false
  property string phase: "owner"
  property double deadline: Date.now() + 30000
  property var api: null
  property var instanceApi: null
  property var rows: []
  property int position: 0
  property var subject: null
  property var piece: null
  property var initial: null
  property var context: ({
                           screen: Quickshell.screens[0]
                         })
  readonly property string fixtureRoot: "file://" + Settings.configDir + "plugins/loader-matrix/"
  readonly property string selectedPath: Quickshell.env("PHA_LOADER_PATH") || ""

  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/loader-matrix/manifest.json"
    blockLoading: true
    printErrors: false
  }
  PluginSettingsSession {
    id: session
    commitInputs: function () {}
    captureInputs: function () {
      return 0;
    }
    acknowledgeInputs: function (revision) {}
    resetInputs: function () {}
    onOpeningFailed: root.fail("native selected session opening")
  }
  Component {
    id: viewFactory
    PluginView {
      asynchronous: false
    }
  }
  Component {
    id: loaderFactory
    Loader {
      asynchronous: false
    }
  }

  function check(ok, message) {
    if (!ok)
      throw new Error("LOADER_ASSERT: " + message);
  }
  function fail(message) {
    console.error(String(message));
    Qt.exit(2);
  }
  function emitRow(data) {
    console.log("LOADER_ROW " + JSON.stringify(data));
  }
  function start() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      "loader-matrix": manifest
    };
    Service._openSettingsOwner("loader-matrix", function (owner) {
      try {
        check(owner !== null, "native owner");
        root.api = Service.createPluginAPI("loader-matrix", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          "loader-matrix": {
            api: root.api
          }
        };
        Settings.data.bar.widgets.left = [
              {
                id: "plugin:loader-matrix"
              }
            ];
        Settings.saveSelected([["bar", "widgets", "left"]], function (result) {
          try {
            check(result.status !== "failed", "placement seed");
            root.instanceApi = PluginInstances.apiFor("loader-matrix", {
                                                        kind: "bar",
                                                        list: "global",
                                                        section: "left",
                                                        index: 0
                                                      });
            root.phase = "runtime";
          } catch (error) {
            root.fail(error);
          }
        });
      } catch (error) {
        root.fail(error);
      }
    });
  }
  function next() {
    if (position === rows.length) {
      // No page intent is submitted by any construction. The driver also
      // independently checks both source files after nonpublishing Close.
      check(!session.editor.dirty && !session.fields.error, "construction is nonpublishing");
      session.confirmDiscard();
      session.presentationClosed();
      PluginInstances.settlePlugin("loader-matrix", function () {
        console.log("PLUGIN_SETTINGS_LOADER_MATRIX: PASS");
        Qt.exit(0);
      });
      phase = "settled";
      return;
    }
    var row = rows[position];
    var key = "matrix-" + position;
    var url = fixtureRoot + row.style + ".qml?v=" + position;
    var selectedApi = row.role === "editor" ? session.pageApi : row.role === "shared" ? api : instanceApi;
    var entry = row.entry;
    var ctx = context;
    piece = null;
    subject = null;
    initial = null;
    if (row.path === "direct") {
      var component = Qt.createComponent(url);
      check(component.status === Component.Ready, "matrix component compiles: " + component.errorString());
      piece = PluginLoader.createObject(key, entry, component, root, selectedApi, ctx);
    } else if (row.path === "view") {
      subject = viewFactory.createObject(root, {
                                           pluginKey: key,
                                           entryPoint: entry,
                                           url: url,
                                           api: selectedApi,
                                           context: ctx
                                         });
    } else {
      subject = loaderFactory.createObject(root);
      try {
        initial = PluginLoader.initialProperties(entry, url, selectedApi, ctx);
        subject.setSource(url, initial);
      } catch (error) {
        check(String(error).indexOf("settings-editor-api-required") !== -1, "raw loader reports actionable role error");
      }
      if (subject.item) {
        piece = subject.item;
        PluginLoader.applyLateContext(piece, entry, ctx, initial);
      }
    }
    phase = "observe";
    deadline = Date.now() + 15000;
  }
  function observe() {
    var row = rows[position];
    var key = "matrix-" + position;
    if (row.path === "view") {
      if (!subject.item && !subject.failed)
        return;
      piece = subject.item;
    }
    var refused = row.entry === "settings" && row.role !== "editor";
    if (refused) {
      check(!piece, "runtime " + row.role + " API rejected before " + row.path + " creation (" + row.style + ")");
      if (row.path !== "loader") {
        var error = Service.pluginErrors[key];
        check(error && error.entryPoint === "settings" && error.error.indexOf("settings-editor-api-required") !== -1, "runtime " + row.role + " API actionable " + row.path + " error");
      }
    } else {
      check(!!piece, "admitted " + row.path + " construction: " + row.style);
      var expected = row.role === "editor" ? session.pageApi : row.role === "shared" ? api : instanceApi;
      check(piece.pluginApi === expected && piece.completedApi, "initial API before first binding");
      if (row.entry === "settings" || row.style === "bare") {
        check(row.style === "bare" ? !("screen" in piece) : piece.screen === null, "uncontracted context skipped");
      } else {
        check(piece.screen === context.screen, "panel context reaches selected property");
        check(row.style === "declares" ? piece.completedScreen === context.screen : piece.completedScreen === null, "root versus inherited construction order");
      }
    }
    emitRow(Object.assign({}, row, {
                            status: "PASS",
                            refused: refused
                          }));
    // Exercise PluginView's context update, not just initial creation.
    if (!refused && row.entry === "panel" && row.style !== "bare") {
      if (row.path === "view")
        subject.context = {
          screen: null
        };
      else
      PluginLoader.applyLateContext(piece, row.entry, {
                                      screen: null
                                    }, initial || {});
      phase = "late";
      return;
    }
    finishRow();
  }
  function finishRow() {
    if (piece && !subject)
      piece.destroy();
    if (subject)
      subject.destroy();
    piece = null;
    subject = null;
    position++;
    phase = "next";
  }
  Timer {
    interval: 30
    running: true
    repeat: true
    onTriggered: {
      try {
        if (Date.now() > root.deadline && root.phase !== "settled")
          throw new Error("LOADER_ASSERT: deadline " + root.phase + " " + root.position);
        if (!root.started)
          root.start();
        if (root.phase === "runtime" && root.instanceApi?.settingsReady) {
          check(session.openPluginSettings(Registry.getPluginManifest("loader-matrix"), "settings"), "selected native editor requested");
          root.phase = "session";
        } else if (root.phase === "session" && session.pageApi) {
          for (var path of ["direct", "view", "loader"])
            for (var style of ["declares", "inherits", "bare"])
              for (var role of ["editor", "shared", "instance"])
                if (!root.selectedPath || path === root.selectedPath)
                  root.rows.push({
                                   path: path,
                                   style: style,
                                   role: role,
                                   entry: "settings"
                                 });
          for (var path of ["direct", "view", "loader"])
            for (var style of ["declares", "inherits", "bare"])
              if (!root.selectedPath || path === root.selectedPath)
                root.rows.push({
                                 path: path,
                                 style: style,
                                 role: "shared",
                                 entry: "panel"
                               });
          root.phase = "next";
        } else if (root.phase === "next")
          root.next();
        else if (root.phase === "observe")
          root.observe();
        else if (root.phase === "late") {
          check(root.piece.screen === null, "late context update without replacement");
          root.finishRow();
        }
      } catch (error) {
        root.fail(error);
      }
    }
  }
}
