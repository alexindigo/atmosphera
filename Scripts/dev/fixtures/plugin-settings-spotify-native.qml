// Native selected settings, actual runtime Panel actions, independent documents.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_SPOTIFY_SCOPE")
  readonly property string mode: Quickshell.env("PHA_SPOTIFY_MODE")
  readonly property string boundary: Quickshell.env("PHA_SPOTIFY_BOUNDARY")
  readonly property string caseDir: Quickshell.env("PHA_SPOTIFY_CASE")
  readonly property bool oldRed: Quickshell.env("PHA_SPOTIFY_OLD_RED") === "1"
  property bool started: false
  property string phase: "startup"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  property var api: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var main: null
  property var presentations: []
  property var receipt: null
  property string afterDisk: ""
  property string diskBoundary: ""
  property var actionExpected: null
  property int requestCount: 0
  property int holdCursor: 0
  property var heldRequests: []
  property var searchExit: null
  readonly property string heldSearchPath: "/v1/search?q=held%20query&type=album%2Cplaylist%2Ctrack"
  readonly property var targetApi: scope === "shared" ? api : selected
  readonly property var targetPanel: presentations.length ? presentations[scope === "shared" ? 0 : 1].panel : null
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/spotify-player/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/spotify-player/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: root.caseDir + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: requests
    path: root.caseDir + "/requests.jsonl"
    blockLoading: true
  }
  FileView {
    id: authorizedFile
    path: Quickshell.env("PHA_SPOTIFY_OUTPUT") + "/persisted/action-retired.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("operational action preserves independent native documents: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1280
    implicitHeight: 1000
    Item {
      id: content
      width: 1280
      height: 1000
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("SPOTIFY_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
    for (var list of [object?.data, object?.children]) {
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
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("spotify-player", entry, component, content, context, {
                                           screen: Quickshell.screens[0]
                                         });
    check(item !== null, "actual " + entry + " constructs");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    dictionaryFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text()), dictionary = JSON.parse(dictionaryFile.text());
    Registry.installedPlugins = {
      "spotify-player": manifest
    };
    Service._openSettingsOwner("spotify-player", function (owner) {
      try {
        check(owner !== null, "actual native owner");
        api = Service.createPluginAPI("spotify-player", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          "spotify-player": {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        var contexts = [0, 1, 2].map(index => PluginInstances.apiFor("spotify-player", {
                                                                       kind: "bar",
                                                                       list: "global",
                                                                       section: "left",
                                                                       index: index
                                                                     }));
        selected = contexts[0];
        sibling = contexts[1];
        inherited = contexts[2];
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function documents(name) {
    if (name === "authorized") {
      authorizedFile.reload();
      authorizedFile.waitForJob();
      return JSON.parse(authorizedFile.text()).values;
    }
    expectedFile.reload();
    expectedFile.waitForJob();
    return JSON.parse(expectedFile.text())[name];
  }
  function values(name) {
    var expected = documents(name), base = Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared);
    return [base].concat(expected.bar.widgets.left.map(row => Object.assign({}, base, row.instanceSettings || {})));
  }
  function observe(name) {
    if (oldRed)
      return;
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], client = main.settingsConsumerFor(item.api.settingsContext);
      check(item.bar.settingsConsumer === client && item.second.settingsConsumer === client && item.panel.settingsConsumer === client, "all runtime entries share selected client identity");
      check(item.api.pluginSettings.clientId === expected[i].clientId, "native effective applied credentials");
      check(item.api.pluginSettings.accessToken === expected[i].accessToken && item.api.pluginSettings.refreshToken === expected[i].refreshToken && item.api.pluginSettings.tokenExpiresAt === expected[i].tokenExpiresAt, "native operational tokens survive separate cold consumers");
      check(find(item.panel, child => child.objectName === "spotify-authorization-status" && child.text === item.api.tr("authorization.token-available")), "actual runtime authorization status renders");
    }
    check(main._settingsConsumers.size === 4, "one Main client per API not per view");
  }
  function ready(name) {
    var expected = values(name);
    return presentations.every((item, i) => item.api.pluginSettings.clientId === expected[i].clientId);
  }
  function probe(name, next) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_SPOTIFY_DISK"), caseDir, Quickshell.env("PHA_SPOTIFY_OUTPUT") + "/persisted", name, JSON.stringify(actionExpected)];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped Settings opens");
    phase = next;
  }
  function edit() {
    var control = find(popup.settingsPage, item => item.label === "Client ID" && item.editCommitted !== undefined);
    check(control, "actual credential control");
    control.text = "selected";
    control.editCommitted();
    check(popup._pageApi.field("clientId").value === "selected", "credential control stages selected field");
    check(targetApi.pluginSettings.clientId !== "selected", "draft credentials are not applied credentials");
    if (!oldRed) {
      check(!find(popup.settingsPage, item => item.objectName === "spotify-authorize"), "Settings has no authorization action");
      check(find(popup.settingsPage, item => item.text === targetApi.tr("authorization.settings-guidance")), "Settings explains Apply then runtime authorization");
    }
    for (var key of ["clientSecret", "playerId", "callbackPort", "message"])
      check(!popup._pageApi.field(key)?.pendingIntent, "untouched configuration has no intent: " + key);
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function requestRows() {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split("\n").filter(Boolean).map(line => JSON.parse(line));
  }
  function beginHold() {
    holdCursor = requestRows().reduce((latest, row) => Math.max(latest, row.id || 0), 0);
    heldRequests = [];
  }
  function heldRequest(rows, path, client, method) {
    var seen = rows.filter(row => row.id > holdCursor && row.held && row.path === path && row.client === client && row.method === method);
    check(seen.length <= 1, "unambiguous held admission: " + path);
    return seen[0];
  }
  function watchToken(row) {
    var xhr = targetPanel.settingsConsumer?._request;
    check(xhr && xhr.readyState > XMLHttpRequest.UNSENT && xhr.readyState < XMLHttpRequest.DONE, "observe the admitted, pending token exchange before invalidating it");
    return {
      id: row.id,
      outcome: function () {
        // Abort resets this observed, already-admitted object to UNSENT.
        if (xhr.readyState === XMLHttpRequest.UNSENT)
          return "cancelled";
        // DONE is observed on a later fixture turn, after the runtime's
        // synchronous ready-state dispatch, and must bear this response ID.
        return xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200 && xhr.getResponseHeader("X-Fixture-Request") === String(row.id) ? "completed" : "pending";
      }
    };
  }
  function heldRequestsSettled() {
    var rows = requestRows();
    var outcomes = heldRequests.map(request => rows.some(row => row.cancelled === request.id) ? "cancelled" : request.outcome());
    if (outcomes.includes("pending"))
      return false;
    check(heldRequests.length > 0, "held admission before settlement");
    console.log("SPOTIFY_HELD_SETTLED " + phase + " " + heldRequests.map((req, i) => req.id + ":" + outcomes[i]).join(","));
    return true;
  }
  function actionData() {
    return scope === "shared" ? actionExpected.shared : actionExpected.bar.widgets.left[0].instanceSettings;
  }
  function button(name) {
    var control = find(targetPanel, item => item.objectName === name && item.clicked !== undefined);
    check(control, "actual runtime action: " + name);
    control.clicked();
  }
  function drive() {
    check(Date.now() - phaseStarted < 22000, "finite operation deadline");
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      presentations = [api, selected, sibling, inherited].map(context => ({
        api: context,
        bar: create("barWidget", context),
        second: create("barWidget", context),
        panel: create("panel", context)
      }));
      phase = "initial";
    } else if (phase === "initial") {
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : mode === "actions" ? "following" : mode === "action-cold" ? "authorized" : boundary;
      if (mode !== "actions") {
        if (!ready(name))
          return;
        observe(name);
      }
      if (mode === "cold" || mode === "action-cold")
        finish();
      else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else if (mode === "actions")
        phase = "action-start";
      else
        open("reset-page");
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "Settings construction has no intent");
      edit();
      check(!popup.requestClose(), "dirty Close refuses");
      popup.confirmDiscard();
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor)
      probe("discarded", "open-edit");
    else if (phase === "open-edit")
      open("edit-page");
    else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
      edit();
      apply("applied");
    } else if (phase === "applied" && accepted() && ready("edited")) {
      observe("edited");
      probe("edited", oldRed ? "old-refresh" : "finish");
    } else if (phase === "old-refresh") {
      main.refreshAccessToken(targetApi);
      phase = "old-refresh-wait";
    } else if (phase === "old-refresh-wait" && !main._request && api.pluginSettings.accessToken !== "seed-access") {
      check(requestRows().some(row => row.path === "/api/token" && row.client === "selected"), "original refresh uses saved selected credentials");
      throw new Error("original shared refresh defect did not reproduce");
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field("clientId").reset(), "native staged credential Reset");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      api.pluginSettings.clientId = "following";
      phase = "base-saving";
      api.saveSettings(result => {
        if (result.status === "saved")
          root.phase = "base-changed";
        else
          root.fail("shared native propagation receipt");
      });
    } else if (phase === "base-changed" && ready("following")) {
      observe("following");
      probe("following", "finish");
    } else if (phase === "action-start") {
      // Actions always use applied runtime values, including while an editor's
      // different preview is active. This is not a page-to-owner capability.
      actionExpected = documents(Quickshell.env("PHA_SPOTIFY_ACTION_BASE") || "following");
      actionData().clientId = "action-selected";
      actionData().playerId = "action-player";
      targetApi.pluginSettings.clientId = "action-selected";
      targetApi.pluginSettings.playerId = "action-player";
      phase = "action-saving";
      targetApi.saveSettings(result => {
        if (result.status === "saved")
          root.phase = "action-saved";
        else
          root.fail("action applied native source receipt");
      });
    } else if (phase === "action-saved")
      probe("action-applied", "wrong-state-create");
    else if (phase === "wrong-state-create")
      probe("marker:wrong-state:1", "wrong-state-start");
    else if (phase === "wrong-state-start") {
      requestCount = requestRows().filter(row => row.path === "/api/token").length;
      button("spotify-authorize");
      phase = "wrong-state-wait";
    } else if (phase === "wrong-state-wait" && targetPanel.settingsConsumer?.error === "callback") {
      check(requestRows().filter(row => row.path === "/api/token").length === requestCount, "wrong callback state cannot start token exchange");
      probe("marker:wrong-state:0", "wrong-state-disk");
    } else if (phase === "wrong-state-disk")
      probe("action-wrong-state", "auth-open");
    else if (phase === "auth-open")
      open("auth-draft");
    else if (phase === "auth-draft" && popup.opened && popup.settingsPage) {
      check(find(popup.settingsPage, item => item.objectName === "spotify-authorization-status" && item.text === targetApi.tr("authorization.failed")), "Settings shows current Main-owned authorization status without an action capability");
      var control = find(popup.settingsPage, item => item.label === "Client ID" && item.editCommitted !== undefined);
      check(control, "draft during authorization");
      control.text = "draft-must-not-authorize";
      control.editCommitted();
      button("spotify-authorize");
      phase = "auth-result";
    } else if (phase === "auth-result" && targetPanel.settingsConsumer?.status === "token-available" && !targetPanel.settingsConsumer.busy) {
      check(!requestRows().some(row => row.client === "draft-must-not-authorize"), "runtime authorization never uses page draft credentials");
      actionData().accessToken = "access-action-selected";
      actionData().refreshToken = "refresh-action-selected";
      actionData().tokenExpiresAt = "bounded-generated-expiry";
      popup.confirmDiscard();
      phase = "auth-closed";
    } else if (phase === "auth-closed" && !popup._editor)
      probe("action-authorized", "devices");
    else if (phase === "devices") {
      button("spotify-devices");
      phase = "devices-result";
    } else if (phase === "devices-result" && targetPanel.settingsConsumer?.availableDevices.indexOf("device-selected") >= 0) {
      check(find(targetPanel, item => item.text && String(item.text).indexOf("device-selected") >= 0), "actual runtime device result renders");
      targetPanel.searchForQuery("controlled query");
      phase = "search-result";
    } else if (phase === "search-result" && targetPanel.searchResults.length === 1) {
      check(find(targetPanel, item => item.text === "Controlled track"), "actual search child renders selected result");
      targetPanel.sendPlayRequest(targetPanel.searchResults[0]);
      phase = "play-result";
    } else if (phase === "play-result" && requestRows().some(row => row.method === "PUT" && row.path === "/v1/me/player/shuffle?state=false&device_id=action-player")) {
      var play = requestRows().find(row => row.method === "PUT" && row.path === "/v1/me/player/play?device_id=action-player");
      check(play && play.bearer === "Bearer access-action-selected" && JSON.parse(play.body).uris[0] === "spotify:track:controlled", "play and follow-up shuffle retain originating native token/player");
      targetPanel.playlistViewActive = true;
      phase = "playlists-result";
    } else if (phase === "playlists-result" && targetPanel.playlistResults.length === 1) {
      check(find(targetPanel, item => item.text === "Controlled playlist"), "actual playlist child renders");
      check(main.refreshAccessToken(targetApi), "runtime selected refresh admission");
      phase = "refresh-result";
    } else if (phase === "refresh-result" && !targetPanel.settingsConsumer.busy) {
      check(requestRows().some(row => row.client === "action-selected" && row.body.indexOf("grant_type=refresh_token") >= 0 && row.body.indexOf("refresh-action-selected") >= 0), "refresh captures originating credentials and operational refresh token");
      probe("action-refreshed", "hold-create");
    } else if (phase === "hold-create")
      probe("marker:hold-action-selected:1", "hold-api-create");
    else if (phase === "hold-api-create")
      probe("marker:hold-api:1", "hold-start");
    else if (phase === "hold-start") {
      beginHold();
      targetPanel.searchForQuery("held query");
      var job = targetPanel.settingsConsumer?._slots.get("search");
      check(job, "observe the held search process before invalidating it");
      searchExit = {
        complete: false
      };
      var receipt = searchExit;
      job.exited.connect(code => receipt.complete = code === 0);
      button("spotify-authorize");
      phase = "hold-pending";
    } else if (phase === "hold-pending") {
      var rows = requestRows(), token = heldRequest(rows, "/api/token", "action-selected", "POST"), search = heldRequest(rows, heldSearchPath, "", "GET");
      if (!token || !search)
        return;
      heldRequests = [watchToken(token),
                      {
                        id: search.id,
                        outcome: () => searchExit.complete ? "completed" : "pending"
                      }
          ];
      targetApi.pluginSettings.clientId = "replacement";
      actionData().clientId = "replacement";
      phase = "replacement-saving";
      targetApi.saveSettings(result => {
        if (result.status === "saved")
          root.phase = "replacement-saved";
        else
          root.fail("replacement native receipt");
      });
    } else if (phase === "replacement-saved")
      probe("marker:hold-action-selected:0", "release-api");
    else if (phase === "release-api")
      probe("marker:hold-api:0", "replacement-wait");
    else if (phase === "replacement-wait" && heldRequestsSettled()) {
      check(targetApi.pluginSettings.accessToken === "access-action-selected", "old source cannot adopt a late token");
      check(targetPanel.searchResults.length === 0, "held old search cannot repopulate replacement source");
      probe("action-replaced", "retire-hold");
    } else if (phase === "retire-hold")
      probe("marker:hold-replacement:1", "retire-start");
    else if (phase === "retire-start") {
      beginHold();
      button("spotify-authorize");
      phase = "retire-pending";
    } else if (phase === "retire-pending") {
      var token = heldRequest(requestRows(), "/api/token", "replacement", "POST");
      if (!token)
        return;
      heldRequests = [watchToken(token)];
      Service.loadedPlugins = ({});
      probe("marker:hold-replacement:0", "retired");
    } else if (phase === "retired" && heldRequestsSettled()) {
      check(main._settingsConsumers.size === 0 && targetPanel.settingsConsumer === null, "last runtime context retires Main client and IO");
      check(targetApi.pluginSettings.accessToken === "access-action-selected", "retired token response cannot publish");
      probe("action-retired", "finish");
    } else if (phase === "finish")
      finish();
  }
  function finish() {
    console.log("SPOTIFY_NATIVE: PASS " + scope + " " + mode);
    Qt.exit(0);
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 80
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
