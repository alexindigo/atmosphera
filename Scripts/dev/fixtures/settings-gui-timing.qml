// Guest-only observer/workload, dynamically attached to an elected full shell.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI

Item {
  id: probe
  property var keys: Qt.createComponent(Quickshell.shellDir + "/Scripts/dev/fixtures/launcher-key-owner-probe.qml").createObject(probe)
  property bool measuring: false
  property double lastTick: 0
  property double worstLate: 0
  property int ticks: 0
  property var lateTicks: []
  property var latenessDistribution: ({})
  property int round: -1
  property var completions: []
  property int gcCount: 0
  property int notifications: 0
  readonly property bool nativeOwner: Settings["store"] !== undefined
  readonly property var ccModel: nativeOwner ? Settings["store"].listModel(["controlCenter", "cards"]) : Settings.data.controlCenter.cards
  readonly property var clockModel: nativeOwner ? Settings["store"].listModel(["calendar", "cards"]) : Settings.data.calendar.cards
  readonly property var audioModel: nativeOwner ? Settings["store"].listModel(["audio", "mprisBlacklist"]) : Settings.data.audio.mprisBlacklist
  readonly property var desktopModel: nativeOwner ? Settings["store"].listModel(["desktopContextMenu", "items"]) : Settings.data.desktopContextMenu.items

  Timer {
    interval: 5
    repeat: true
    running: probe.measuring
    onTriggered: {
      const now = Date.now();
      const late = Math.max(0, now - probe.lastTick - interval);
      probe.worstLate = Math.max(probe.worstLate, late);
      probe.ticks++;
      probe.latenessDistribution[late] = (probe.latenessDistribution[late] || 0) + 1;
      if (late > 16)
        probe.lateTicks.push({
                               at: now,
                               latenessMs: late
                             });
      probe.lastTick = now;
    }
  }

  // Four simultaneously rendered model consumers, including actual role reads.
  // The full production shell remains active alongside this observer window.
  PanelWindow {
    anchors {
      right: true
      bottom: true
    }
    implicitWidth: 600
    implicitHeight: 120
    exclusiveZone: -1
    color: "#202020"
    Row {
      anchors.fill: parent
      ListView {
        id: ccView
        width: 150
        height: 120
        clip: true
        model: probe.ccModel
        delegate: Text {
          required property var model
          required property int index
          readonly property var row: probe.nativeOwner ? model : model.modelData
          width: 150
          height: 20
          color: "white"
          text: row.id + ":" + row.enabled
        }
      }
      ListView {
        id: clockView
        width: 150
        height: 120
        clip: true
        model: probe.clockModel
        delegate: Text {
          required property var model
          required property int index
          readonly property var row: probe.nativeOwner ? model : model.modelData
          width: 150
          height: 20
          color: "white"
          text: row.id + ":" + row.enabled
        }
      }
      ListView {
        id: audioView
        width: 150
        height: 120
        clip: true
        model: probe.audioModel
        delegate: Text {
          required property string modelData
          width: 150
          height: 20
          color: "white"
          text: modelData
        }
      }
      ListView {
        id: desktopView
        width: 150
        height: 120
        clip: true
        model: probe.desktopModel
        delegate: Text {
          required property var model
          required property int index
          readonly property var row: probe.nativeOwner ? model : model.modelData
          width: 150
          height: 20
          color: "white"
          text: row.id
        }
      }
    }
  }

  function save(label) {
    const started = Date.now();
    Settings.saveImmediate(function (result, message) {
      const status = typeof result === "boolean" ? (result ? "saved" : "failed") : result.status;
      const receipt = {
        round: probe.round,
        label: label,
        status: status,
        started: started,
        completed: Date.now(),
        message: message || ""
      };
      probe.completions.push(receipt);
      console.log("GUI_TIMING_SAVE " + JSON.stringify(receipt));
    });
  }

  function burst(number) {
    round = number;
    console.log("GUI_TIMING_PHASE " + JSON.stringify({
                                                       phase: "burst",
                                                       round: round,
                                                       at: Date.now()
                                                     }));
    // Scalar slider-like ingress, equality/no-op saves, record/list publication,
    // real notification listeners/views and a full 1000-row replace/reorder.
    for (let i = 0; i < 5; ++i)
      Settings.data.bar.widgetSpacing = 4 + ((number + i) % 5);
    Settings.data.notifications.enableKeyboardLayoutToast = number % 2 === 0;
    const audio = [];
    for (let i = 0; i < 1000; ++i)
      audio.push("i6-" + number + "-" + i);
    if (number % 2)
      audio.reverse();
    Settings.data.audio.mprisBlacklist = audio;
    const cards = Settings.data.controlCenter.cards.slice();
    cards.reverse();
    Settings.data.controlCenter.cards = cards;
    const calendar = Settings.data.calendar.cards.slice();
    calendar.reverse();
    Settings.data.calendar.cards = calendar;
    const desktop = Settings.data.desktopContextMenu.items.slice();
    desktop.reverse();
    Settings.data.desktopContextMenu.items = desktop;
    const widgets = Settings.data.bar.widgets.left.slice();
    if (widgets.length) {
      const first = Object.assign({}, widgets[0]);
      first.compactMode = number % 2 === 0;
      widgets[0] = first;
      Settings.data.bar.widgets.left = widgets;
    }
    save("burst");
    save("joined-or-noop");
    ToastService.showNotice("I6 settings burst " + number, "Native GUI timing", "", 100);
    notifications++;
    gc();
    gcCount++;
    console.log("GUI_TIMING_PHASE " + JSON.stringify({
                                                       phase: "ingress-gc-return",
                                                       round: round,
                                                       at: Date.now()
                                                     }));
  }

  function viewText(view) {
    const item = view.itemAtIndex(0);
    return item ? item.text : null;
  }

  IpcHandler {
    target: "guiTiming"
    function start(): void {
      probe.worstLate = 0;
      probe.ticks = 0;
      probe.lateTicks = [];
      probe.latenessDistribution = ({});
      probe.lastTick = Date.now();
      probe.measuring = true;
    }
    function burst(number: int): void {
      probe.burst(number);
    }
    function noop(): void {
      probe.save("settled-noop");
    }
    function collect(): void {
      gc();
      probe.gcCount++;
    }
    function stop(): string {
      probe.measuring = false;
      return JSON.stringify({
                              ticks: probe.ticks,
                              worstLate: probe.worstLate,
                              latenessDistribution: probe.latenessDistribution,
                              violationsOver16ms: probe.lateTicks
                            });
    }
    function input(text: string): void {
      Settings.data.audio.preferredPlayer = text;
      probe.save("input-persistence");
    }
    function closeLauncher(): void {
      PanelService.closeLauncher(PanelService.findFallbackScreen());
    }
    function quit(): void {
      Qt.quit();
    }
    function status(): string {
      return JSON.stringify({
                              loaded: Settings.isLoaded,
                              nativeOwner: probe.nativeOwner,
                              round: probe.round,
                              spacing: Settings.data.bar.widgetSpacing,
                              preferredPlayer: Settings.data.audio.preferredPlayer,
                              audioCount: audioView.count,
                              audioFirst: probe.viewText(audioView),
                              counts: [ccView.count, clockView.count, audioView.count, desktopView.count],
                              first: [probe.viewText(ccView), probe.viewText(clockView), probe.viewText(audioView), probe.viewText(desktopView)],
                              completions: probe.completions,
                              notifications: probe.notifications,
                              gcCount: probe.gcCount
                            });
    }
  }
}
