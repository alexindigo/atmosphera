pragma Singleton
import DBus 1.0

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor
import qs.Services.Locker
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

  // ——— Group membership (fcitx5 group name → unique IM names) ———
  property var groupMembers: ({})

  // ——— fcitx5 D-Bus proxy ———
  // Every call goes through _call(), which checks the reply.
  DBus {
    id: fcitx5
    service: "org.fcitx.Fcitx5"
    path: "/controller"
    iface: "org.fcitx.Fcitx.Controller1"
    connection: SessionBus
    watchServiceStatus: true

    onStatusChanged: {
      if (status === 2) {                                   // Ready
        Logger.i("InputMethodService", "fcitx5 controller ready");
        refreshTimer.start();
        root._reconcileSecure();
      } else if (status === 3) {                            // Error
        Logger.w("InputMethodService", "fcitx5 controller unreachable");
      }
    }

    onServiceAvailableChanged: {
      // Sole writer of fcitx5Available. A name-owned-but-broken fcitx5
      // degrades per call via reply.isError guards instead.
      if (!serviceAvailable) {
        root.fcitx5Available = false;
        root._resetState();
        Logger.w("InputMethodService", "fcitx5 service disappeared");
      } else {
        root.fcitx5Available = true;
        Logger.i("InputMethodService", "fcitx5 service appeared, refreshing metadata");
        refreshTimer.start();
        root._reconcileSecure();
      }
    }

    // Controller1 emits only InputMethodGroupsChanged. fcitx5 does not push the
    // current IM or group, so they are queried (queryState) instead.
    onSignalReceived: function (name, args) {
      if (name === "InputMethodGroupsChanged") {
        root._fetchGroups();
        root.queryState();
      }
    }
  }

  // ——— State publishing (fcitx-input-state.json) ———
  // Publishes the current IM state for non-shell consumers (e.g. a
  // screen-border glow when a composing IM is active). The file is written
  // once per applied state (_applyState / _resetCurrent), only when its
  // content differs from the last write, so no separate polling daemon is
  // needed. Atomic write (tmp + rename).
  readonly property string _stateFile: {
    var rd = Quickshell.env("XDG_RUNTIME_DIR");
    return (rd && rd.length > 0 ? rd : "/tmp") + "/fcitx-input-state.json";
  }
  property string _publishedKey: ""

  function _publishIfChanged() {
    var st = {
      "im": root.currentIMUniqueName || root.currentIM || "",
      "group": root.currentGroup || "",
      "lang": root.currentIMLanguage || ""
    };
    var key = JSON.stringify(st);
    if (key === root._publishedKey)
      return;
    root._publishedKey = key;
    var b64 = Qt.btoa(key);
    var proc = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "echo '${b64}' | base64 -d > '${root._stateFile}.tmp' && mv '${root._stateFile}.tmp' '${root._stateFile}'"]
      }
    `, root, "imStateWriter");
    proc.exited.connect(function () {
      proc.destroy();
    });
    proc.running = true;
  }

  // ——— Init ———
  function init() {
    Logger.i("InputMethodService", "Service started");
  }

  // ——— fcitx5 calls ———
  // done(error, values) runs exactly once: error is "" on success, otherwise the
  // reason, which is also logged here with the method and arguments.
  function _call(method, args, done) {
    if (!root.fcitx5Available) {
      if (done)
        done("unavailable", null);
      return;
    }
    var reply = fcitx5.call(method, args);
    if (!reply) {
      Logger.w("InputMethodService", method, JSON.stringify(args), "no reply");
      if (done)
        done("D-Bus: no reply", null);
      return;
    }
    var finish = function () {
      if (reply.isError) {
        var msg = "D-Bus: " + (reply.error && reply.error.message ? reply.error.message : "unknown error");
        Logger.w("InputMethodService", method, JSON.stringify(args), msg);
        if (done)
          done(msg, null);
      } else if (done) {
        done("", reply.values);
      }
    };
    if (reply.isFinished)
      finish();
    else
      reply.finished.connect(finish);
  }

  // Runs every [{method, args}] call; done(results) once all have finished,
  // with results[i] = {error, values} in the same order.
  function _callAll(calls, done) {
    var results = [];
    var remaining = calls.length;
    if (remaining === 0) {
      done(results);
      return;
    }
    calls.forEach(function (c, i) {
      root._call(c.method, c.args, function (error, values) {
        results[i] = {
                       "error": error,
                       "values": values
                     };
        remaining -= 1;
        if (remaining === 0)
          done(results);
      });
    });
  }

  function activate() {
    root._call("Activate", [], function () {
      root.queryState();
    });
  }

  function deactivate() {
    root._call("Deactivate", [], function () {
      root.queryState();
    });
  }

  function toggle() {
    root._call("Toggle", [], function () {
      root.queryState();
    });
  }

  // ——— Serial operations ———
  // Switches and toggles change fcitx5's state and then read it back. Each
  // runs to completion (its callback fires) before the next one starts, so a
  // second press always sees the result of the first. Reads (queryState) are
  // not queued.
  property var _opQueue: []
  property bool _opBusy: false

  function _serial(run) {
    root._opQueue.push(run);
    root._pumpOps();
  }

  function _pumpOps() {
    if (root._opBusy || root._opQueue.length === 0)
      return;
    root._opBusy = true;
    var run = root._opQueue.shift();
    run(function () {
      root._opBusy = false;
      root._pumpOps();
    });
  }

  // Switches to input method `target`: its group first when it is not the
  // current one, then the IM. Returns the reason when the request is refused
  // (unavailable, unknown, or in no group); "" when it was dispatched. callback
  // always runs once: at once with the refusal, or later with "" on success or
  // the error once the state has been re-read.
  function switchTo(target, callback) {
    var refused = root._switchRefusal(target);
    if (refused) {
      Logger.w("InputMethodService", "switchTo", target, refused);
      if (callback)
        callback(refused);
      return refused;
    }
    root._serial(function (done) {
      root._switchNow(target, "", function (error) {
        if (callback)
          callback(error);
        done();
      });
    });
    return "";
  }

  // Same contract as switchTo, for a group.
  function setGroup(name, callback) {
    var refused = "";
    if (!root.fcitx5Available)
      refused = "unavailable";
    else if (!name)
      refused = "missing group";
    else if (root.groups.indexOf(name) < 0)
      refused = "unknown group " + name;
    if (refused) {
      Logger.w("InputMethodService", "setGroup", name, refused);
      if (callback)
        callback(refused);
      return refused;
    }
    root._serial(function (done) {
      root._setGroupNow(name, function (error) {
        if (callback)
          callback(error);
        done();
      });
    });
    return "";
  }

  // Toggle: pressing `target` switches to it and remembers the group and IM
  // it left. Pressing it again while it is current returns to the remembered
  // pair; with nothing remembered, to the first other IM of the current group.
  // The refusal contract is switchTo's; a failure after the decision is
  // reported to callback and logged.
  property var _toggleReturn: null

  function toggleTo(target, callback) {
    var refused = root._switchRefusal(target);
    if (refused) {
      Logger.w("InputMethodService", "toggleTo", target, refused);
      if (callback)
        callback(refused);
      return refused;
    }
    root._serial(function (done) {
      root.queryState(function () {
        var finish = function (error) {
          if (error)
            Logger.w("InputMethodService", "toggleTo", target, error);
          if (callback)
            callback(error);
          done();
        };
        if (root.currentIM !== target) {
          root._toggleReturn = root.currentIM ? {
                                                  "group": root.currentGroup,
                                                  "im": root.currentIM
                                                } : null;
          root._switchNow(target, "", finish);
          return;
        }
        var back = root._toggleReturn;
        root._toggleReturn = null;
        if (back) {
          root._switchNow(back.im, back.group, finish);
          return;
        }
        var others = root._membersOf(root.currentGroup).filter(function (im) {
          return im !== target;
        });
        if (others.length === 0) {
          finish(target + " has no other input method to return to");
          return;
        }
        root._switchNow(others[0], root.currentGroup, finish);
      });
    });
    return "";
  }

  // Switches to the next input method of the current group, wrapping around.
  // Same contract as switchTo.
  function next(callback) {
    var refused = "";
    if (!root.fcitx5Available)
      refused = "unavailable";
    else if (root._membersOf(root.currentGroup).length === 0)
      refused = "no input method in the current group";
    if (refused) {
      Logger.w("InputMethodService", "next", refused);
      if (callback)
        callback(refused);
      return refused;
    }
    root._serial(function (done) {
      root.queryState(function () {
        var finish = function (error) {
          if (error)
            Logger.w("InputMethodService", "next", error);
          if (callback)
            callback(error);
          done();
        };
        var members = root._membersOf(root.currentGroup);
        if (members.length === 0) {
          finish("no input method in the current group");
          return;
        }
        var target = members[(members.indexOf(root.currentIM) + 1) % members.length];
        root._switchNow(target, root.currentGroup, finish);
      });
    });
    return "";
  }

  // Logs once when the group a caller names for an IM does not contain it.
  // The group is only a hint: fcitx5 decides which group an IM belongs to.
  property bool _groupHintLogged: false

  function noteGroupHint(name, group) {
    if (root._groupHintLogged || !group || root.groups.length === 0)
      return;
    if (root._groupsContaining(name).indexOf(group) >= 0)
      return;
    root._groupHintLogged = true;
    Logger.w("InputMethodService", "group hint", group, "does not contain", name, "- ignored");
  }

  // Runs after the state has been re-read: switch the group if needed, then the IM.
  // group: a preferred group (may be ""); cb(error) once done.
  function _switchNow(target, group, cb) {
    root.queryState(function () {
      var resolved = root._groupFor(target, group);
      if (!resolved) {
        cb(target + " is in no group");
        return;
      }
      var setIM = function () {
        root._call("SetCurrentIM", [target], function (error) {
          root.queryState(function () {
            cb(error);
          });
        });
      };
      if (resolved === root.currentGroup)
        setIM();
      else
        root._setGroupNow(resolved, function (error) {
          if (error)
            cb(error);
          else
            setIM();
        });
    });
  }

  // Switches to group `name` and re-reads the state; cb(error) once done.
  function _setGroupNow(name, cb) {
    root._call("SwitchInputMethodGroup", [name], function (error) {
      root.queryState(function () {
        cb(error);
      });
    });
  }

  function reload() {
    root._call("ReloadConfig", [], function (error) {
      if (!error)
        root.refresh();
    });
  }

  // ——— State query ———
  // Reads group, IM, IM info and state from fcitx5 and applies them together.
  // Snapshots are applied in issue order only: a reply older than the applied
  // one is dropped. callback(ok) runs after the apply or the drop.
  property int _querySeq: 0
  property int _appliedSeq: 0

  function queryState(callback) {
    if (!root.fcitx5Available) {
      if (callback)
        callback(false);
      return;
    }
    var seq = ++root._querySeq;
    root._callAll([{ "method": "CurrentInputMethodGroup", "args": [] },
                   { "method": "CurrentInputMethod", "args": [] },
                   { "method": "CurrentInputMethodInfo", "args": [] },
                   { "method": "State", "args": [] }], function (results) {
      var ok = results.every(function (r) {
        return r.error === "";
      });
      if (seq > root._appliedSeq) {
        root._appliedSeq = seq;
        if (ok)
          root._applyState(results);
        else
          root._resetCurrent();
      }
      if (callback)
        callback(ok);
    });
  }

  // Results of queryState's calls, in order: group, IM, IM info, State.
  // CurrentInputMethodInfo: (uniqueName, name, nativeName, icon, label,
  // languageCode, addon, configurable, ...) as observed on fcitx5 5.1.23.
  function _applyState(results) {
    var info = results[2].values || [];
    root.currentGroup = String(results[0].values[0] || "");
    root.currentIM = String(results[1].values[0] || "");
    root.currentIMUniqueName = String(info[0] || "");
    root.currentIMIcon = String(info[3] || "");
    root.currentIMLanguage = String(info[5] || "");
    root.active = Number(results[3].values[0]) === 2;   // State 2: an IM is active
    root._publishIfChanged();
  }

  function _resetCurrent() {
    root.currentGroup = "";
    root.currentIM = "";
    root.currentIMUniqueName = "";
    root.currentIMIcon = "";
    root.currentIMLanguage = "";
    root.active = false;
    root._publishIfChanged();
  }

  // The layout toast follows the IM: announce each change of the current IM
  // (not the start from none, and not a reset to none).
  property string _announcedIM: ""

  onCurrentIMChanged: {
    var previous = root._announcedIM;
    root._announcedIM = root.currentIM;
    if (previous === "" || root.currentIM === "")
      return;
    var found = root.availableIMs.find(function (im) {
      return im.uniqueName === root.currentIM;
    });
    KeyboardLayoutService.inputMethodChanged(found && found.name ? found.name : root.currentIM);
  }

  // fcitx5 went away: forget everything it reported. A lock snapshot taken from
  // that process is dropped too; the next fcitx5 is held afresh while locked.
  function _resetState() {
    root._resetCurrent();
    root.groups = [];
    root.groupMembers = ({});
    root.availableIMs = [];
    root._secureSnapshot = null;
    root._appliedSeq = root._querySeq;
  }

  // Why a switch to `target` is refused, or "" when it can be dispatched.
  // Uses the cached lists, which refresh() and InputMethodGroupsChanged keep current.
  function _switchRefusal(target) {
    if (!root.fcitx5Available)
      return "unavailable";
    if (!target)
      return "missing input method";
    var known = root.availableIMs.some(function (im) {
      return im.uniqueName === target;
    });
    if (!known)
      return "unknown input method " + target;
    if (!root._groupFor(target))
      return target + " is in no group";
    return "";
  }

  // The preferred group if it contains `im`, else the current group if it
  // does, else the first group that does, else "".
  function _groupFor(im, preferred) {
    if (preferred && root._membersOf(preferred).indexOf(im) >= 0)
      return preferred;
    var current = root.currentGroup;
    if (current && root._membersOf(current).indexOf(im) >= 0)
      return current;
    return root._groupsContaining(im)[0] || "";
  }

  function _membersOf(group) {
    return (group && root.groupMembers[group]) || [];
  }

  function _groupsContaining(im) {
    return Object.keys(root.groupMembers).filter(function (name) {
      return root.groupMembers[name].indexOf(im) >= 0;
    });
  }

  // ——— Metadata refresh ———

  Timer {
    id: refreshTimer
    interval: 500
    onTriggered: root.refresh()
  }

  // fcitx5 does not push the current IM or group: poll them while it is up.
  Timer {
    id: stateTimer
    interval: 400
    repeat: true
    running: root.fcitx5Available
    onTriggered: root.queryState()
  }

  function refresh() {
    if (!root.fcitx5Available)
      return;
    _fetchAvailableIMs();
    _fetchGroups();
    root.queryState();
    Logger.d("InputMethodService", "Metadata refreshed");
  }

  function _fetchAvailableIMs() {
    root._call("AvailableInputMethods", [], function (error, result) {
      if (error || !result || result.length === 0)
        return;
      var ims = [];
      var arr = result[0];
      if (arr && typeof arr.length === "number") {
        for (var i = 0; i < arr.length; i++) {
          var im = arr[i];
          // length-based check: dbusqml's nested struct lists are
          // array-like (indexable, .length) but fail Array.isArray()
          // Entry layout (fcitx5 5.1.23): (uniqueName, name, nativeName,
          // icon, label, languageCode, configurable).
          if (im && typeof im.length === "number" && im.length >= 6) {
            ims.push({
                       "uniqueName": String(im[0] || ""),
                       "name": String(im[1] || ""),
                       "label": String(im[4] || ""),
                       "icon": String(im[3] || ""),
                       "language": String(im[5] || ""),
                       "configurable": im.length >= 7 ? Boolean(im[6]) : false
                     });
          }
        }
      }
      root.availableIMs = ims;
    });
  }

  // Group names, then each group's members, applied together.
  function _fetchGroups() {
    root._call("InputMethodGroups", [], function (error, result) {
      if (error || !result || result.length === 0)
        return;
      var names = [];
      var arr = result[0];
      if (arr && typeof arr.length === "number") {
        for (var i = 0; i < arr.length; i++)
          names.push(String(arr[i] || ""));
      }
      var calls = names.map(function (name) {
        return { "method": "InputMethodGroupInfo", "args": [name] };
      });
      root._callAll(calls, function (infos) {
        var members = {};
        names.forEach(function (name, i) {
          var list = [];
          var items = infos[i].values && infos[i].values[1];
          if (!infos[i].error && items && typeof items.length === "number") {
            for (var j = 0; j < items.length; j++)
              list.push(String(items[j][0] || ""));
          }
          members[name] = list;
        });
        root.groups = names;
        root.groupMembers = members;
      });
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

  // ——— Out-of-process lock trigger ———
  // Secure mode follows the compositor-side LockedHint, which covers
  // every locker class (bundled config, swaylock, contract service,
  // in-process fallback alike). The in-process LockScreen.active path
  // in Modules/LockScreen stays as a redundant trigger (idempotent).
  Connections {
    target: LockerService
    function onLockedChanged() {
      if (LockerService.locked)
        root.enterSecureMode();
      else
        root.exitSecureMode();
    }
  }

  // ——— Lock screen (secure mode) ———
  // Secure mode is a desired state, secureModeActive, which the shell sets from
  // its lock state (LockerService.locked, covering every locker class) and
  // LockScreen.active (redundant, idempotent). The bundled locker process never
  // references this service, so the shell is the only instance that holds and
  // releases fcitx5 for the lock.
  //
  // _reconcileSecure() converges fcitx5 to the desired state. It runs on each
  // request and whenever fcitx5 appears, so a lock that arrives before fcitx5 is
  // attached (or a shell started while locked) is still applied on attach.
  // Each run reads the desired state when it runs, so queued runs are idempotent.
  //
  // hold: snapshot {group, im, active}, then Deactivate. release: restore the
  // snapshot (group, IM, then Activate or Deactivate to match `active`). The
  // snapshot is kept only once the Deactivate succeeded, so a failed hold is
  // retried by the next reconcile.
  property var _secureSnapshot: null

  function enterSecureMode() {
    if (root.secureModeActive)
      return;  // idempotent
    root.secureModeActive = true;
    Logger.i("InputMethodService", "enterSecureMode — IME suppressed");
    root._reconcileSecure();

    // TODO: xkb layout → force "us" when xkbAvailable is implemented
  }

  function exitSecureMode() {
    if (!root.secureModeActive)
      return;  // idempotent
    root.secureModeActive = false;
    Logger.i("InputMethodService", "exitSecureMode — IME restored");
    root._reconcileSecure();

    // TODO: restore xkb layout when xkbAvailable is implemented
  }

  function _reconcileSecure() {
    root._serial(function (done) {
      if (root.secureModeActive)
        root._holdNow(done);
      else
        root._releaseNow(done);
    });
  }

  function _holdNow(done) {
    if (!root.fcitx5Available || root._secureSnapshot !== null) {
      done();
      return;
    }
    root.queryState(function (ok) {
      if (!ok || !root.fcitx5Available || root._secureSnapshot !== null || !root.secureModeActive) {
        if (!ok)
          Logger.w("InputMethodService", "lock: fcitx5 state not read; will retry");
        done();
        return;
      }
      var snap = {
        "group": root.currentGroup,
        "im": root.currentIM,
        "active": root.active
      };
      // Disable fcitx5 composition while locked.
      // This prevents CJK IME leaks (JP mozc unmasked) and lock-client
      // crashes (noctalia#2212 Rime/Shuangpin focus-handoff).
      // qtwayland 6.11.1 text-input-v3 ordering bug means password
      // content_type arrives too late — deactivating the IME entirely
      // is the only reliable mitigation from QML today.
      root._call("Deactivate", [], function (error) {
        if (!error)
          root._secureSnapshot = snap;
        root.queryState(function () {
          done();
        });
      });
    });
  }

  function _releaseNow(done) {
    var snap = root._secureSnapshot;
    root._secureSnapshot = null;
    if (!snap) {
      done();
      return;
    }
    if (!root.fcitx5Available) {
      Logger.w("InputMethodService", "unlock: fcitx5 is gone; the IME state is not restored");
      done();
      return;
    }
    var reactivate = function (error) {
      if (error)
        Logger.w("InputMethodService", "unlock: restore", error);
      root._call(snap.active ? "Activate" : "Deactivate", [], function () {
        root.queryState(function () {
          done();
        });
      });
    };
    if (snap.im)
      root._switchNow(snap.im, snap.group, reactivate);
    else if (snap.group)
      root._setGroupNow(snap.group, reactivate);
    else
      reactivate("");
  }
}
