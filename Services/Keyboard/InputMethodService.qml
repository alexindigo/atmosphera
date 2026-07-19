pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import DBus 1.0
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI

Singleton {
  id: root

  // ——— State ———
  property bool fcitx5Available: false
  property bool xkbAvailable: false
  property bool active: false
  property string currentIM: ""
  property string currentGroup: ""
  property string currentLayout: ""
  property bool secureModeActive: false

  // ——— Snapshots for enterSecureMode/exitSecureMode ———
  property string _savedIM: ""
  property bool _savedActive: false
  property string _savedLayout: ""

  // ——— fcitx5 D-Bus proxy ———
  DBus {
    id: fcitx5
    service: "org.fcitx.Fcitx5"
    path: "/controller"
    iface: "org.fcitx.Fcitx.Controller1"
    connection: SessionBus
    watchServiceStatus: true

    onStatusChanged: {
      if (status === 2) {                                   // Ready
        root.fcitx5Available = true;
        Logger.i("InputMethodService", "fcitx5 controller ready");
      } else if (status === 3) {                            // Error
        root.fcitx5Available = false;
        Logger.w("InputMethodService", "fcitx5 controller unreachable");
      }
    }

    onServiceAvailableChanged: {
      if (!serviceAvailable) {
        root.fcitx5Available = false;
        Logger.w("InputMethodService", "fcitx5 service disappeared");
      }
    }

    onSignalReceived: function (name, args) {
      if (name === "CurrentInputMethodChanged") {
        root.currentIM = args && args.length > 0 ? String(args[0]) : "";
      } else if (name === "CurrentGroupChanged") {
        root.currentGroup = args && args.length > 0 ? String(args[0]) : "";
      }
    }
  }

  // ——— Init ———
  function init() {
    Logger.i("InputMethodService", "Service started");
  }

  // ——— fcitx5 control ———
  function activate() {
    if (!root.fcitx5Available)
      return;
    fcitx5.activate();
    root.active = true;
  }

  function deactivate() {
    if (!root.fcitx5Available)
      return;
    fcitx5.deactivate();
    root.active = false;
  }

  function toggle() {
    if (!root.fcitx5Available)
      return;
    fcitx5.toggle();
  }

  function setCurrentIM(name) {
    if (!root.fcitx5Available || !name)
      return;
    fcitx5.call("SetCurrentIM", [name]);
  }

  function setGroup(name) {
    if (!root.fcitx5Available || !name)
      return;
    fcitx5.call("SetCurrentGroup", [name]);
  }

  function reload() {
    if (!root.fcitx5Available)
      return;
    fcitx5.call("ReloadConfig");
  }

  // ——— Composite operations (lock screen) ———
  function enterSecureMode() {
    if (root.secureModeActive)
      return;  // idempotent

    // Snapshot current state before suppressing
    root._savedIM = root.currentIM;
    root._savedActive = root.active;
    root._savedLayout = root.currentLayout;

    // Disable fcitx5 composition while locked.
    // This prevents CJK IME leaks (JP mozc unmasked) and lock-client
    // crashes (noctalia#2212 Rime/Shuangpin focus-handoff).
    // qtwayland 6.11.1 text-input-v3 ordering bug means password
    // content_type arrives too late — deactivating the IME entirely
    // is the only reliable mitigation from QML today.
    if (root.fcitx5Available) {
      fcitx5.deactivate();
      root.active = false;
    }

    // TODO: xkb layout → force "us" when xkbAvailable is implemented

    root.secureModeActive = true;
    Logger.i("InputMethodService", "enterSecureMode — IME suppressed");
  }

  function exitSecureMode() {
    if (!root.secureModeActive)
      return;  // idempotent

    // Restore fcitx5 state
    if (root.fcitx5Available) {
      if (root._savedIM) {
        fcitx5.call("SetCurrentIM", [root._savedIM]);
      }
      if (root._savedActive) {
        fcitx5.activate();
        root.active = true;
      }
    }

    // TODO: restore xkb layout when xkbAvailable is implemented

    root.secureModeActive = false;
    Logger.i("InputMethodService", "exitSecureMode — IME restored");
  }
}
