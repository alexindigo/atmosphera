import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_CLIPBOARD_CASE")
  property var main: null
  property var client: null
  property var second: null
  property var item: null
  property string phase: "start"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var token: ({})
  property var before: null
  property bool alive: true
  property bool otherAlive: true
  property var config: ({
                          maxHistorySize: 2,
                          showImagePreviews: false,
                          density: "compact"
                        })
  property var otherConfig: ({
                               maxHistorySize: 4,
                               showImagePreviews: true,
                               density: "spacious"
                             })
  property QtObject context: QtObject {
    readonly property var settingsView: root.config
    readonly property bool alive: root.alive
    function current() {
      return alive;
    }
  }
  property QtObject otherContext: QtObject {
    readonly property var settingsView: root.otherConfig
    readonly property bool alive: root.otherAlive
    function current() {
      return alive;
    }
  }
  readonly property var sharedContext: ({
                                          current: function () {
                                            return true;
                                          },
                                          settingsView: {
                                            maxHistorySize: 6,
                                            showImagePreviews: false
                                          }
                                        })
  readonly property var api: ({
                                settingsContext: sharedContext,
                                pluginSettings: sharedContext.settingsView,
                                tr: function (key) {
                                  return key;
                                },
                                mainInstance: main
                              })
  PanelWindow {
    visible: true
    implicitWidth: 700
    implicitHeight: 600
    Item {
      id: content
      width: 700
      height: 600
    }
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: marker
    onExited: code => {
      if (code !== 0)
        root.fail("marker publication");
      else
        root.phase = root.afterMarker;
    }
  }
  property string afterMarker: ""
  function mark(name, after) {
    afterMarker = after;
    phase = "marker";
    marker.command = ["touch", base + "/" + name];
    marker.running = true;
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("CLIPBOARD_LIFETIME_ASSERT " + phase + ": " + message);
  }
  function fail(error) {
    driver.stop();
    console.error(String(error));
    Qt.exit(2);
  }
  function records(endpoint) {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line)).filter(row => row.endpoint === endpoint);
  }
  function create(file, properties) {
    const component = Qt.createComponent("file://" + base + "/config/plugins/clipboard/" + file);
    check(component.status === Component.Ready, component.errorString());
    const result = component.createObject(content, properties);
    check(result, "actual " + file);
    return result;
  }
  function drive() {
    check(Date.now() - since < 12000, "finite lifetime phase");
    if (phase === "start") {
      main = create("Main.qml", {
                      pluginApi: api
                    });
      client = main.settingsConsumerFor(context);
      second = main.settingsConsumerFor(otherContext);
      check(client === main.settingsConsumerFor(context) && client !== second, "API-keyed client identity");
      phase = "initial";
    } else if (phase === "initial" && client.items.length === 2 && second.items.length === 4 && main.items.length === 6) {
      before = JSON.stringify(main.copiedAt);
      main.pinnedItems = [
            {
              preview: "common-pin",
              type: "text"
            }
          ];
      config = {
        maxHistorySize: 0,
        showImagePreviews: false
      };
      phase = "zero";
    } else if (phase === "zero" && client.items.length === 0) {
      config = {
        maxHistorySize: -2,
        showImagePreviews: false
      };
      phase = "negative";
    } else if (phase === "negative" && client.items.length === 4) {
      config = {
        maxHistorySize: 2.5,
        showImagePreviews: false
      };
      phase = "fractional";
    } else if (phase === "fractional" && client.items.length === 0 && records("head").some(row => row.argv[1] === "2.5")) {
      check(before === JSON.stringify(main.copiedAt) && main.pinnedItems[0].preview === "common-pin", "selected limits preserve full timestamps and pins");
      config = {
        maxHistorySize: 3,
        showImagePreviews: true
      };
      phase = "projection-held";
    } else if (phase === "projection-held" && records("head").some(row => row.argv[1] === "3")) {
      config = {
        maxHistorySize: 2,
        showImagePreviews: true
      };
      phase = "projection-replaced";
    } else if (phase === "projection-replaced" && client.items.length === 2) {
      item = create("ClipboardItem.qml", {
                      pluginApi: {
                        settingsContext: context,
                        pluginSettings: config,
                        mainInstance: main
                      },
                      entryId: "91",
                      itemType: "image"
                    });
      phase = "decode";
    } else if (phase === "decode" && records("decode").some(row => row.id === "91")) {
      // Original Main's shared false preference refuses this actual delegate.
      main.getImage("91", otherContext);
      alive = false;
      phase = "coalesced";
    } else if (phase === "coalesced" && Date.now() - since > 200) {
      check(main.decodingId === "91", "coalesced current requester keeps decode alive");
      mark("release-91", "published");
    } else if (phase === "published" && main.imageCache["91"]) {
      item.destroy();
      main.getImage("92", otherContext);
      main.getImage("93", otherContext);
      phase = "held";
    } else if (phase === "held" && records("decode").some(row => row.id === "92")) {
      otherAlive = false;
      phase = "retired";
    } else if (phase === "retired" && Date.now() - since > 300) {
      check(!main.imageCache["92"] && !records("decode").some(row => row.id === "93"), "retired in-flight and queued decode cannot publish or launch");
      check(main._settingsConsumers.size === 0, "both retired clients released");
      main.destroy();
      main = null;
      phase = "joined";
    } else if (phase === "joined" && Date.now() - since > 300) {
      driver.stop();
      console.log("CLIPBOARD_LIFETIME: PASS");
      Qt.exit(0);
    }
  }
  Timer {
    id: driver
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
}
