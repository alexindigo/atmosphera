// Inert native owner/metadata preparation; never constructs plugin Main/actions.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  property var expected: []
  property int selected: -1
  property var api: null
  property bool started: false
  FileView {
    id: expectedFile
    path: Quickshell.env("PHA_CATALOG_EXPECTED")
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: manifestFile
    blockLoading: true
    printErrors: false
  }
  Text {
    id: consumer
    text: root.api && root.selected >= 0 && root.selected < root.expected.length ? String(root.api.pluginSettings[root.expected[root.selected].consumer]) : ""
  }
  function check(condition, message) {
    if (!condition)
      throw new Error("CATALOG_METADATA_ASSERT: " + message);
  }
  function equal(left, right) {
    if (left === right)
      return true;
    if (!left || !right || typeof left !== "object" || typeof right !== "object")
      return false;
    var a = Object.keys(left).sort();
    var b = Object.keys(right).sort();
    return JSON.stringify(a) === JSON.stringify(b) && a.every(function (key) {
      return equal(left[key], right[key]);
    });
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function next() {
    selected++;
    if (selected === expected.length) {
      Qt.exit(0);
      return;
    }
    var row = expected[selected];
    manifestFile.path = Settings.configDir + "plugins/" + row.id + "/manifest.json";
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    var installed = Object.assign({}, Registry.installedPlugins);
    installed[row.id] = manifest;
    Registry.installedPlugins = installed;
    Service._openSettingsOwner(row.id, function (owner) {
      try {
        check(owner !== null, row.id + " native owner");
        var metadata = owner.store.settingsEditorMetadata;
        check(metadata.ready && metadata.error === "", row.id + " metadata ready");
        check(Object.keys(metadata.fields).length === Object.keys(row.usage).length, row.id + " field coverage");
        for (var key in row.usage)
          check(metadata.fields[key].usage === row.usage[key], row.id + " explicit role");
        root.api = Service.createPluginAPI(row.id, manifest, owner, {}, {}, {});
        var loaded = Object.assign({}, Service.loadedPlugins);
        loaded[row.id] = {
          api: root.api
        };
        Service.loadedPlugins = loaded;
        var editor = root.api.createSettingsEditor();
        check(editor !== null, row.id + " native editor");
        editor.whenReady(function (opened) {
          try {
            check(opened.status === "opened", row.id + " draft ready");
            for (var name in row.values)
              check(equal(editor.copyValue(editor.values[name]), row.values[name]), row.id + " effective value " + name);
            check(consumer.text === row.consumerText, row.id + " bound consumer");
            editor.apply(editor.values, function (result) {
              try {
                check(result.status === "nothing_to_save" && result.refreshState === "current", row.id + " untouched receipt");
                check(consumer.text === row.consumerText, row.id + " consumer after receipt");
                editor.discard();
                console.log("CATALOG_METADATA_NATIVE: PASS " + row.id);
                Qt.callLater(root.next);
              } catch (error) {
                fail(error);
              }
            });
          } catch (error) {
            fail(error);
          }
        });
      } catch (error) {
        fail(error);
      }
    });
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    try {
      expectedFile.waitForJob();
      expected = JSON.parse(expectedFile.text());
      next();
    } catch (error) {
      fail(error);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 45000
    running: true
    onTriggered: root.fail("catalog metadata watchdog")
  }
  Component.onCompleted: begin()
}
