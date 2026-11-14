import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Services.Files
import qs.Services.UI
import qs.Modules.FileChooser
import "../../../Helpers/PortalPaths.js" as Paths

// This dedicated guest-only probe intentionally talks to the real guest system
// bus; the normal UI/portal suites retain their blocked system-bus contract.
ShellRoot {
  id: root
  property string volumeId: Quickshell.env("FILECHOOSER_VOLUME_ID")
  property string path: ""
  property int phase: 0
  property int ticks: 0
  property var rows: []
  property var volumeRequest: null
  readonly property var chooser: windowLoader.item
  Component { id: requestFactory; FileRequest {} }
  Loader {
    id: windowLoader
    active: root.volumeRequest !== null
    sourceComponent: FileChooserWindow { request: root.volumeRequest }
  }
  Component.onCompleted: Qt.callLater(function() {
    volumeRequest = requestFactory.createObject(root, {options: {title: "Choose a file", current_folder: Paths.encodeBytePath(Quickshell.env("FILECHOOSER_VOLUME_FOLDER")).bytes}});
  })
  TestEvent { id: input }
  FileView {
    path: Quickshell.shellDir + "/builtin/plugins/atmosphera-icons/icons.json"
    onLoaded: IconRegistry.register("dev:atmosphera-icons", JSON.parse(text()), Quickshell.shellDir + "/builtin/plugins/atmosphera-icons")
  }
  Process { id: capture; command: ["grim", Quickshell.env("FILECHOOSER_VOLUME_CAPTURE")] }
  Process { id: externalMount; command: ["timeout", "5", "udisksctl", "mount", "--no-user-interaction", "-b", "/dev/loop0"] }
  Process { id: externalUnmount; command: ["timeout", "5", "udisksctl", "unmount", "--no-user-interaction", "-b", "/dev/loop0"] }
  function click(rect) {
    var layout = chooser.layoutGeometry();
    input.mouseClick(chooser.contentItem, (chooser.width-layout.width)/2 + rect.x + rect.width/2,
                     (chooser.height-layout.height)/2 + rect.y + rect.height/2, Qt.LeftButton, Qt.NoModifier, 0);
  }
  function check(name, value, detail) {
    rows.push({name: name, pass: !!value, detail: detail});
    console.log("FILECHOOSER_VOLUMES|" + JSON.stringify(rows[rows.length-1]));
    if (!value) Qt.quit();
  }
  FileView { id: content; path: root.path ? root.path + "/Volume.txt" : ""; printErrors: false }
  Connections {
    target: FileVolumes
    function onMounted(id, path) { if (id === root.volumeId) root.path = path; }
  }
  Timer {
    interval: 100; repeat: true; running: true
    onTriggered: {
      if (++root.ticks > 150 || FileVolumes.errorText) {
        root.check("volume-no-error", false, {error: FileVolumes.errorText, rows: FileVolumes.volumes, phase: root.phase});
        return;
      }
      var row = FileVolumes.volumes.find(v => v.id === root.volumeId);
      if (FileVolumes.busy) return;
      if (!root.chooser || !root.volumeRequest) return;
      var geometry = chooser.placesState().rows.find(v => v.id === root.volumeId);
      if (root.phase === 0 && row && geometry && volumeRequest.browser.status === "ready") {
        root.check("discovery-unmounted", !row.mounted && row.name === "ChooserVolume", row);
        externalMount.running = true; root.phase++;
      } else if (root.phase === 1 && row && row.mounted && !externalMount.running) {
        root.check("external-mount-projection", true, row);
        externalUnmount.running = true; root.phase++;
      } else if (root.phase === 2 && row && !row.mounted && !externalUnmount.running && geometry) {
        root.check("external-unmount-projection", true, row);
        click(geometry.mount); root.phase++;
      } else if (root.phase === 3 && row && row.mounted && root.path && content.loaded && volumeRequest.browser.currentPath === root.path && volumeRequest.browser.status === "ready") {
        root.check("mount-consumer-bytes", content.text() === "real UDisks mount bytes\n" && row.path === root.path && volumeRequest.browser.indexOfPath(root.path + "/Volume.txt") >= 0 && chooser.focusArea === "listing", {volume: row, focus: chooser.focusArea});
        capture.running = true; root.phase++;
      } else if (root.phase === 4 && !capture.running) {
        FileVolumes.unmount(root.volumeId); root.phase++;
      } else if (root.phase === 5 && row && !row.mounted && geometry) {
        root.check("unmount-consumer", true, row);
        click(geometry.mount); root.phase++;
      } else if (root.phase === 6 && row && row.mounted && geometry && geometry.action.visible) {
        root.check("remount-before-eject", row.ejectable, row);
        click(geometry.action); root.phase++;
      } else if (root.phase === 7 && !row) {
        root.check("eject-unmounts-and-detaches-loop", chooser.focusArea === "listing", {volumes: FileVolumes.volumes, focus: chooser.focusArea});
        Qt.quit();
      }
    }
  }
}
