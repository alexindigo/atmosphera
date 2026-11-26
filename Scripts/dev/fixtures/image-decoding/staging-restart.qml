import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  property string first: ""
  property int phase: 0

  ImageOriginalStore {
    id: store
  }

  // The fixture owns this store. Identify its one direct supervisor before
  // simulating unexpected exit; do not touch any other shell or worker.
  Process {
    id: stopWorker
    command: ["python3", "-c", "import os, pathlib, signal, sys\nids = pathlib.Path(f'/proc/{sys.argv[1]}/task/{sys.argv[1]}/children').read_text().split()\nworkers = [int(p) for p in ids if b'images.retention' in pathlib.Path(f'/proc/{p}/cmdline').read_bytes().split(bytes(1))]\nassert len(workers) == 1, workers\nos.kill(workers[0], signal.SIGTERM)", String(
        Quickshell.processId)]
    onExited: code => {
      if (code !== 0)
        Qt.exit(3);
    }
  }

  FloatingWindow {
    visible: true
    implicitWidth: 120
    implicitHeight: 90
    NImage {
      id: image
      anchors.fill: parent
      source: Quickshell.env("IMAGE_FIXTURES") + "/Still.webp"
    }
  }

  Component.onCompleted: store.ensureStage(ok => {
    if (!ok) {
      Qt.exit(3);
      return;
    }
    root.first = store.stageDirectory;
    root.phase = 1;
    stopWorker.running = true;
  })
  Connections {
    target: store
    function onStageDirectoryChanged() {
      if (root.phase === 1 && !store.stageDirectory)
        root.phase = 2;
      else if (root.phase === 2 && store.stageDirectory && store.stageDirectory !== root.first)
        root.phase = 3;
    }
  }
  Timer {
    interval: 50
    repeat: true
    running: root.phase === 3 && image.imageState === "ready"
    onTriggered: {
      root.phase = 4;
      if (!image.grabToImage(frame => {
        console.log("IMAGE_GRAB|" + JSON.stringify({
                                                     saved: frame.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/recovered.png")
                                                   }));
        console.log('IMAGE_BASELINE|{"recovered":true}');
        Qt.quit();
      }))
        Qt.exit(3);
    }
  }
  Timer {
    interval: 5500
    running: true
    onTriggered: {
      console.log("STAGING_RECOVERY_TIMEOUT|" + root.phase);
      Qt.exit(3);
    }
  }
}
