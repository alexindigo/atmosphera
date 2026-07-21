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

  // ——— IM metadata (reactive, refreshed on IM change) ———
  property var availableIMs: ([])
  property var groups: ([])
  property string currentIMLanguage: ""
  property string currentIMIcon: ""
  property string currentIMUniqueName: ""

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
        refreshTimer.start();
      } else if (status === 3) {                            // Error
        root.fcitx5Available = false;
        Logger.w("InputMethodService", "fcitx5 controller unreachable");
      }
    }

    onServiceAvailableChanged: {
      if (!serviceAvailable) {
        root.fcitx5Available = false;
        Logger.w("InputMethodService", "fcitx5 service disappeared");
      } else {
        root.fcitx5Available = true;
        Logger.i("InputMethodService", "fcitx5 service appeared, refreshing metadata");
        refreshTimer.start();
      }
    }

    onSignalReceived: function (name, args) {
      if (name === "CurrentInputMethodChanged") {
        root.currentIM = args && args.length > 0 ? String(args[0]) : "";
        root.refreshCurrentIMInfo();
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
    root.active = !root.active;
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

  // ——— Metadata refresh ———

  Timer {
    id: refreshTimer
    interval: 500
    onTriggered: root.refresh()
  }

  function refresh() {
    if (!root.fcitx5Available)
      return;
    _fetchAvailableIMs();
    _fetchGroups();
    refreshCurrentIMInfo();
    Logger.d("InputMethodService", "Metadata refreshed");
  }

  function refreshCurrentIMInfo() {
    if (!root.fcitx5Available)
      return;
    fcitx5.call("CurrentInputMethodInfo", [], function (result) {
      if (result && result.length >= 9) {
        root.currentIMUniqueName = String(result[0] || "");
        root.currentIMLanguage = String(result[3] || "");
        root.currentIMIcon = String(result[5] || "");
      }
    });
  }

  function _fetchAvailableIMs() {
    if (!root.fcitx5Available)
      return;
    fcitx5.call("AvailableInputMethods", [], function (result) {
      if (!result || result.length === 0)
        return;
      var ims = [];
      var arr = result[0];
      if (Array.isArray(arr)) {
        for (var i = 0; i < arr.length; i++) {
          var im = arr[i];
          if (Array.isArray(im) && im.length >= 6) {
            ims.push({
                       "uniqueName": String(im[0] || ""),
                       "name": String(im[1] || ""),
                       "addon": String(im[2] || ""),
                       "language": String(im[3] || ""),
                       "label": String(im[4] || ""),
                       "icon": String(im[5] || ""),
                       "configurable": im.length >= 7 ? Boolean(im[6]) : false
                     });
          }
        }
      }
      root.availableIMs = ims;
    });
  }

  function _fetchGroups() {
    if (!root.fcitx5Available)
      return;
    fcitx5.call("InputMethodGroups", [], function (result) {
      if (!result || result.length === 0)
        return;
      var groups = [];
      var arr = result[0];
      if (Array.isArray(arr)) {
        for (var i = 0; i < arr.length; i++) {
          groups.push(String(arr[i] || ""));
        }
      }
      root.groups = groups;
    });
  }

  // ——— Flag emoji lookup ———
  // Tier 1: exact uniqueName match (most precise, region-aware)
  // Tier 2: locale-suffix parsing from uniqueName or language field
  // Tier 3: bare language code fallback
  // Tier 4: none → returns "" (widget renders as text)
  function flagFor(uniqueName, languageCode) {
    var un = (uniqueName || "").toLowerCase();
    var lc = (languageCode || "").toLowerCase();

    if (exactFlagMap[un])
      return exactFlagMap[un];

    var candidate = lc || un;
    var suffixMatch = candidate.match(/[_-](tw|hk|cn|gb|us|ca|au|br|pt|mx|in|sg|my|id|jp|kr|ru|ua|de|at|ch|fr|be|lu|it|es|pl|cz|sk|hu|nl|se|no|dk|fi|is|il|ir|tr|gr|th|vn)\b/i);
    if (suffixMatch) {
      var region = suffixMatch[1].toLowerCase();
      if (regionFlagMap[region])
        return regionFlagMap[region];
    }

    var bare = lc.replace(/[_-].*$/, "");
    if (bare && languageFlagMap[bare])
      return languageFlagMap[bare];

    return "";
  }

  property var exactFlagMap: {
    "keyboard-us": "🇺🇸",
    "keyboard-gb": "🇬🇧",
    "keyboard-ca": "🇨🇦",
    "keyboard-au": "🇦🇺",
    "keyboard-nz": "🇳🇿",
    "keyboard-de": "🇩🇪",
    "keyboard-fr": "🇫🇷",
    "keyboard-es": "🇪🇸",
    "keyboard-it": "🇮🇹",
    "keyboard-pt": "🇵🇹",
    "keyboard-br": "🇧🇷",
    "keyboard-ru": "🇷🇺",
    "keyboard-ua": "🇺🇦",
    "keyboard-pl": "🇵🇱",
    "keyboard-cz": "🇨🇿",
    "keyboard-sk": "🇸🇰",
    "keyboard-hu": "🇭🇺",
    "keyboard-jp": "🇯🇵",
    "keyboard-kr": "🇰🇷",
    "keyboard-cn": "🇨🇳",
    "keyboard-tw": "🇹🇼",
    "keyboard-hk": "🇭🇰",
    "keyboard-tr": "🇹🇷",
    "keyboard-gr": "🇬🇷",
    "keyboard-il": "🇮🇱",
    "keyboard-ir": "🇮🇷",
    "keyboard-in": "🇮🇳",
    "keyboard-th": "🇹🇭",
    "keyboard-vn": "🇻🇳",
    "keyboard-se": "🇸🇪",
    "keyboard-no": "🇳🇴",
    "keyboard-dk": "🇩🇰",
    "keyboard-fi": "🇫🇮",
    "keyboard-is": "🇮🇸",
    "keyboard-nl": "🇳🇱",
    "keyboard-be": "🇧🇪",
    "keyboard-ch": "🇨🇭",
    "keyboard-at": "🇦🇹",
    "keyboard-ro": "🇷🇴",
    "keyboard-bg": "🇧🇬",
    "keyboard-rs": "🇷🇸",
    "keyboard-hr": "🇭🇷",
    "keyboard-si": "🇸🇮",
    "keyboard-ee": "🇪🇪",
    "keyboard-lv": "🇱🇻",
    "keyboard-lt": "🇱🇹",
    "mozc": "🇯🇵",
    "anthy": "🇯🇵",
    "skk": "🇯🇵",
    "hangul": "🇰🇷",
    "chewing": "🇹🇼",
    "libpinyin": "🇨🇳",
    "sunpinyin": "🇨🇳",
    "shuangpin": "🇨🇳",
    "wubi": "🇨🇳",
    "zhuyin": "🇹🇼",
    "cangjie5": "🇹🇼",
    "cangjie3": "🇹🇼",
    "rime": "🇨🇳",
    "unikey": "🇻🇳",
    "thai": "🇹🇭",
    "sayura": "🇱🇰",
    "m17n": "🌐"
  }

  property var regionFlagMap: {
    "tw": "🇹🇼",
    "hk": "🇭🇰",
    "cn": "🇨🇳",
    "gb": "🇬🇧",
    "us": "🇺🇸",
    "ca": "🇨🇦",
    "au": "🇦🇺",
    "br": "🇧🇷",
    "pt": "🇵🇹",
    "mx": "🇲🇽",
    "in": "🇮🇳",
    "sg": "🇸🇬",
    "my": "🇲🇾",
    "id": "🇮🇩",
    "jp": "🇯🇵",
    "kr": "🇰🇷",
    "ru": "🇷🇺",
    "ua": "🇺🇦",
    "de": "🇩🇪",
    "at": "🇦🇹",
    "ch": "🇨🇭",
    "fr": "🇫🇷",
    "be": "🇧🇪",
    "lu": "🇱🇺",
    "it": "🇮🇹",
    "es": "🇪🇸",
    "pl": "🇵🇱",
    "cz": "🇨🇿",
    "sk": "🇸🇰",
    "hu": "🇭🇺",
    "nl": "🇳🇱",
    "se": "🇸🇪",
    "no": "🇳🇴",
    "dk": "🇩🇰",
    "fi": "🇫🇮",
    "is": "🇮🇸",
    "il": "🇮🇱",
    "ir": "🇮🇷",
    "tr": "🇹🇷",
    "gr": "🇬🇷",
    "th": "🇹🇭",
    "vn": "🇻🇳"
  }

  property var languageFlagMap: {
    "en": "🇺🇸",
    "zh": "🇨🇳",
    "pt": "🇵🇹",
    "de": "🇩🇪",
    "fr": "🇫🇷",
    "es": "🇪🇸",
    "ja": "🇯🇵",
    "ko": "🇰🇷",
    "ru": "🇷🇺",
    "ar": "🇸🇦",
    "fa": "🇮🇷",
    "hi": "🇮🇳",
    "he": "🇮🇱",
    "tr": "🇹🇷",
    "gr": "🇬🇷",
    "th": "🇹🇭",
    "vi": "🇻🇳",
    "pl": "🇵🇱",
    "cs": "🇨🇿",
    "sk": "🇸🇰",
    "hu": "🇭🇺",
    "ro": "🇷🇴",
    "bg": "🇧🇬",
    "uk": "🇺🇦",
    "nl": "🇳🇱",
    "sv": "🇸🇪",
    "no": "🇳🇴",
    "da": "🇩🇰",
    "fi": "🇫🇮",
    "it": "🇮🇹"
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
