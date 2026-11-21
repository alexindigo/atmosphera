import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_CONTENT_CASE")
  readonly property string plugin: Quickshell.env("PHA_CONTENT_PLUGIN")
  property var main: null
  property var provider: null
  property var preview: null
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property bool started: false
  property int mark: 0
  property string afterGate: ""
  property var admittedEntry: ({
                                 id: "admitted",
                                 title: "Admitted",
                                 url: "https://inert.invalid/admitted",
                                 uploader: "Uploader",
                                 duration: 10
                               })
  QtObject {
    id: selected
    property bool alive: true
    property var settingsView: ({
                                  enableTodoIntegration: true,
                                  autoPasteDelay: 150,
                                  autoSaveMp3AfterPlayback: true,
                                  showUploaderMetadata: false,
                                  previewMetadataMode: "never",
                                  previewThumbnailSize: "small",
                                  showHomeRecent: false,
                                  showHomeTop: false,
                                  showHomeTags: false,
                                  showHomeArtists: false,
                                  showHomePlaylists: false
                                })
    function current() {
      return alive;
    }
  }
  QtObject {
    id: shared
    property var settingsView: ({
                                  enableTodoIntegration: false,
                                  autoPasteDelay: 900,
                                  autoSaveMp3AfterPlayback: false,
                                  showUploaderMetadata: true
                                })
    function current() {
      return true;
    }
  }
  QtObject {
    id: api
    property var settingsContext: shared
    property var settingsView: shared.settingsView
    property var pluginSettings: shared.settingsView
    property var mainInstance: root.main
    property var manifest: ({
                              metadata: {
                                defaultSettings: {}
                              }
                            })
    function tr(key, params) {
      return key;
    }
  }
  QtObject {
    id: selectedApi
    property var settingsContext: selected
    property var settingsView: selected.settingsView
    property var pluginSettings: selected.settingsView
    property var mainInstance: root.main
    property var manifest: api.manifest
    function tr(key, params) {
      return key;
    }
  }
  QtObject {
    id: todoApi
    property var pluginSettings: ({
                                    todos: [],
                                    count: 0,
                                    pages: [
                                      {
                                        id: 7,
                                        name: "Shared page"
                                      }
                                    ]
                                  })
    property var mainInstance: ({})
    property int saves: 0
    function saveSettings() {
      saves++;
    }
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: gate
    onExited: code => {
      if (code !== 0)
        root.fail("gate failed");
      else
        root.phase = root.afterGate;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 900
    implicitHeight: 700
    Item {
      id: content
      width: 900
      height: 700
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("CONTENT_LIFETIME_ASSERT: " + plugin + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function actions(name) {
    return rows().slice(mark).filter(row => row.endpoint === "music-helper" && row.argv[0] === name);
  }
  function record(name) {
    console.log("CONTENT_LIFETIME " + JSON.stringify({
                                                       case: name,
                                                       status: "PASS"
                                                     }));
  }
  function file(action, name, next) {
    afterGate = next;
    phase = "gate";
    gate.command = [action === "hold" ? "touch" : "rm", base + "/hold-" + name];
    gate.running = true;
  }
  function create(name, properties) {
    const component = Qt.createComponent("file://" + base + "/plugin/" + name + ".qml");
    check(component.status === Component.Ready, component.errorString());
    const object = component.createObject(content, properties);
    check(object, "actual " + name);
    return object;
  }
  function updatePolicy(patch) {
    selected.settingsView = Object.assign({}, selected.settingsView, patch);
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    Service.loadedPlugins = {
      todo: {
        api: todoApi
      }
    };
    main = create("Main", {
                    pluginApi: api
                  });
    if (plugin === "music-search") {
      provider = create("LauncherProvider", {
                          pluginApi: selectedApi
                        });
      preview = create("MusicPreview", {
                         currentItem: {
                           id: "preview",
                           title: "Selected",
                           uploader: "Hidden uploader",
                           provider: provider
                         }
                       });
      phase = "presentation";
    } else
      phase = "clip-start";
  }
  function music() {
    if (phase === "presentation") {
      check(provider.buildDescription({
                                        uploader: "Hidden uploader"
                                      }, "").indexOf("Hidden uploader") === -1, "selected launcher description");
      check(preview.previewMetadataMode === "never" && preview.previewThumbnailSize === "small" && !preview.showUploaderMetadata, "selected actual preview policy");
      main.applyLibrary(JSON.stringify([
                                         {
                                           id: "song",
                                           title: "Song",
                                           url: "https://inert.invalid/song",
                                           uploader: "Artist",
                                           playCount: 4,
                                           lastPlayedAt: "2026-11-20",
                                           tags: ["tag"]
                                         }
                                       ]));
      main.playlistEntries = [
            {
              id: "list",
              name: "List",
              entryIds: ["song"]
            }
          ];
      const home = provider.buildHomeItems();
      check(!home.some(item => item.kind === "section" && ["home.recentlyPlayed", "home.mostPlayed", "home.tags", "home.artists", "home.playlists"].indexOf(item.name) >= 0), "selected home sections");
      record("launcher-preview-home");
      file("hold", "play", "play-held-start");
    } else if (phase === "play-held-start") {
      mark = rows().length;
      main.playEntry(admittedEntry, selected);
      phase = "play-held";
    } else if (phase === "play-held" && actions("play").length) {
      admittedEntry.url = "https://inert.invalid/foreign";
      updatePolicy({
                     autoSaveMp3AfterPlayback: false
                   });
      file("release", "play", "play-finish");
    } else if (phase === "play-finish" && !main.playbackBusy && !main.downloadBusy && Date.now() - since > 300) {
      check(actions("download-mp3").length === 1 && actions("download-mp3")[0].argv[2] === "https://inert.invalid/admitted", "captured policy and scalar track after held completion");
      record("held-playback-policy-target");
      updatePolicy({
                     autoSaveMp3AfterPlayback: true
                   });
      file("hold", "play", "retired-start");
    } else if (phase === "retired-start") {
      mark = rows().length;
      main.playEntry({
                       id: "retired",
                       title: "Retired",
                       url: "https://inert.invalid/retired"
                     }, selected);
      phase = "retired-held";
    } else if (phase === "retired-held" && actions("play").length) {
      selected.alive = false;
      file("release", "play", "retired-finish");
    } else if (phase === "retired-finish" && !main.playbackBusy && Date.now() - since > 350) {
      check(actions("download-mp3").length === 0, "retired playback cannot download");
      record("retired-playback");
      selected.alive = true;
      main.applyState('{"isPlaying":false}');
      main.applyQueue('[{"id":"first","title":"First","url":"https://inert.invalid/first"}]');
      mark = rows().length;
      main.startQueue(selected);
      phase = "queue-first";
    } else if (phase === "queue-first" && !main.playbackBusy && !main.downloadBusy && Date.now() - since > 500) {
      check(actions("download-mp3").length === 1, "initial queue policy");
      updatePolicy({
                     autoSaveMp3AfterPlayback: false
                   });
      main.applyQueue('[{"id":"second","title":"Second","url":"https://inert.invalid/second"}]');
      main.applyState('{"isPlaying":false,"endReason":"finished","updatedAt":"queue-2"}');
      phase = "queue-second";
    } else if (phase === "queue-second" && !main.playbackBusy && !main.downloadBusy && Date.now() - since > 500) {
      check(actions("download-mp3").length === 2, "queue continuation retains admitted policy");
      check(actions("download-mp3")[1].argv[2] === "https://inert.invalid/second", "queue continuation retains admitted policy");
      selected.alive = false;
      main.applyState('{"isPlaying":false,"endReason":"finished","updatedAt":"queue-3"}');
      phase = "queue-retired";
    } else if (phase === "queue-retired" && Date.now() - since > 350) {
      check(actions("play").length === 2 && !main.queueActive, "retired queue cannot start another track");
      record("queue-capture-retirement");
      selected.alive = true;
      updatePolicy({
                     autoSaveMp3AfterPlayback: true
                   });
      file("hold", "queue-load-library", "autoplay-start");
    } else if (phase === "autoplay-start") {
      mark = rows().length;
      main.autoplaySavedTracks(false, selected);
      phase = "autoplay-held";
    } else if (phase === "autoplay-held" && actions("queue-load-library").length) {
      updatePolicy({
                     autoSaveMp3AfterPlayback: false
                   });
      file("release", "queue-load-library", "autoplay-finish");
    } else if (phase === "autoplay-finish" && !main.playbackBusy && !main.downloadBusy && actions("download-mp3").length === 1) {
      check(actions("download-mp3")[0].argv[2] === "https://inert.invalid/auto", "saved autoplay retains policy");
      record("held-saved-autoplay");
      main.stopQueue();
      file("hold", "queue-enqueue", "batch-start");
    } else if (phase === "batch-start") {
      mark = rows().length;
      main.startQueueBatch([
                             {
                               id: "a",
                               url: "https://inert.invalid/a"
                             },
                             {
                               id: "b",
                               url: "https://inert.invalid/b"
                             }
                           ], {
                             finalAction: "start"
                           }, selected);
      phase = "batch-held";
    } else if (phase === "batch-held" && actions("queue-enqueue").length) {
      selected.alive = false;
      file("release", "queue-enqueue", "batch-finish");
    } else if (phase === "batch-finish" && !main.queueBatchBusy && Date.now() - since > 350) {
      check(actions("queue-enqueue").length === 1 && actions("play").length === 0, "retired batch cannot enqueue or play another stage");
      record("held-batch-retirement");
      finish();
    }
  }
  function clipper() {
    if (phase === "clip-start" && main.wtypeAvailable)
      file("hold", "selection", "selection-start");
    else if (phase === "selection-start") {
      mark = rows().length;
      main.addSelectedToPage(7, selected);
      phase = "selection-held";
    } else if (phase === "selection-held" && rows().slice(mark).some(row => row.endpoint === "wl-paste")) {
      updatePolicy({
                     enableTodoIntegration: false
                   });
      file("release", "selection", "selection-finish");
    } else if (phase === "selection-finish" && todoApi.saves === 1) {
      check(todoApi.pluginSettings.todos[0].pageId === 7 && todoApi.pluginSettings.todos[0].text === "Admitted selection", "selected admitted Todo policy and target");
      main.addTodoWithText("Disabled", 8, selected);
      main.addTodoWithText("Shared disabled", 8);
      check(todoApi.saves === 1, "disabled selected/shared admission");
      record("held-selection-and-disabled-admission");
      updatePolicy({
                     enableTodoIntegration: true
                   });
      main.showTodoPageSelector("Selector text", selected);
      updatePolicy({
                     enableTodoIntegration: false
                   });
      main.handleTodoPageSelected(9, "Nine");
      check(todoApi.saves === 2 && todoApi.pluginSettings.todos[1].pageId === 9, "selector retains admitted policy");
      updatePolicy({
                     enableTodoIntegration: true
                   });
      main.showTodoPageSelector("Retired selector", selected);
      selected.alive = false;
      main.handleTodoPageSelected(10, "Ten");
      check(todoApi.saves === 2, "retired selector cannot write shared Todo");
      record("selector-policy-retirement");
      selected.alive = true;
      file("hold", "selection", "retired-selection-start");
    } else if (phase === "retired-selection-start") {
      mark = rows().length;
      main.addSelectedToPage(11, selected);
      phase = "retired-selection-held";
    } else if (phase === "retired-selection-held" && rows().slice(mark).some(row => row.endpoint === "wl-paste")) {
      selected.alive = false;
      file("release", "selection", "retired-selection-finish");
    } else if (phase === "retired-selection-finish" && Date.now() - since > 350) {
      check(todoApi.saves === 2, "retired selection cannot write Todo");
      record("held-selection-retirement");
      selected.alive = true;
      updatePolicy({
                     autoPasteDelay: 150
                   });
      mark = rows().length;
      main.triggerAutoPaste(undefined, selected);
      updatePolicy({
                     autoPasteDelay: 900
                   });
      selected.alive = false;
      phase = "paste-retired";
    } else if (phase === "paste-retired" && Date.now() - since > 350) {
      check(!rows().slice(mark).some(row => row.endpoint === "wtype"), "retired delayed paste refused");
      selected.alive = true;
      updatePolicy({
                     autoPasteDelay: 150
                   });
      mark = rows().length;
      main.triggerAutoPaste(undefined, selected);
      updatePolicy({
                     autoPasteDelay: 900
                   });
      phase = "paste-live";
    } else if (phase === "paste-live" && Date.now() - since > 350) {
      check(rows().slice(mark).filter(row => row.endpoint === "wtype").length === 1, "live delayed paste retains original delay");
      record("delayed-paste-policy-retirement");
      finish();
    }
  }
  function finish() {
    console.log("CONTENT_RUNTIME: PASS " + plugin);
    Qt.exit(0);
  }
  function drive() {
    check(Date.now() - since < 18000, "finite lifetime phase");
    if (plugin === "music-search")
      music();
    else
      clipper();
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  SettingsBootstrap {}
  Timer {
    interval: 30
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
