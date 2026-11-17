pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Locker

Singleton {
  id: root
  property bool available: false
  property bool _initialized: false
  readonly property bool enabled: _initialized && Settings.data.general.lockOnSuspend && Settings.data.general.lockScreenEnabled
  onEnabledChanged: inhibitor.running = enabled

  function publishSecure() {
    if (inhibitor.running)
      inhibitor.write(JSON.stringify({secure: LockOwnerService.secure,
        opaque: LockOwnerService.status.descriptor?.snapshot.adapter !== "bundled"}) + "\n");
  }

  Process {
    id: inhibitor
    command: ["python3", "-B", Quickshell.shellDir + "/Scripts/python/locker-sleep-inhibitor.py"]
    running: root.enabled
    stdinEnabled: true
    onStarted: root.publishSecure()
    stdout: SplitParser {
      onRead: data => {
        var event;
        try { event = JSON.parse(data); }
        catch (error) { Logger.e("LogindService", "Invalid inhibitor event"); return; }
        if (event.event === "acquired") {
          root.available = true;
          Logger.i("LogindService", "Delay inhibitor acquired");
        } else if (event.event === "prepare") {
          LockOwnerService.observeSleepWindow(event.sleeping);
          if (event.sleeping)
            LockOwnerService.requestLock("prepare-for-sleep", false);
          root.publishSecure();
        } else if (event.event === "unconfirmed") {
          Logger.e("LogindService", event.message);
        }
      }
    }
    stderr: SplitParser { onRead: data => Logger.e("LogindService", data) }
    onExited: code => {
      root.available = false;
      if (root.enabled) {
        Logger.e("LogindService", "Delay inhibitor exited: " + code);
        retry.restart();
      }
    }
  }

  Timer {
    id: retry
    interval: 1000
    onTriggered: if (root.enabled) inhibitor.running = true
  }

  Connections {
    target: LockOwnerService
    function onStatusChanged() { root.publishSecure(); }
  }

  function init() {
    LockOwnerService.init();
    _initialized = true;
  }
}
