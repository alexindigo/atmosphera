// Explicit-context lifetime collaborators; real native writer proof is separate.
import QtQuick
import Quickshell
import Quickshell.Io
import "Services/Plugins/PluginSettingsRead.js" as Read
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_HTTP_PLUGIN")
  readonly property bool news: plugin === "news"
  readonly property bool habitica: plugin === "habitica"
  property var data: null
  property var main: null
  property var shared: null
  property var selected: null
  property var peer: null
  property var client: null
  property var peerClient: null
  property var bar: null
  property var second: null
  property var panel: null
  property var toasts: []
  property int phase: 0
  property double phaseTime: Date.now()
  property string legacyCache: JSON.stringify({
                                                user: {
                                                  profile: {
                                                    name: "unqualified-legacy"
                                                  }
                                                },
                                                timestamp: 2140000000
                                              })
  readonly property string liveCache: habitica && shared ? shared.pluginSettings._habiticaCache ?? "" : ""
  onLiveCacheChanged: {
    if (!habitica || !liveCache || liveCache === legacyCache)
      return;
    try {
      check(JSON.parse(liveCache).sourceUserId === "shared", "only original shared cache writer publishes qualified shared account");
    } catch (error) {
      fail(error);
    }
  }
  onPhaseChanged: phaseTime = Date.now()
  FileView {
    id: input
    path: Quickshell.env("PHA_HTTP_CASE") + "/input.json"
    blockLoading: true
  }
  FileView {
    id: requests
    path: Quickshell.env("PHA_HTTP_REQUESTS")
    blockLoading: true
  }
  Process {
    id: nativeDisk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete native cache document");
      else {
        console.log("HTTP_LIFECYCLE: PASS " + plugin);
        Qt.exit(0);
      }
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.toasts = root.toasts.concat([
                                         {
                                           title: title,
                                           description: description
                                         }
                                       ]);
    }
  }
  Component {
    id: apiFactory
    QtObject {
      id: api
      property var manifest: root.data.manifest
      property string pluginDir: root.data.directory
      required property var pluginSettings
      property var mainInstance: root.main
      property bool alive: true
      property int writes: 0
      property var lifetime: ({
                                alive: true
                              })
      Component.onDestruction: lifetime.alive = false
      readonly property var settingsContext: Read.context(lifetime, function () {
        return api.pluginSettings;
      }, function () {
        return api.alive;
      })
      function tr(key, params) {
        return key;
      }
      function trp(key, count) {
        return key + " " + count;
      }
      function saveSettings() {
        pluginSettings = Object.assign({}, pluginSettings);
        ++writes;
        return true;
      }
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1100
    implicitHeight: 900
    Item {
      id: content
      anchors.fill: parent
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("HTTP_LIFECYCLE_ASSERT: " + plugin + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate, visited) {
    var seen = visited || new Set();
    if (!object || seen.has(object))
      return null;
    seen.add(object);
    if (predicate(object))
      return object;
    for (var list of [object.data, object.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var result = find(child, predicate, seen);
        if (result)
          return result;
      }
    }
    return null;
  }
  function create(entry, api) {
    var component = Qt.createComponent("file://" + data.directory + "/" + data.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var properties = {
      pluginApi: api
    };
    if (entry === "barWidget")
      properties.screen = Quickshell.screens[0];
    var item = component.createObject(content, properties);
    check(item, "actual " + entry + " constructs");
    return item;
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function change(api, fields) {
    api.pluginSettings = Object.assign({}, api.pluginSettings, fields);
  }
  function source(api, name) {
    change(api, news ? {
                         category: name
                       } : habitica ? {
                                        habiticaUserId: name
                                      } : {
             topics: name
           });
  }
  function begin() {
    if (phase || !Settings.isLoaded)
      return;
    input.waitForJob();
    data = JSON.parse(input.text());
    var base = Object.assign({}, data.manifest.metadata.defaultSettings, news ? {
                                                                                  apiKey: "controlled-key",
                                                                                  category: "general"
                                                                                } : habitica ? {
                                                                                                 habiticaUserId: "shared",
                                                                                                 habiticaApiToken: "controlled-token",
                                                                                                 _habiticaCache: legacyCache
                                                                                               } : {
                               serverUrl: data.base,
                               topics: "shared",
                               enableToasts: false,
                               readMessageIds: ["protected-read"],
                               authMethod: "token",
                               authToken: "shared-token"
                             });
    if (habitica) {
      phase = -1;
      var registry = {};
      registry[plugin] = data.manifest;
      Registry.installedPlugins = registry;
      Service._openSettingsOwner(plugin, function (owner) {
        try {
          check(owner, "actual native shared cache owner");
          shared = Service.createPluginAPI(plugin, data.manifest, owner, {}, {}, {});
          var loaded = {};
          loaded[plugin] = {
            api: shared
          };
          Service.loadedPlugins = loaded;
          setup(base);
        } catch (error) {
          fail(error);
        }
      });
    } else {
      shared = apiFactory.createObject(content, {
                                         pluginSettings: base
                                       });
      setup(base);
    }
  }
  function setup(base) {
    main = create("main", shared);
    shared.mainInstance = main;
    var chosen = Object.assign({}, base, news ? {
                                                  category: "science"
                                                } : habitica ? {
                                                                 habiticaUserId: "selected",
                                                                 enableTagFilter: true,
                                                                 selectedTagId: "tag-a",
                                                                 showHabits: true,
                                                                 showChecklistItems: true
                                                               } : {
                                 topics: "selected",
                                 enableToasts: true,
                                 authToken: "selected-token"
                               });
    selected = apiFactory.createObject(content, {
                                         pluginSettings: chosen
                                       });
    peer = apiFactory.createObject(content, {
                                     pluginSettings: Object.assign({}, chosen)
                                   });
    client = main.settingsConsumerFor(selected.settingsContext);
    peerClient = main.settingsConsumerFor(peer.settingsContext);
    bar = create("barWidget", selected);
    second = create("barWidget", selected);
    panel = create("panel", selected);
    phase = 1;
  }
  function resultText(name) {
    return find(panel, item => item.text === (habitica ? "account-" : "headline-") + name);
  }
  function drive() {
    check(Date.now() - phaseTime < 16000, "finite individual outcome deadline");
    if (!phase) {
      begin();
      return;
    }
    if (phase === 1) {
      check(bar.settingsConsumer === client && second.settingsConsumer === client && panel.settingsConsumer === client, "same-context views share exact request producer");
      if (habitica) {
        check(shared.pluginSettings._habiticaCache === legacyCache && main.user?.profile?.name !== "unqualified-legacy", "unqualified legacy cache not assigned to a new source");
        phase = 2;
      } else if (resultText(news ? "science" : "selected"))
        phase = 2;
    } else if (phase === 2) {
      if (habitica) {
        if (client.isLoading || !resultText("selected") || main.isLoading || shared.pluginSettings._habiticaCache === legacyCache)
          return;
        check(client.visibleTodos.length === 1 && client.visibleDailies.length === 1 && client.visibleHabits.length === 1, "selected task filter and limits reach actual Panel model");
        check(find(panel, item => item.text === "task-selected-0") && !find(panel, item => item.text === "task-selected-1"), "actual filtered task child, not raw client array");
        check(bar.tooltipText.indexOf("account-selected") >= 0, "actual Bar account tooltip");
        var cached = JSON.parse(shared.pluginSettings._habiticaCache);
        check(cached.sourceUserId === "shared" && cached.user.profile.name === "account-shared" && selected.writes === 0 && peer.writes === 0, "only original shared cache writer publishes qualified shared account");
        change(selected, {
                 selectedTagId: "tag-b",
                 maxTodos: 1
               });
        phase = 3;
      } else {
        var count = rows().filter(row => row.name === (news ? "science" : "selected")).length;
        check(count === 2, "two contexts have two producers despite three views of one context");
        if (!news) {
          if (peerClient.isLoading || peerClient.messages.length === 0)
            return;
          check(toasts.length === 1, "one common toast for duplicate event across current clients");
          var button = find(panel, item => item.tooltipText === "panel.markAllRead" && item.clicked !== undefined);
          check(button, "actual Panel mark-read action");
          button.clicked();
          check(shared.writes === 1 && selected.writes === 0 && shared.pluginSettings.readMessageIds.indexOf("protected-read") >= 0 && shared.pluginSettings.readMessageIds.indexOf("message-selected") >= 0, "read action retains protected history and one original writer");
          check(client.unreadCount === 0 && peerClient.unreadCount === 0, "all selected projections observe the one read owner");
        }
        second.destroy();
        second = null;
        check(main.settingsConsumerFor(selected.settingsContext) === client, "view loss retains context producer");
        source(selected, "held");
        phase = 4;
      }
    } else if (phase === 3) {
      if (!find(panel, item => item.text === "task-selected-1"))
        return;
      check(!find(panel, item => item.text === "task-selected-0"), "live selected tag does not reuse another task projection");
      var complete = find(panel, item => item.tooltipText === "panel.complete" && item.clicked !== undefined && item.visible);
      check(complete, "actual selected score button");
      complete.clicked();
      phase = 10;
    } else if (phase === 4) {
      if (!rows().some(row => row.name === "held"))
        return;
      check(client.newsData?.length === 0 || client.messages?.length === 0, "held replacement clears old-source results");
      source(selected, "replacement");
      phase = 5;
    } else if (phase === 5 && resultText("replacement")) {
      if (!news) {
        change(selected, {
                 authMethod: "basic",
                 authUsername: "literal user",
                 authPassword: "literal:pass"
               });
        phase = 6;
      } else
        phase = 7;
    } else if (phase === 6) {
      if (!rows().some(row => row.name === "replacement" && row.authorization === "Basic " + Qt.btoa("literal user:literal:pass")) || client.isLoading)
        return;
      check(client.messages.length === 1 && client.messages[0].message === "Basic " + Qt.btoa("literal user:literal:pass"), "same-topic auth replacement reaches fresh request/result");
      phase = 7;
    } else if (phase === 7 && Date.now() - phaseTime > 1700) {
      check(resultText("replacement"), "late held response cannot repopulate replacement");
      if (!news) {
        source(selected, " , ");
        phase = 8;
      } else {
        change(selected, {
                 apiKey: "YOUR_API_KEY_HERE"
               });
        phase = 8;
      }
    } else if (phase === 8) {
      check(!client.isLoading && (news ? client.newsData.length === 0 : client.messages.length === 0), "empty/unconfigured source clears old results");
      source(selected, "held");
      if (news)
        change(selected, {
                 apiKey: "controlled-key"
               });
      phase = 9;
    } else if (phase === 9) {
      if (rows().filter(row => row.name === "held").length < 2)
        return;
      selected.alive = false;
      phase = 20;
    } else if (phase === 10) {
      if (!rows().some(row => row.method === "POST" && row.user === "selected"))
        return;
      peerClient.completeTask({
                                id: "peer-must-refuse"
                              });
      phase = 101;
    } else if (phase === 101 && Date.now() - phaseTime > 200) {
      check(rows().filter(row => row.method === "POST").length === 1, "common score admission refuses second client while held");
      source(selected, "held");
      phase = 11;
    } else if (phase === 11) {
      if (!rows().some(row => row.user === "held"))
        return;
      check(!main.isScoring && client.user.profile === undefined, "account replacement releases old score and clears account projection");
      source(selected, "replacement");
      phase = 12;
    } else if (phase === 12 && resultText("replacement") && !client.isLoading) {
      peerClient.scoreChecklistItem({
                                      id: "literal/task '"
                                    }, {
                                      id: "literal/item '"
                                    });
      phase = 13;
    } else if (phase === 13) {
      if (!rows().some(row => row.method === "POST" && row.path.indexOf("checklist") >= 0))
        return;
      check(rows().some(row => row.user === "selected" && row.path === "/api/v3/tasks/literal%2Ftask%20'/checklist/literal%2Fitem%20'/score"), "literal captured checklist target/auth");
      source(selected, "held");
      phase = 14;
    } else if (phase === 14) {
      if (rows().filter(row => row.user === "held").length < 2)
        return;
      selected.alive = false;
      phase = 20;
    } else if (phase === 20 && Date.now() - phaseTime > 1700) {
      check(!main._settingsConsumers.has(selected.settingsContext) && bar.settingsConsumer === null && panel.settingsConsumer === null, "retirement removes client and selected views");
      if (habitica) {
        check(!rows().some(row => row.user === "held" && row.path !== "/api/v3/user"), "retired held chain cannot start next stage");
        var cached = JSON.parse(shared.pluginSettings._habiticaCache);
        check(cached.sourceUserId === "shared" && selected.writes === 0, "retired/selected accounts cannot overwrite protected shared cache");
      }
      if (habitica) {
        nativeDisk.command = ["python3", "-B", Quickshell.env("PHA_HTTP_CACHE_DISK"), Quickshell.env("PHA_HTTP_CASE"), Quickshell.env("PHA_HTTP_OUTPUT")];
        nativeDisk.running = true;
        phase = 21;
      } else {
        console.log("HTTP_LIFECYCLE: PASS " + plugin);
        Qt.exit(0);
      }
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
