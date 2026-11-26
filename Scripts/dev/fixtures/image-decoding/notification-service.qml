import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Notification as Popups
import qs.Modules.Panels.NotificationHistory
import qs.Services.System
import qs.Services.UI

ShellRoot {
  id: root
  readonly property var modelData: Quickshell.screens[0]
  property int tick: 0
  property var step: null
  property int stepTick: 0
  property int pending: 0
  property bool started: false
  property int producerExit: -1
  property int interestsBeforeNotify: 0
  property string producerErrors: ""
  property var snapshots: []
  property var admissions: []
  property var changes: []
  property var widgets: []
  property bool done: false
  FileView {
    path: Quickshell.env("IMAGE_ICON_DIR") + "/icons.json"
    onLoaded: IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("IMAGE_ICON_DIR"))
  }
  Image {
    id: raw
    source: Quickshell.env("IMAGE_FIXTURES") + "/Still.webp"
  }
  Popups.Notification {
    id: popups
  }
  FloatingWindow {
    visible: true
    implicitWidth: 900
    implicitHeight: 1000
    NotificationHistoryPanel {
      id: history
      screen: root.modelData
    }
  }
  function rows(model) {
    var result = [];
    for (var i = 0; i < model.count; ++i)
      result.push(Object.assign({}, model.get(i)));
    return result;
  }
  function collect(item, result) {
    if ("notification" in item && "imagePath" in item) {
      result.push(item);
      return;
    }
    for (var i = 0; item.children && i < item.children.length; ++i)
      collect(item.children[i], result);
  }
  function widgetCohorts() {
    var items = [];
    if (popups.instances.length && popups.instances[0].item)
      collect(popups.instances[0].item.contentItem, items);
    var density = Settings.data.notifications.density;
    // Both popup densities exist in the actual card; select the visible layout.
    items = items.filter(item => Math.round(item.width) === Math.round((density === "compact" ? 24 : 40) * Style.uiScaleRatio));
    var historyItems = [];
    collect(history, historyItems);
    return {
      popup: items,
      history: historyItems
    };
  }
  function grab(item, name) {
    if (!item || !item.grabToImage(image => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: image.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/" + name)
                                                 }));
      --root.pending;
    })) {
      console.error("Notification fixture grab rejected: " + name);
      Qt.exit(3);
      return false;
    }
    ++root.pending;
    return true;
  }
  function recordWidgets(name, cohorts) {
    var items = cohorts.popup.concat(cohorts.history);
    for (var index = 0; index < items.length; ++index) {
      var item = items[index];
      var row = {
        stage: name,
        cohort: index < cohorts.popup.length ? "popup" : "history",
        summary: item.notification.summary,
        id: item.notification.id,
        path: item.imagePath,
        status: item.status,
        error: item.errorCode,
        reason: item.errorReason,
        revision: item.sourceRevision,
        width: item.width,
        height: item.height,
        file: name + "-" + index + ".png"
      };
      root.widgets.push(row);
      if (!root.grab(item, row.file))
        return false;
    }
    if (["file", "compact", "missing", "closed"].includes(name)) {
      var captures = [
            {
              item: history,
              name: name + "-history-panel"
            }
          ];
      if (name !== "closed" && popups.instances.length && popups.instances[0].item)
        captures.push({
                        item: popups.instances[0].item.contentItem.children.find(child => "spacing" in child),
                        name: name + "-popup-window"
                      });
      for (const capture of captures) {
        if (!root.grab(capture.item, capture.name + ".png"))
          return false;
      }
    }
    return true;
  }
  function presented(step, cohorts) {
    if (step.name === "file") {
      // The D-Bus producer sees Quickshell's numeric ID; widgets use the persisted ID.
      const id = NotificationService.quickshellIdToInternalId[step.id];
      if (!id || ![cohorts.popup, cohorts.history].every(items => items.some(item => item.visible && item.notification.id === id)))
        return false;
    }
    return cohorts.popup.concat(cohorts.history).every(item => item.notification.imageState === "ready" ? item.status === Image.Ready : item.notification.imageState === "unavailable" ? item.status === Image.Error : true);
  }
  // An admission is owned by a live popup/history target, not an image
  // renderer or an unrelated icon-set request.
  function admissionInterests() {
    return Object.values(NotificationService.popupState).reduce((total, entry) => total + entry.imageRequests.filter(request => request.pending).length, 0);
  }
  function observeAdmission(notification) {
    if (notification.summary === "slow-start") {
      const originalId = notification.id;
      for (const name of ["summaryChanged", "appIconChanged", "imageChanged"]) {
        notification[name].connect(function () {
          const id = NotificationService.quickshellIdToInternalId[originalId];
          const entry = NotificationService.popupState[id];
          root.changes.push({
                              signal: name,
                              image: notification.image,
                              appIcon: notification.appIcon,
                              entrySource: entry ? entry.data.originalImage : "",
                              revision: entry ? entry.data.imageRevision : ""
                            });
        });
      }
    }
    var id = NotificationService.quickshellIdToInternalId[notification.id];
    var entry = NotificationService.popupState[id];
    var before = {
      summary: notification.summary,
      id: id || "",
      count: NotificationService.popupModel.count,
      historyCount: NotificationService.historyModel.count,
      interests: root.admissionInterests(),
      interestDelta: root.admissionInterests() - root.interestsBeforeNotify,
      state: entry ? entry.data.imageState : "none",
      source: entry ? entry.data.originalImage : "",
      revision: entry ? entry.data.imageRevision : ""
    };
    if (notification.summary === "pending-clear") {
      NotificationService.clearHistory();
      NotificationService.dismissAllPopups();
    } else if (notification.summary === "pending-dismiss") {
      NotificationService.dismissPopup(id);
    } else if (notification.summary === "pending-remove") {
      NotificationService.removeFromHistory(id);
    }
    before.afterInterests = root.admissionInterests();
    before.afterEntry = !!NotificationService.popupState[id];
    root.admissions.push(before);
  }
  Process {
    id: producer
    stdinEnabled: true
    command: ["python3", Quickshell.env("IMAGE_PRODUCER"), Quickshell.env("IMAGE_FIXTURES"), "full"]
    stdout: SplitParser {
      onRead: data => {
        root.step = JSON.parse(data);
        root.stepTick = root.tick;
        if (root.step.kind === "prepare") {
          NotificationService.doNotDisturb = ["dnd", "no-owner", "pending-remove"].includes(root.step.name);
          Settings.data.notifications.density = root.step.name === "compact" ? "compact" : "default";
          NotificationService.maxHistory = root.step.name === "overflow-trigger" ? 1 : 30;
          root.interestsBeforeNotify = root.admissionInterests();
          root.step = null;
          producer.write("next\n");
        } else if (root.step.kind === "control") {
          if (root.step.name === "shared-remove") {
            const item = rows(NotificationService.historyModel).find(row => row.summary === "shared-one");
            NotificationService.removeFromHistory(item.id);
            NotificationService.dismissPopup(item.id);
          } else if (root.step.name === "clear-with-popup") {
            NotificationService.clearHistory();
            ImageCacheService.clearRepresentations();
          } else if (root.step.name === "closed") {
            NotificationService.dismissAllPopups();
          }
        }
      }
    }
    stderr: StdioCollector {}
    onExited: (code, status) => {
      root.producerExit = code;
      root.producerErrors = stderr.text;
      if (code !== 0 || status !== 0 || !root.done) {
        console.error("Notification producer exited before successful completion: code=" + code + " status=" + status + " stderr=" + root.producerErrors);
        Qt.exit(4);
      }
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (!root.started && NotificationService.notificationServerLoader && raw.status !== Image.Loading) {
        root.started = true;
        Settings.data.general.animationDisabled = true;
        Settings.data.notifications.respectExpireTimeout = true;
        Settings.data.notifications.saveToHistory.normal = true;
        NotificationService.maxPopups = 20;
        NotificationService.maxHistory = 30;
        NotificationRulesService.init();
        NotificationService.notificationServerLoader.notification.connect(root.observeAdmission);
        history.open();
        producer.running = true;
      }
      if (root.step && root.step.kind !== "ack" && root.tick > root.stepTick + 6 && !root.pending) {
        var unsettled = Object.values(NotificationService.popupState).some(entry => entry.imageRequests.some(request => request.pending));
        var cohorts = root.widgetCohorts();
        if (!unsettled && root.presented(root.step, cohorts)) {
          var current = root.step;
          root.step = null;
          root.snapshots.push({
                                stage: current.name,
                                originalId: current.id || 0,
                                popup: rows(NotificationService.popupModel),
                                history: rows(NotificationService.historyModel),
                                interests: root.admissionInterests(),
                                owners: Object.values(NotificationService.popupState).map(entry => ({
                                  id: entry.data.id,
                                  summary: entry.data.summary,
                                  popup: entry.popupWanted,
                                  history: entry.historyWanted,
                                  revision: entry.imageRevision,
                                  native: !!entry.notification
                                }))
        });
        if (!root.recordWidgets(current.name, cohorts))
          return;
        root.done = current.name === "closed";
        root.step = {
          kind: "ack",
          name: current.name
        };
        root.stepTick = root.tick;
      }
    }
    if (root.step && root.step.kind === "ack" && !root.pending) {
      root.step = null;
      producer.write("next\n");
    }
      if (root.done && root.producerExit >= 0 && !root.pending) {
        history.close();
        if (!root.admissionInterests()) {
          NotificationService.performSaveHistory();
          console.log("IMAGE_BASELINE|" + JSON.stringify({
            raw: raw.status,
            snapshots: root.snapshots,
            admissions: root.admissions,
            widgets: root.widgets,
            changes: root.changes,
            producerExit: root.producerExit,
            producerErrors: root.producerErrors,
            interests: root.admissionInterests(),
            historyFile: NotificationService.historyFile,
            warningColor: [Math.round(AtmoColor.mError.r * 255), Math.round(AtmoColor.mError.g * 255), Math.round(AtmoColor.mError.b * 255)]
          }));
          Qt.quit();
        }
        }
        }
        }
          Timer {
            interval: 85000
            running: true
            onTriggered: Qt.exit(2)
          }
        }
