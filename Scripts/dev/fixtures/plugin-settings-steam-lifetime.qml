import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_STEAM_CASE")
  readonly property string test: Quickshell.env("PHA_STEAM_TEST")
  property var main: null
  property string phase: "start"
  property double since: Date.now()
  property int before: 0
  property bool destroyed: false
  property bool added: false
  readonly property string heldStage: ({
                                         "retire-query": "detect",
                                         "retire-all-query": "detect-all",
                                         "retire-move-all": "move-all",
                                         "retire-move": "move",
                                         "retire-show": "show",
                                         "retire-focus": "focus",
                                         "retire-focus-exec": "focus-exec",
                                         "retire-new": "new",
                                         "retire-new-move": "new-move"
                                       })[test] || ""
  onPhaseChanged: since = Date.now()
  QtObject {
    id: context
    property bool alive: true
    property var settingsView: ({
                                  gapSize: 30,
                                  friendsWidthPercent: 15,
                                  mainWidthPercent: 50,
                                  chatWidthPercent: 20,
                                  topMarginPercent: 4,
                                  windowHeightPercent: 80,
                                  useCustomLayout: root.test === "custom"
                                })
    function current() {
      return alive;
    }
  }
  QtObject {
    id: api
    property var pluginSettings: ({
                                    gapSize: 10,
                                    useCustomLayout: false
                                  })
    property var settingsContext: sharedContext
    property var manifest: ({
                              metadata: {
                                defaultSettings: {}
                              }
                            })
  }
  QtObject {
    id: sharedContext
    readonly property var settingsView: api.pluginSettings
    function current() {
      return true;
    }
  }
  Process {
    id: release
  }
  Item {
    id: content
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("STEAM_LIFETIME_ASSERT: " + test + "/" + phase + ": " + message);
  }
  function finish() {
    main.destroy();
    main = null;
    destroyed = true;
    phase = "joined";
  }
  function pass() {
    driver.stop();
    console.log("STEAM_LIFETIME: PASS " + test);
    Qt.exit(0);
  }
  Timer {
    id: driver
    interval: 40
    running: true
    repeat: true
    onTriggered: {
      try {
        root.check(Date.now() - root.since < 10000, "finite Steam phase");
        if (root.phase === "start") {
          const component = Qt.createComponent("file://" + root.base + "/config/plugins/hyprland-steam-overlay/Main.qml");
          root.check(component.status === Component.Ready, component.errorString());
          root.main = component.createObject(content, {
                                               pluginApi: api
                                             });
          root.check(root.main, "actual Main");
          root.phase = "ready";
        } else if (root.phase === "ready" && root.main.steamRunning && root.main.screenWidth === 2000 && root.main.luaModeProbed) {
          if (root.test === "launch")
            root.main.steamRunning = false;
          root.main.toggleOverlay(context);
          root.phase = "queried";
        } else if (root.phase === "queried" && root.test === "ordering-red" && Date.now() - root.since > 1300) {
          root.check(root.main.steamWindows.length === 3, "held first query eventually populated windows");
          root.check(!root.main.overlayActive && !root.rows().some(row => row.endpoint === "hyprctl" && row.argv[0] === "dispatch" && row.argv[1] !== "hl.dsp.no_op()"), "original first opening loses async continuation");
          root.finish();
        } else if (root.phase === "queried" && ["continuing", "retire-new-move"].includes(root.test) && root.main.overlayActive && !root.added) {
          root.added = true;
          context.settingsView = {
            gapSize: 0,
            useCustomLayout: true
          };
          release.command = ["touch", root.base + "/add-window"];
          release.running = true;
        } else if (root.phase === "queried" && ["classic", "lua", "custom"].includes(root.test) && root.rows().some(row => row.stage === "detect")) {
          context.settingsView = {
            gapSize: 0,
            useCustomLayout: root.test !== "custom"
          };
          root.main.luaMode = !root.main.luaMode;
          root.check(!root.main.toggleOverlay(sharedContext), "overlapping request cannot replace admitted policy");
          release.command = ["touch", root.base + "/release-detect"];
          release.running = true;
          root.phase = "opening";
        } else if (["queried", "opening"].includes(root.phase) && root.heldStage && root.rows().some(row => row.stage === root.heldStage)) {
          context.alive = false;
          root.before = root.rows().length;
          release.command = ["touch", root.base + "/release-" + root.heldStage];
          release.running = true;
          root.phase = "retired";
        } else if (root.phase === "retired" && Date.now() - root.since > 800) {
          const later = root.rows().slice(root.before);
          // The common pidof observer survives policy retirement. In an active
          // overlay, a pure new-window query already spawned before retirement
          // may log its child after the boundary; it must never dispatch an effect.
          root.check(later.every(row => row.endpoint === "pidof" || (["retire-new-move", "retire-active"].includes(root.test) && ((row.endpoint === "bash" && row.stage === "new") || (row.endpoint === "hyprctl" && row.argv[0] === "clients")))), "retired held stage has no later endpoint");
          root.check(!root.main.toggleOverlay(context), "retired caller refused");
          root.finish();
        } else if (root.phase === "queried" && root.test === "launch" && Date.now() - root.since > 500) {
          root.check(root.rows().some(row => row.endpoint === "steam" && row.argv[0] === "steam://open/main"), "existing Steam launch endpoint retained");
          root.check(!root.rows().some(row => row.stage === "detect"), "launch does not start overlay query");
          root.finish();
        } else if (["queried", "opening"].includes(root.phase) && root.main.overlayActive && !root.heldStage && Date.now() - root.since > 1700) {
          if (root.test === "retire-active") {
            context.alive = false;
            root.before = root.rows().length;
            root.phase = "retired";
          } else {
            if (root.test === "continuing")
              root.check(root.rows().some(row => row.stage === "new-move"), "continuing window uses active admitted policy");
            root.finish();
          }
        } else if (root.phase === "joined" && Date.now() - root.since > 400)
          root.pass();
      } catch (error) {
        driver.stop();
        console.error(String(error));
        Qt.exit(2);
      }
    }
  }
}
