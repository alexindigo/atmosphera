import QtQuick
import Quickshell
import ConfigQml 1.0

// Independent library boundary witness for retained widget-array consumers.
ShellRoot {
  id: root
  property bool started: false
  ConfigStore {
    id: store
    autoSave: false
    schema: ConfigSchema {
      ConfigValue {
        key: "rows"
        valueType: ConfigValue.List
        defaultValue: []
        ConfigValue {
          valueType: ConfigValue.Record
          open: true
          ConfigValue { key: "id"; valueType: ConfigValue.String }
          ConfigValue { key: "knownNumber"; valueType: ConfigValue.Real; optional: true }
        }
      }
    }
    sources: [JsonFileSource {
      sourceId: "user"; layerId: "user"
      path: Quickshell.env("I5_NUMBER_FILE")
      optional: true; writable: true; unknownData: JsonFileSource.Preserve
    }]
  }
  function begin() {
    if (started || !store.ready) return;
    started = true;
    var rows = store.values.rows;
    var observed = rows[0].customField;
    if (rows[0].knownNumber !== 123) {
      console.error("I5_NUMBER_ASSERT: declared-number control");
      Qt.exit(2);
      return;
    }
    console.log("I5_NUMBER_PRESENTATION: " + JSON.stringify({type: typeof observed,
      declaredControl: rows[0].knownNumber,
      json: JSON.stringify(observed), text: String(observed), coerced: String(Number(observed)),
      keys: Object.keys(Object(observed)), rows: JSON.stringify(rows)}));
    if (typeof observed !== "number" || observed !== 123 || rows[0].fraction !== 1.25) {
      console.error("I5_NUMBER_ASSERT: unknown safe numeric fields are usable by QML consumers");
      Qt.exit(2);
      return;
    }
    store.close(function () { console.log("I5_NUMBER_PRESENTATION: PASS"); Qt.exit(0); });
  }
  Timer { interval: 10; repeat: true; running: true; onTriggered: root.begin() }
  Timer { interval: 15000; running: true; onTriggered: Qt.exit(2) }
}
