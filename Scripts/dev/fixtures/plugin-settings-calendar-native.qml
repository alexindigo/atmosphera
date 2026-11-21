// Native page intent -> independent files -> actual calendar Panel/Bar.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Location
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_CALENDAR_SCOPE")
  readonly property string mode: Quickshell.env("PHA_CALENDAR_MODE")
  readonly property string boundary: Quickshell.env("PHA_CALENDAR_BOUNDARY")
  readonly property bool oldRed: Quickshell.env("PHA_CALENDAR_OLD_RED") === "1"
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
  property var requestedRanges: []
  property int beforeRetirementRequests: 0
  property bool availabilityChecked: false
  QtObject {
    id: provider
    function loadEvents(ahead, behind) {
      root.requestedRanges = root.requestedRanges.concat([
                                                           {
                                                             ahead: ahead,
                                                             behind: behind
                                                           }
                                                         ]);
    }
    function loadCalendars() {
    }
  }
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/weekly-calendar/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/weekly-calendar/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: Quickshell.env("PHA_CALENDAR_CASE") + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete calendar documents: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1280
    implicitHeight: 900
    Item {
      id: content
      width: 1280
      height: 900
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("CALENDAR_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var result = find(child, predicate);
        if (result)
          return result;
      }
    }
    return null;
  }
  function all(object, predicate, matches) {
    if (object && predicate(object))
      matches.push(object);
    for (var list of [object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list)
        all(child, predicate, matches);
    }
    return matches;
  }
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("weekly-calendar", entry, component, content, context, {
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
      "weekly-calendar": manifest
    };
    CalendarService.available = oldRed;
    CalendarService.dataProvider = provider;
    Service._openSettingsOwner("weekly-calendar", function (owner) {
      try {
        check(owner !== null, "actual native owner");
        api = Service.createPluginAPI("weekly-calendar", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          "weekly-calendar": {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        var contexts = [0, 1, 2].map(index => PluginInstances.apiFor("weekly-calendar", {
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
  function values(name) {
    expectedFile.reload();
    expectedFile.waitForJob();
    var expected = JSON.parse(expectedFile.text())[name];
    return [expected.shared].concat(expected.bar.widgets.left.map(row => Object.assign({}, expected.shared, row.instanceSettings || {})));
  }
  function ready(name) {
    var expected = values(name);
    return presentations.every((item, index) => Object.keys(api.manifest.metadata.settingsSchema.fields).every(key => item.api.pluginSettings[key] === expected[index][key]));
  }
  function observe(name) {
    if (oldRed)
      return;
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], client = main.settingsConsumerFor(item.api.settingsContext);
      check(item.bar.settingsConsumer === client && item.second.settingsConsumer === client && item.panel.mainInstance === client, "actual views share exact selected calendar client");
      check(item.panel.allowAttach === ((expected[i].panelMode || "attached") === "attached") && item.panel.panelAnchorHorizontalCenter === (expected[i].panelMode === "centered"), "actual Panel uses selected attachment mode");
      check(client.firstDayOfWeek === Number(expected[i].weekStart), "selected week range");
      check(client.use12hourFormat === (expected[i].timeFormat === "12h"), "selected time format");
      var hour = new Date();
      hour.setHours(13, 0, 0, 0);
      check(find(item.panel, child => child.text === client.formatTime(hour)), "actual Panel hour Text uses selected format");
      check(client.hourLineOpacitySetting === expected[i].hourLineOpacity && client.dayLineOpacitySetting === expected[i].dayLineOpacity, "selected grid alpha");
      var line = expected[i].lineColorType === "mOnSurfaceVariant" ? AtmoColor.mOnSurfaceVariant : AtmoColor.mOutline;
      check(client.lineColor.toString() === line.toString(), "selected grid color");
      check(find(item.panel, child => child.height === 1 && child.color !== undefined && child.color.toString() === Qt.alpha(line, expected[i].hourLineOpacity).toString()), "actual grid child uses selected color");
      check(all(item.panel, child => child.height === 1 && child.color !== undefined && Math.abs(child.color.a - expected[i].hourLineOpacity) < 0.005, []).length >= 24, "actual hour grid alpha");
      check(all(item.panel, child => child.width === 1 && child.color !== undefined && Math.abs(child.color.a - expected[i].dayLineOpacity) < 0.005, []).length >= 6, "actual day grid alpha");
    }
    check(main._settingsConsumers.size === 4, "one calendar client per API, not renderer");
    console.log("CALENDAR_CONSUMERS " + JSON.stringify({
                                                         scope: scope,
                                                         mode: mode,
                                                         boundary: name,
                                                         clients: main._settingsConsumers.size
                                                       }));
  }
  function probe(name, next) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_CALENDAR_DISK"), Quickshell.env("PHA_CALENDAR_CASE"), Quickshell.env("PHA_CALENDAR_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
    phase = next;
  }
  function edit() {
    var control = find(popup.settingsPage, item => item.label === api.tr("settings.panelMode") && item.selected !== undefined);
    check(control, "actual panel mode combo");
    control.selected("centered");
    check(popup._pageApi.field("panelMode").value === "centered", "actual combo stages mode");
    for (var key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== "panelMode")
        check(!popup._pageApi.field(key).pendingIntent, "untouched field has no intent: " + key);
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function editPolicy() {
    for (var row of [["settings.weekStart", "0"], ["settings.gridColor", "mOnSurfaceVariant"]]) {
      var combo = find(popup.settingsPage, item => item.label === api.tr(row[0]) && item.selected !== undefined);
      check(combo, "actual policy combo " + row[0]);
      combo.selected(row[1]);
    }
    var toggle = find(popup.settingsPage, item => item.label === api.tr("settings.timeFormat") && item.toggled !== undefined);
    check(toggle, "actual time format toggle");
    toggle.toggled(true);
    check(popup._pageApi.field("timeFormat").value === "12h", "time format intent uses stable source ID");
    for (var field of ["hourLineOpacity", "dayLineOpacity"]) {
      var slider = find(popup.settingsPage, item => item.objectName === "settings-range-" + field);
      check(slider, "actual opacity slider");
      slider.value = field === "hourLineOpacity" ? 0.2 : 0.3;
      slider.moved();
    }
  }
  function event(uid, title, start, end) {
    return {
      uid: uid,
      summary: title,
      start: new Date(start).getTime() / 1000,
      end: new Date(end).getTime() / 1000
    };
  }
  function seedLayout() {
    for (var item of presentations)
      item.panel.mainInstance.currentDate = new Date(2026, 10, 18, 12);
    CalendarService.events = [event("one", "Selected overlap one", "2026-11-18T13:00:00", "2026-11-18T14:00:00"), event("two", "Selected overlap two", "2026-11-18T13:30:00", "2026-11-18T14:30:00"), event("boundary", "Sunday boundary", "2026-11-15T13:00:00", "2026-11-15T14:00:00"), event("day", "Three-day event", "2026-11-17T00:00:00", "2026-11-20T00:00:00"), event(
                                "night", "Split midnight", "2026-11-18T23:00:00", "2026-11-19T01:00:00")];
  }
  function observeLayout() {
    for (var item of presentations) {
      var client = item.panel.mainInstance;
      check(client.eventsModel.count === (client.firstDayOfWeek === 1 ? 4 : 5), "selected range filters common calendar events");
      check(client.allDayEventsWithLayout.length === 1 && client.allDayEventsWithLayout[0].spanDays === 3, "all-day layout preserves exclusive midnight range");
      check(client.allDaySectionHeight > 0 && find(item.panel, child => child.text === "Three-day event"), "actual all-day child renders common event");
      var parts = all(item.panel, child => child.eventData?.title === "Selected overlap one" && child.overlapInfo !== undefined, []);
      check(parts.length === 1 && parts[0].overlapInfo.totalLanes === 2, "actual overlap delegate has two lanes");
      check(Math.abs(parts[0].width - ((client.dayColumnWidth + 1) / 2 - 1)) < 0.001, "actual overlap geometry uses selected model");
      check(find(item.panel, child => child.text === "Selected overlap one"), "actual timed child renders common event");
      check(client.eventsModel.get(client.eventsModel.count - 1).totalParts === 2, "cross-midnight split keeps original layout algorithm");
    }
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
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : mode === "policy" ? "following" : boundary;
      if (!ready(name))
        return;
      if (!oldRed && !availabilityChecked) {
        CalendarService.available = true;
        var at = Date.now();
        CalendarService.events = [event("appeared", "Available calendar event", new Date(at - 60000), new Date(at + 60000))];
        phase = "availability";
        return;
      }
      observe(name);
      if (mode === "cold")
        finish();
      else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else if (mode === "policy")
        open("policy-page");
      else
        open("reset-page");
    } else if (phase === "availability") {
      check(presentations.every(item => item.panel.mainInstance.eventsModel.count === 1), "new clients receive events when common service becomes available");
      availabilityChecked = true;
      phase = "initial";
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "construction has no intent");
      edit();
      observe("initial");
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
      probe("edited", oldRed ? "old-red" : "finish");
    } else if (phase === "old-red") {
      check(presentations[1].panel.panelAnchorHorizontalCenter, "original Panel consumes saved selected mode");
      throw new Error("original calendar defect did not reproduce");
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field("panelMode").reset(), "native staged Reset");
      observe("edited");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      api.pluginSettings.panelMode = "centered";
      phase = "base-saving";
      api.saveSettings(function (result) {
        try {
          check(result.status === "saved", "shared native propagation");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following")) {
      observe("following");
      probe("following", "retire");
    } else if (phase === "policy-page" && popup.opened && popup.settingsPage) {
      editPolicy();
      apply("policy-applied");
    } else if (phase === "policy-applied" && accepted() && ready("policy")) {
      observe("policy");
      probe("policy", "seed-layout");
    } else if (phase === "seed-layout") {
      seedLayout();
      phase = "layout";
    } else if (phase === "layout") {
      observeLayout();
      var otherDate = presentations[0].panel.mainInstance.currentDate.getTime();
      presentations[1].panel.mainInstance.navigateWeek(28);
      check(presentations[0].panel.mainInstance.currentDate.getTime() === otherDate, "selected navigation cannot move shared calendar");
      presentations[1].panel.mainInstance.loadEvents();
      phase = "range-union";
    } else if (phase === "range-union") {
      var now = new Date(), starts = [], ends = [];
      for (var item of presentations) {
        var c = item.panel.mainInstance, first = new Date(c.weekStart), last = new Date(c.weekEnd);
        first.setDate(first.getDate() - 7);
        last.setDate(last.getDate() + 14);
        starts.push(first.getTime());
        ends.push(last.getTime());
      }
      var expected = {
        ahead: Math.max(0, Math.ceil((Math.max(...ends) - now) / 86400000)),
        behind: Math.max(0, Math.ceil((now - Math.min(...starts)) / 86400000))
      };
      check(requestedRanges.length > 0 && JSON.stringify(requestedRanges[requestedRanges.length - 1]) === JSON.stringify(expected), "one provider receives union of active selected ranges");
      check(presentations[1].panel.mainInstance.eventsModel.count === 0 && presentations[0].panel.mainInstance.eventsModel.count > 0, "selected navigation changes only its event projection");
      for (var item of presentations)
        item.panel.mainInstance.goToToday();
      var at = Date.now();
      CalendarService.events = [event("current", "Controlled current calendar event", new Date(at - 60000), new Date(at + 60000))];
      phase = "bar-projection";
    } else if (phase === "bar-projection") {
      for (var item of presentations) {
        var client = item.panel.mainInstance;
        check(client.eventsModel.count === 1, "current common event reaches each selected projection");
        item.bar.updateTooltip();
        var expected = api.tr("bar_widget.now") + ": Controlled current calendar event\n" + client.formatTimeRangeForDisplay(client.eventsModel.get(0));
        check(item.bar.tooltipContent === expected && find(item.bar, child => child.tooltipText === expected), "actual Bar pill tooltip uses selected event format");
      }
      phase = "retire";
    } else if (phase === "retire") {
      beforeRetirementRequests = requestedRanges.length;
      for (var item of presentations)
        item.panel.mainInstance.loadEvents();
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && !selected.settingsContext.current()) {
      check(main._settingsConsumers.size === 0 && presentations.every(item => item.bar.settingsConsumer === null), "retirement releases every calendar projection");
      check(requestedRanges.length === beforeRetirementRequests, "retirement fences queued provider requests");
      phase = "finish";
    } else if (phase === "finish")
      finish();
  }
  function finish() {
    console.log("CALENDAR_NATIVE: PASS " + scope + " " + mode + " " + boundary);
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
