pragma ComponentBehavior: Bound
import ConfigQml 1.0
import QtQuick
import Quickshell
// Inert I4 entrypoint. The runner copies it to the installed shell root.
import qs.Commons as Main

ShellRoot {
  id: root

  property int rejections: 0
  property int refusedEdits: 0
  property int acceptedEdits: 0
  readonly property var cfg: store.values

  // Both card consumers share scalar role access. QML's reserved `id` is
  // deliberately read through `model`, never declared as a required property
  // or fetched as ConfigNode.id. These adapters are not production imports.
  component CardAdapter: Item {
    id: cards
    required property var rows
    property bool weatherEnabled: false

    Repeater {
      id: repeated
      model: cards.rows
      delegate: Item {
        required property var model
        readonly property string cardId: model.id
        readonly property bool cardEnabled: model.enabled
        readonly property bool active: cardEnabled && (cardId !== "weather-card" || cards.weatherEnabled)
        readonly property var snapshot: model.modelData

        function rejectRoleEdit() {
          model.enabled = !cardEnabled;
        }
      }
    }

    function snapshot() {
      const result = [];
      for (let i = 0; i < repeated.count; i++) {
        const row = repeated.itemAt(i);
        result.push({
                      "id": row.cardId,
                      "enabled": row.cardEnabled,
                      "active": row.active
                    });
      }
      return result;
    }

    function retainRow(index) {
      return repeated.itemAt(index).snapshot;
    }

    function rejectRoleEdit() {
      repeated.itemAt(0).rejectRoleEdit();
    }
  }

  component BlacklistAdapter: Item {
    id: blacklist
    required property var rows
    required property var removePlayer

    Repeater {
      id: repeated
      model: blacklist.rows
      delegate: Item {
        required property string modelData
        required property var model

        function remove() {
          // The injected owner resolves the current value, not this row index.
          blacklist.removePlayer(modelData);
        }

        function rejectRoleEdit() {
          model.modelData = "unadmitted";
        }
      }
    }

    function snapshot() {
      const result = [];
      for (let i = 0; i < repeated.count; i++)
        result.push(repeated.itemAt(i).modelData);
      return result;
    }

    function removeRow(index) {
      repeated.itemAt(index).remove();
    }

    function rejectRoleEdit() {
      repeated.itemAt(0).rejectRoleEdit();
    }
  }

  component MenuAdapter: Item {
    id: menu
    required property var rows
    required property var removeItem
    property string generation: ""

    Repeater {
      id: repeated
      model: menu.rows
      delegate: Item {
        required property var model
        readonly property string itemId: model.id

        function rejectRoleEdit() {
          model.id = "unadmitted";
        }
      }
    }

    function snapshot() {
      const result = [];
      for (let i = 0; i < repeated.count; i++) {
        const row = rowAt(i);
        result.push(row.itemId);
      }
      return result;
    }

    function rowAt(index): var {
      return repeated.itemAt(index);
    }

    function removeRow(index) {
      // Repeated dividers are legitimate. An index is valid only with the
      // captured publication generation, never as a persistent placement ID.
      return removeItem(generation, index);
    }

    function rejectRoleEdit() {
      rowAt(0).rejectRoleEdit();
    }
  }

  ConfigStore {
    id: store
    autoSave: false
    sources: [
      MemorySource {}
    ]
    schema: Main.SettingsSchema {
      homeDirectory: "/inert/home"
      defaultFont: "Test Sans"
      fixedFont: "Test Mono"
    }
    onInputRejected: (path, code) => {
      root.check(code === "read-only-model", "unexpected rejection: " + code);
      root.rejections++;
    }
    onReadyChanged: {
      if (ready)
        Qt.callLater(root.start);
    }
  }

  CardAdapter {
    id: controlCenter
    rows: store.ready ? store.listModel(["controlCenter", "cards"]) : null
  }

  CardAdapter {
    id: calendar
    rows: store.ready ? store.listModel(["calendar", "cards"]) : null
  }

  BlacklistAdapter {
    id: blacklist
    rows: store.ready ? store.listModel(["audio", "mprisBlacklist"]) : null
    removePlayer: playerName => {
      const values = root.cfg.audio.mprisBlacklist.slice();
      const index = values.indexOf(playerName);
      if (index !== -1) {
        values.splice(index, 1);
        root.cfg.audio.mprisBlacklist = values;
      }
    }
  }

  MenuAdapter {
    id: menu
    rows: store.ready ? store.listModel(["desktopContextMenu", "items"]) : null
    removeItem: (expectedGeneration, index) => {
      const info = store.info(["desktopContextMenu", "items"]);
      if (info.publicationGeneration !== expectedGeneration || root.hasPendingInput(info)) {
        root.refusedEdits++;
        return false;
      }
      const values = root.cfg.desktopContextMenu.items.slice();
      if (index < 0 || index >= values.length)
        return false;
      values.splice(index, 1);
      root.cfg.desktopContextMenu.items = values;
      root.acceptedEdits++;
      return true;
    }
  }

  function check(condition, message) {
    if (!condition) {
      console.error("I4_MODEL_ADAPTERS: FAIL: " + message);
      Qt.exit(1);
      throw new Error(message);
    }
  }

  function equal(actual, expected, message) {
    check(JSON.stringify(actual) === JSON.stringify(expected), message);
  }

  function hasPendingInput(info) {
    // workerCovered can exceed this path's latestInput when another path
    // advances the store prefix. Compare decimal strings without Number loss.
    const latest = info.latestInput;
    const covered = info.workerCovered;
    return latest.length > covered.length || (latest.length === covered.length && latest > covered);
  }

  function fence(next) {
    store.flush(result => {
      check(result.status === "saved" || result.status === "nothing_to_save", "flush receipt failed");
      Qt.callLater(next);
    });
  }

  function start() {
    check(hasPendingInput({
                            latestInput: "10",
                            workerCovered: "9"
                          }), "decimal prefix ordering across digit boundary");
    check(!hasPendingInput({
                             latestInput: "9007199254740992",
                             workerCovered: "9007199254740993"
                           }), "covered prefix beyond JS safe integers");
    check(controlCenter.snapshot().length === 6 && calendar.snapshot().length === 3, "generated card defaults");
    equal(blacklist.snapshot(), [], "generated blacklist default");
    equal(menu.snapshot(), ["add-app-shortcut", "divider", "change-wallpaper", "display-settings", "toggle-edit-mode"], "generated menu default");
    check(!controlCenter.snapshot()[4].active && !calendar.snapshot()[2].active, "weather disabled");
    controlCenter.weatherEnabled = true;
    calendar.weatherEnabled = true;
    check(controlCenter.snapshot()[4].active && calendar.snapshot()[2].active, "weather enabled");
    store.values.controlCenter.cards = [
          {
            id: "audio-card",
            enabled: true
          },
          {
            id: "weather-card",
            enabled: false
          }
        ];
    store.values.calendar.cards = [
          {
            id: "weather-card",
            enabled: true
          },
          {
            id: "calendar-month-card",
            enabled: false
          }
        ];
    store.values.audio.mprisBlacklist = ["alpha", "beta", "gamma"];
    store.values.desktopContextMenu.items = [
          {
            id: "divider"
          },
          {
            id: "change-wallpaper"
          },
          {
            id: "divider"
          }
        ];
    fence(replaceEqualLength);
  }

  property var retainedCard: null

  function replaceEqualLength() {
    equal(controlCenter.snapshot(), [
            {
              id: "audio-card",
              enabled: true,
              active: true
            },
            {
              id: "weather-card",
              enabled: false,
              active: false
            }
          ], "first control-center publication");
    equal(calendar.snapshot(), [
            {
              id: "weather-card",
              enabled: true,
              active: true
            },
            {
              id: "calendar-month-card",
              enabled: false,
              active: false
            }
          ], "first calendar publication");
    equal(blacklist.snapshot(), ["alpha", "beta", "gamma"], "first primitive roles");
    equal(menu.snapshot(), ["divider", "change-wallpaper", "divider"], "duplicate dividers admitted");
    retainedCard = controlCenter.retainRow(0);
    store.values.controlCenter.cards = [
          {
            id: "weather-card",
            enabled: true
          },
          {
            id: "audio-card",
            enabled: false
          }
        ];
    store.values.calendar.cards = [
          {
            id: "calendar-header-card",
            enabled: true
          },
          {
            id: "weather-card",
            enabled: true
          }
        ];
    store.values.audio.mprisBlacklist = ["delta", "beta", "omega"];
    store.values.desktopContextMenu.items = [
          {
            id: "divider"
          },
          {
            id: "display-settings"
          },
          {
            id: "divider"
          }
        ];
    fence(checkEqualLength);
  }

  function checkEqualLength() {
    equal(controlCenter.snapshot(), [
            {
              id: "weather-card",
              enabled: true,
              active: true
            },
            {
              id: "audio-card",
              enabled: false,
              active: false
            }
          ], "equal-length card roles");
    equal(calendar.snapshot(), [
            {
              id: "calendar-header-card",
              enabled: true,
              active: true
            },
            {
              id: "weather-card",
              enabled: true,
              active: true
            }
          ], "equal-length calendar roles");
    equal(blacklist.snapshot(), ["delta", "beta", "omega"], "equal-length primitive roles");
    equal(menu.snapshot(), ["divider", "display-settings", "divider"], "equal-length menu roles");
    check(retainedCard.get("id").value === "audio-card", "retained node is an immutable old snapshot");
    for (const adapter of [controlCenter, calendar, blacklist, menu]) {
      try {
        adapter.rejectRoleEdit();
      } catch (error) {
        // The store also emits inputRejected; the count below is mandatory.
      }
    }
    check(rejections === 4, "all four model role writes rejected");
    check(store.values.controlCenter.cards[0].enabled && store.values.calendar.cards[0].enabled, "role edit cannot mutate cards");
    check(store.values.audio.mprisBlacklist[0] === "delta" && store.values.desktopContextMenu.items[0].id === "divider", "role edit cannot mutate primitive/menu");

    // Before yielding, the model is still the prior publication while getters
    // already contain the new list. Removing displayed 'beta' must not remove
    // the different value now occupying its old index.
    store.values.audio.mprisBlacklist = ["beta", "omega", "delta"];
    blacklist.removeRow(1);
    equal(store.values.audio.mprisBlacklist, ["omega", "delta"], "remove current value, not stale index");
    menu.generation = store.info(["desktopContextMenu", "items"]).publicationGeneration;
    store.values.desktopContextMenu.items = [
          {
            id: "display-settings"
          },
          {
            id: "divider"
          }
        ];
    check(!menu.removeRow(0) && refusedEdits === 1, "pending model-index edit refused");
    equal(store.values.desktopContextMenu.items, [
            {
              id: "display-settings"
            },
            {
              id: "divider"
            }
          ], "refusal retains newer list");
    store.values.controlCenter.cards = [
          {
            id: "audio-card",
            enabled: true
          }
        ];
    store.values.calendar.cards = [
          {
            id: "weather-card",
            enabled: false
          }
        ];
    fence(checkShrink);
  }

  function checkShrink() {
    equal(controlCenter.snapshot(), [
            {
              id: "audio-card",
              enabled: true,
              active: true
            }
          ], "control-center shrink");
    equal(calendar.snapshot(), [
            {
              id: "weather-card",
              enabled: false,
              active: false
            }
          ], "calendar shrink");
    equal(blacklist.snapshot(), ["omega", "delta"], "blacklist reorder/shrink");
    equal(menu.snapshot(), ["display-settings", "divider"], "menu reorder/shrink");
    check(!menu.removeRow(0) && refusedEdits === 2, "stale settled generation refused");
    menu.generation = store.info(["desktopContextMenu", "items"]).publicationGeneration;
    check(menu.removeRow(1) && acceptedEdits === 1, "current generation callback accepted");
    fence(finish);
  }

  function finish() {
    equal(menu.snapshot(), ["display-settings"], "injected menu edit reaches model consumer");
    equal(store.values.desktopContextMenu.items, [
            {
              id: "display-settings"
            }
          ], "final owning leaf");
    store.close(result => {
      check(result.status !== "failed", "close receipt");
      console.log("I4_MODEL_ADAPTERS: PASS (four boundaries; scalar roles, weather, equal replacement, reorder/shrink, read-only roles, current-value removal, generation fences)");
      Qt.quit();
    });
  }

  Timer {
    interval: 20000
    running: true
    onTriggered: root.check(false, "watchdog")
  }
}
