import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  property bool started: false
  property var api
  property var selected
  property var sibling
  property var main
  property var sharedClient
  property var client
  property var second
  property var inputData
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property string afterDisk
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/mawaqit/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/mawaqit/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: effects
    path: Quickshell.env("PHA_PRAYER_EFFECTS")
    blockLoading: true
  }
  FileView {
    id: input
    path: Quickshell.env("PHA_PRAYER_CASE") + "/input.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete prayer native readback");
      else
        root.phase = root.afterDisk;
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("PRAYER_ASSERT: " + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function probe(boundary, next) {
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_PRAYER_DISK"), Quickshell.env("PHA_PRAYER_CASE"), Quickshell.env("PHA_PRAYER_OUTPUT") + "/persisted", boundary];
    disk.running = true;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    input.waitForJob();
    inputData = JSON.parse(input.text());
    var meta = JSON.parse(manifest.text()), translations = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      mawaqit: meta
    };
    Service._openSettingsOwner("mawaqit", function (owner) {
      try {
        check(owner, "actual native plugin owner");
        api = Service.createPluginAPI("mawaqit", meta, owner, translations, translations, {});
        Service.loadedPlugins = {
          mawaqit: {
            api: api
          }
        };
        var component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        check(component.status === Component.Ready, component.errorString());
        main = component.createObject(root, {
                                        pluginApi: api
                                      });
        check(main, "actual Main constructs");
        api.mainInstance = main;
        selected = PluginInstances.apiFor("mawaqit", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        sibling = PluginInstances.apiFor("mawaqit", {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        phase = "contexts";
      } catch (error) {
        fail(error);
      }
    });
  }
  function save(next) {
    phase = "saving";
    selected.saveSettings(function (result) {
      try {
        check(result.status === "saved" || result.status === "nothing_to_save", "originating runtime native save");
        phase = next;
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    check(Date.now() - since < 16000, "finite prayer lifetime deadline");
    if (phase === "contexts" && selected.settingsReady && sibling.settingsReady) {
      sharedClient = main.settingsConsumerFor(api.settingsContext);
      client = main.settingsConsumerFor(selected.settingsContext);
      second = main.settingsConsumerFor(sibling.settingsContext);
      phase = "selected";
    } else if (phase === "selected" && client.prayerTimings && second.prayerTimings && sharedClient.isLoading && api._pendingSettingsSaves === 0) {
      check(client.hijriDay === 12 && second.hijriDay === 10 && client.secondsToNext >= 0, "selected Hijri offset and actual countdown projection");
      check(main.settingsConsumerFor(selected.settingsContext) === client && main._settingsConsumers.size === 3, "one prayer client per captured API");
      probe("initial", "release-shared");
    } else if (phase === "release-shared") {
      var release = new XMLHttpRequest();
      release.open("GET", inputData.base + "/release-shared");
      release.send();
      phase = "shared-result";
    } else if (phase === "shared-result" && sharedClient.prayerTimings && !sharedClient.isLoading) {
      check(sharedClient.gregorianDateStr === "controlled-shared" && client.gregorianDateStr === "controlled-selected", "separate sources reach final prayer result projection");
      main.onPrayerTime(sharedClient, "Fajr");
      probe("shared", "shared-effect");
    } else if (phase === "shared-effect" && !main.azanPlaying) {
      main.onPrayerTime(client, "Fajr");
      main.onPrayerTime(second, "Fajr");
      phase = "effects";
    } else if (phase === "effects") {
      effects.reload();
      effects.waitForJob();
      var rows = effects.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
      if (rows.filter(row => row.command === "notify-send").length < 2 || rows.filter(row => row.command === "paplay").length < 2)
        return;
      check(rows.filter(row => row.command === "notify-send").length === 2 && rows.filter(row => row.command === "paplay").length === 2, "identical scheduled event across contexts has one common notification/audio admission");
      selected.pluginSettings.city = "held";
      save("held");
    } else if (phase === "held" && client.isLoading && !client.prayerTimings) {
      selected.pluginSettings.city = "fallback";
      save("fallback");
    } else if (phase === "fallback" && !client.isLoading && client.gregorianDateStr === "controlled-fallback") {
      check(second.gregorianDateStr === "controlled-selected" && sharedClient.gregorianDateStr === "controlled-shared", "held replacement cannot retarget sibling/shared results");
      selected.pluginSettings.tune = true;
      selected.pluginSettings.tuneFajr = 9.9;
      save("tuned");
    } else if (phase === "tuned" && !client.isLoading && client.gregorianDateStr === "controlled-fallback" && client.tuneParam.split(",")[1] === "9") {
      selected.pluginSettings.city = "retry";
      save("retry-admit");
    } else if (phase === "retry-admit") {
      var control = new XMLHttpRequest();
      control.open("GET", inputData.base + "/release-retry");
      control.send();
      phase = "retry";
    } else if (phase === "retry" && client._retryCount > 0) {
      check(client._retryCount === 1, "one application-level retry scheduled before retirement");
      probe("selected", "retire");
    } else if (phase === "retire") {
      console.log("PRAYER_RETIRE " + Date.now());
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && Date.now() - since > 5600) {
      check(main._settingsConsumers.size === 0 && !selected.settingsContext.current(), "last-owner retirement releases retry/XHR/countdown clients");
      console.log("PRAYER_LIFECYCLE: PASS");
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
    interval: 60
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
