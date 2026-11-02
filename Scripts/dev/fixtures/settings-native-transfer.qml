// Installed configqml 0.3.0 witness, inert until invoked by the VM-only driver.
import QtQuick
import Quickshell
import ConfigQml 1.0

Item {
  id: root
  function config(): var { return store.values; }
  function rowIdentity(row: var): string { return row.rowId; }
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  function check(ok, name) {
    if (!ok)
      throw new Error("I4_NATIVE_TRANSFER_ASSERT: " + name);
  }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  component Row: Item { required property string rowId }
  Repeater {
    id: leftRows
    model: store.ready ? store.listModel(["left"]) : null
    delegate: Row {}
  }
  Repeater {
    id: rightRows
    model: store.ready ? store.listModel(["right"]) : null
    delegate: Row {}
  }
  ConfigStore {
    id: store
    autoSave: false
    schema: ConfigSchema {
      ConfigValue {
        key: "left"; valueType: ConfigValue.List; defaultValue: []; idField: "id"
        ConfigValue {
          valueType: ConfigValue.Record
          ConfigValue { key: "id"; valueType: ConfigValue.String }
          ConfigValue { key: "injectedDefault"; valueType: ConfigValue.Boolean; optional: true }
        }
      }
      ConfigValue {
        key: "right"; valueType: ConfigValue.List; defaultValue: []; idField: "id"
        ConfigValue {
          valueType: ConfigValue.Record
          ConfigValue { key: "id"; valueType: ConfigValue.String }
          ConfigValue { key: "injectedDefault"; valueType: ConfigValue.Boolean; optional: true }
        }
      }
    }
    sources: [JsonFileSource { sourceId: "user"; path: Quickshell.env("I4_NATIVE_FILE") }]
    recordListPolicies: [ConfigRecordListPolicy {
        policyId: "left"; path: ["left"]; keyField: "id"; pruneUnknown: true; normalizeFields: true
      }, ConfigRecordListPolicy { policyId: "right"; path: ["right"]; keyField: "id" }]
    onReadyChanged: {
      if (!ready)
        return;
      store.updateRecordListPolicy("left", {ready: true, entries: [
        {key: "visible", available: true, retain: false, normalize: true, defaults: {injectedDefault: false}}
      ]}, function (projected) {
        try {
          root.check(projected.status === "projected", "metadata admission");
          if (root.verifyOnly) {
            root.check(leftRows.count === 0 && rightRows.count === 1 && root.rowIdentity(rightRows.itemAt(0)) === "visible", "cold model consumers");
            root.check(root.config().right[0].deprecatedData.token === "retain" && root.config().right[0].injectedDefault === undefined, "cold raw preservation");
            console.log("I4_NATIVE_TRANSFER: RESTART_PASS");
            Qt.exit(0);
            return;
          }
          root.check(leftRows.count === 1 && root.config().left[0].injectedDefault === false, "normalized source consumer");
          store.editRecordList("left", {generation: store.info(["left"]).publicationGeneration, listAddress: [], edits: [
            {op: "transfer", from: {policyId: "left", listAddress: [], generation: store.info(["left"]).publicationGeneration, index: 0},
             to: {policyId: "right", listAddress: [], generation: store.info(["right"]).publicationGeneration, index: 0}}
          ]}, function (admitted) {
            try {
              root.check(admitted.status === "admitted" && leftRows.count === 0 && rightRows.count === 1 && root.rowIdentity(rightRows.itemAt(0)) === "visible", "transfer model consumers");
              root.check(store.info(["left"]).publicationGeneration === store.info(["right"]).publicationGeneration, "coherent worker generations");
              root.check(root.config().right[0].deprecatedData.token === "retain" && root.config().right[0].injectedDefault === undefined, "unnormalized row moved");
              store.save(function (saved) {
                try {
                  root.check(saved.status === "saved", "actual native save");
                  console.log("I4_NATIVE_TRANSFER: SAVED_PASS");
                  Qt.exit(0);
                } catch (error) { root.fail(error); }
              });
            } catch (error) { root.fail(error); }
          });
        } catch (error) { root.fail(error); }
      });
    }
  }
  Timer { interval: 20000; running: true; onTriggered: root.fail("native transfer watchdog") }
}
