import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets

ShellRoot {
  id: root
  FileView {
    id: input
    path: Quickshell.env("PHA_PROVIDER_CASE") + "/input.json"
    blockLoading: true
  }
  property var data
  property var main
  property var one
  property var two
  property var heldWorker
  property string publicAvatar
  NImageRounded {
    id: avatarImage
    width: 32
    height: 32
  }
  NImageRounded {
    id: cachedImage
    width: 32
    height: 32
  }
  FileView {
    id: avatarBarrier
    path: Quickshell.env("PHA_PROVIDER_CASE") + "/avatar-held"
    watchChanges: true
    onFileChanged: reload()
  }
  FileView {
    id: effects
    path: Quickshell.env("PHA_PRAYER_EFFECTS")
    blockLoading: true
  }
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  QtObject {
    id: shared
    property bool alive: true
    property var settingsView: ({
                                  username: "shared",
                                  token: "controlled-shared",
                                  githubUrl: "",
                                  refreshInterval: 1800,
                                  enableSystemNotifications: false
                                })
    function current() {
      return alive;
    }
  }
  QtObject {
    id: selected
    property bool alive: true
    property var settingsView: ({
                                  username: "chain",
                                  token: "controlled-chain",
                                  githubUrl: "",
                                  refreshInterval: 1800,
                                  maxEvents: 200,
                                  enableSystemNotifications: false
                                })
    function current() {
      return alive;
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("GITHUB_LIFECYCLE_ASSERT: " + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function configure(patch) {
    selected.settingsView = Object.assign({}, selected.settingsView, patch);
  }
  function begin() {
    input.waitForJob();
    data = JSON.parse(input.text());
    var component = Qt.createComponent("file://" + data.directory + "/Main.qml");
    check(component.status === Component.Ready, component.errorString());
    main = component.createObject(root, {
                                    pluginApi: {
                                      settingsContext: shared,
                                      pluginDir: data.directory
                                    }
                                  });
    check(main, "actual Main constructs");
    one = main.settingsConsumerFor(shared);
    two = main.settingsConsumerFor(selected);
    phase = "chain";
  }
  function drive() {
    check(Date.now() - since < 18000, "finite chain deadline");
    if (phase === "chain" && one.events.length === 1 && two.events.length === 102 && !two.isLoading) {
      check(main.settingsConsumerFor(selected) === two && main._settingsConsumers.size === 2, "one exact client per context across renderers");
      check(two.followingList.length === 101 && two._worker.completedBatches === 13 && two._worker.totalGraphQLCost === 14, "pagination, all batches, controlled retry and own-repo stage complete");
      check(!one.events.some(event => event.id === "legacy-foreign"), "unqualified event cache is not attributed to a new source");
      configure({
                  username: "held-following",
                  token: "controlled-old"
                });
      phase = "held-following";
    } else if (phase === "held-following" && two._worker?.isLoading) {
      heldWorker = two._worker;
      configure({
                  username: "selected",
                  token: "controlled-new"
                });
      phase = "replacement";
    } else if (phase === "replacement" && two.events.length === 2 && !two.isLoading) {
      check(two.events.every(event => event.repo.name === "selected/controlled"), "replacement source owns final events");
      heldWorker = two._worker;
      configure({
                  token: "controlled-token-only"
                });
      phase = "token-only";
    } else if (phase === "token-only" && two._worker !== heldWorker && two.events.length === 2 && two.notificationsList.length === 3) {
      two.markAllNotificationsAsRead();
      phase = "marking";
    } else if (phase === "marking" && two._worker.isMarkingRead) {
      configure({
                  username: "retired",
                  token: "controlled-retired"
                });
      phase = "retiring-queue";
    } else if (phase === "retiring-queue" && two.events.length === 1 && !two.isLoading) {
      configure({
                  username: "avatar",
                  token: "controlled-avatar"
                });
      phase = "avatar-source";
    } else if (phase === "avatar-source" && two.events.length === 1 && !two.isLoading) {
      main.downloadAvatars(two._worker, [
                             {
                               actor: {
                                 login: "cached",
                                 avatar_url: "https://avatars.controlled/cached?x=1"
                               }
                             },
                             {
                               actor: {
                                 login: "download",
                                 avatar_url: "https://avatars.controlled/download?x=1"
                               }
                             }
                           ]);
      phase = "avatar-public";
    } else if (phase === "avatar-public" && two.getAvatarPath("cached") && two.getAvatarPath("download")) {
      publicAvatar = two.getAvatarPath("download");
      check(publicAvatar.endsWith("__download.png"), "qualified public avatar path");
      avatarImage.imagePath = publicAvatar;
      cachedImage.imagePath = two.getAvatarPath("cached");
      phase = "avatar-image-public";
    } else if (phase === "avatar-image-public") {
      check(avatarImage.status !== Image.Error && cachedImage.status !== Image.Error, "actual rounded-image consumer accepts qualified avatar URLs");
      if (avatarImage.status !== Image.Ready || cachedImage.status !== Image.Ready)
        return;
      configure({
                  githubUrl: "enterprise.controlled"
                });
      phase = "avatar-enterprise-source";
    } else if (phase === "avatar-enterprise-source" && two.events.length === 1 && !two.isLoading) {
      check(two.getAvatarPath("download") === "", "another origin cannot borrow a public avatar");
      main.downloadAvatars(two._worker, [
                             {
                               actor: {
                                 login: "download",
                                 avatar_url: "https://avatars.controlled/enterprise?x=1"
                               }
                             }
                           ]);
      phase = "avatar-enterprise";
    } else if (phase === "avatar-enterprise" && two.getAvatarPath("download")) {
      check(two.getAvatarPath("download") !== publicAvatar, "same login has distinct origin paths");
      avatarImage.imagePath = two.getAvatarPath("download");
      phase = "avatar-image-enterprise";
    } else if (phase === "avatar-image-enterprise") {
      check(avatarImage.status !== Image.Error, "actual rounded-image consumer accepts enterprise avatar URL");
      if (avatarImage.status !== Image.Ready)
        return;
      main.downloadAvatars(two._worker, [
                             {
                               actor: {
                                 login: "held",
                                 avatar_url: "https://avatars.controlled/held?x=1"
                               }
                             },
                             {
                               actor: {
                                 login: "never",
                                 avatar_url: "https://avatars.controlled/never?x=1"
                               }
                             }
                           ]);
      phase = "avatar-held";
    } else if (phase === "avatar-held" && avatarBarrier.text().trim() === "admitted") {
      configure({
                  token: ""
                });
      phase = "empty-token";
    } else if (phase === "empty-token" && Date.now() - since > 1700) {
      check(!two._worker && two.events.length === 0 && two.notificationsList.length === 0, "empty token clears previous source");
      check(two.hasError && two.errorMessage === "Please add a GitHub Personal Access Token in settings", "empty token retains original error guidance");
      check(!two.getAvatarPath("held") && main._avatarQueue.length === 0 && !main._avatar, "retired admitted avatar cannot publish or continue its queue");
      two.fetchFromGitHub();
      configure({
                  username: "",
                  token: "controlled-empty-user"
                });
      phase = "empty-username";
    } else if (phase === "empty-username" && Date.now() - since > 200) {
      check(!two._worker && two.hasError && two.errorMessage === "Please configure your GitHub username in settings", "empty username has truthful unconfigured projection");
      two.fetchFromGitHub();
      shared.settingsView = Object.assign({}, shared.settingsView, {
                                            username: "same",
                                            token: "controlled-same",
                                            enableSystemNotifications: true
                                          });
      configure({
                  username: "same",
                  token: "controlled-same",
                  githubUrl: "",
                  enableSystemNotifications: true
                });
      phase = "common-notification";
    } else if (phase === "common-notification" && one.events.length === 1 && two.events.length === 1 && !one.isLoading && !two.isLoading) {
      main.sendSystemNotification(one._worker, "Controlled", "Controlled shared event", "https://github.com", "controlled-common-event");
      main.sendSystemNotification(two._worker, "Controlled", "Controlled shared event", "https://github.com", "controlled-common-event");
      phase = "notification-result";
    } else if (phase === "notification-result" && Date.now() - since > 250) {
      effects.reload();
      effects.waitForJob();
      var notifications = effects.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
      check(notifications.length === 1 && notifications[0].command === "notify-send", "one common notification across equal-source contexts");
      configure({
                  username: "held-last",
                  token: "controlled-last"
                });
      phase = "last-held";
    } else if (phase === "last-held" && two._worker?.isLoading) {
      selected.alive = false;
      shared.alive = false;
      phase = "retired";
    } else if (phase === "retired" && Date.now() - since > 2300) {
      check(main._settingsConsumers.size === 0, "retirement drops every request-chain client");
      console.log("GITHUB_LIFECYCLE: PASS");
      Qt.exit(0);
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
  Component.onCompleted: {
    try {
      begin();
    } catch (error) {
      fail(error);
    }
  }
}
