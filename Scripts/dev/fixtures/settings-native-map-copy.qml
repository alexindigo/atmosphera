import QtQuick
import Quickshell
import ConfigQml 1.0

// Characterize an owned native record copy without converting opaque integer
// members through JavaScript numbers. The declared map is one atomic leaf.
ShellRoot {
  id: root
  property bool started: false
  readonly property string file: Quickshell.env("I5_MAP_FILE")
  function check(ok, label) { if (!ok) throw new Error("I5_MAP_COPY_ASSERT: " + label); }
  function own(value, key) { return Object.getOwnPropertyDescriptor(value, key)?.value; }
  ConfigStore {
    id: store
    autoSave: false
    schema: ConfigSchema {
      ConfigValue {
        key: "monitors"
        valueType: ConfigValue.Map
        defaultValue: ({})
        ConfigValue {
          valueType: ConfigValue.Record
          open: true
          ConfigValue { key: "label"; valueType: ConfigValue.String; optional: true }
        }
      }
    }
    sources: [JsonFileSource {
      sourceId: "user"; layerId: "user"; path: root.file
      writable: true; optional: true; unknownData: JsonFileSource.Preserve
    }]
  }
  function begin() {
    if (started || !store.ready) return;
    started = true;
    try {
      var prefix = store.info(["monitors"]).latestInput;
      var original = store.values.monitors;
      var map = store.copyValue(original);
      var sourceRecord = own(original, "__proto__");
      var record = store.copyValue(sourceRecord);
      record.label = "edited";
      check(Object.prototype.hasOwnProperty.call(record, "wide"), "opaque member survives changed-record copy");
      check(own(store.values.monitors, "__proto__").label === "original", "record copy is detached from owner");
      check(store.info(["monitors"]).latestInput === prefix, "copy mutation admits no owner input");
      map["__proto__"] = record;
      store.values.monitors = map;
      check(Number(store.info(["monitors"]).latestInput) === Number(prefix) + 1, "one complete map assignment");
      store.save(function (result) {
        try {
          check(result.status === "saved", "copy save receipt");
          check(own(store.values.monitors, "__proto__").label === "edited", "map consumer sees edited field");
          store.close(function () { console.log("I5_MAP_COPY: PASS"); Qt.exit(0); });
        } catch (error) { console.error(String(error)); Qt.exit(2); }
      });
    } catch (error) { console.error(String(error)); Qt.exit(2); }
  }
  Component.onCompleted: Qt.callLater(begin)
  Timer { interval: 10; repeat: true; running: true; onTriggered: root.begin() }
  Timer { interval: 20000; running: true; onTriggered: { console.error("I5_MAP_COPY_ASSERT: timeout"); Qt.exit(2); } }
}
