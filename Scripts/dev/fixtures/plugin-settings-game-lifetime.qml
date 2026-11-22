import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string casePath: Quickshell.env("PHA_GAME_CASE")
  readonly property string mode: Quickshell.env("PHA_GAME_MODE")
  property bool started: false
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var api: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var main: null
  property var panel: null
  property var panel2: null
  property var game: null
  property var pet: null
  property var food: null
  property var ball: null
  property var bed: null
  property var soap: null
  property var debug: null
  property var decayTimer: null
  property var retirementTimer: null
  property var retiredContext: null
  property var retiredGame: null
  property var retainedFeed: null
  property string afterDisk: ""
  property string diskBoundary: ""
  property int integerProbe: 0
  property int sleepEnergy: 0
  property var expected: ({})
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/tamagotchi/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/tamagotchi/i18n/en.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete lifetime documents: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  Process {
    id: pointer
    property bool ready: false
    property bool busy: false
    property int pending: 0
    property bool joined: false
    command: [Quickshell.env("PHA_POINTER")]
    stdinEnabled: true
    onExited: code => {
      if (code !== 0)
        root.fail("virtual pointer exit: " + code);
      else
        joined = true;
    }
    function send(lines) {
      busy = true;
      pending = lines.length;
      for (var line of lines)
        write(line + "\n");
    }
    stdout: SplitParser {
      onRead: line => {
        if (line === "READY")
          pointer.ready = true;
        else if (line === "OK" && --pointer.pending === 0)
          pointer.busy = false;
        else if (line !== "OK")
          root.fail("pointer reply: " + line);
      }
    }
  }
  PanelWindow {
    id: host
    visible: true
    screen: Quickshell.screens.find(item => item.name === Quickshell.env("PHA_GAME_SCREEN"))
    WlrLayershell.layer: WlrLayer.Overlay
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    Item {
      id: content
      anchors.fill: parent
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("GAME_LIFE_ASSERT: " + phase + ": " + message + " observed=" + (game ? JSON.stringify(snapshot()) : "no game"));
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function all(object, predicate, result = []) {
    if (object && predicate(object) && !result.includes(object))
      result.push(object);
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list)
        if (child && !result.includes(child))
          all(child, predicate, result);
    }
    return result;
  }
  function find(object, predicate) {
    return all(object, predicate)[0];
  }
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("tamagotchi", entry, component, content, context, {});
    check(item, "actual " + entry + " constructs");
    return item;
  }
  function snapshot() {
    return {
      hunger: game.hunger,
      happiness: game.happiness,
      cleanliness: game.cleanliness,
      energy: game.energy
    };
  }
  function stats(value, label) {
    check(JSON.stringify(snapshot()) === JSON.stringify(value), label + " selected game stats");
  }
  function probe(name, next) {
    diskBoundary = name;
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_GAME_DISK"), casePath, Quickshell.env("PHA_GAME_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    var descriptor = JSON.parse(manifest.text()), dict = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      tamagotchi: descriptor
    };
    Service._openSettingsOwner("tamagotchi", function (owner) {
      try {
        check(owner, "native game owner");
        api = Service.createPluginAPI("tamagotchi", descriptor, owner, dict, dict, {});
        Service.loadedPlugins = {
          tamagotchi: {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        selected = PluginInstances.apiFor("tamagotchi", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        sibling = PluginInstances.apiFor("tamagotchi", {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        inherited = PluginInstances.apiFor("tamagotchi", {
                                             kind: "bar",
                                             list: "global",
                                             section: "left",
                                             index: 2
                                           });
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function timers(model) {
    return all(model, item => item.interval === 30000 && item.repeat !== undefined);
  }
  function stopTimers() {
    for (var model of main._games.values())
      for (var timer of timers(model))
        timer.stop();
  }
  function quietBall(object) {
    var b = find(object, item => item.gravity !== undefined && item.forceMultiplier !== undefined);
    check(b, "actual Ball");
    b.gravity = 0;
    b.vx = 0;
    b.vy = 0;
    return b;
  }
  function setup() {
    panel = create("panel", selected);
    panel2 = create("panel", selected);
    panel2.visible = false;
    quietBall(panel2);
    ball = quietBall(panel);
    game = main.gameFor(selected);
    check(panel.game === game && panel2.game === game && game !== main.sharedGame && game !== main.gameFor(sibling) && game !== main.gameFor(inherited), "same-context sharing and independent games");
    check(main.sharedGame && timers(main.sharedGame).length === 1 && timers(main.sharedGame)[0].running, "plugin background timer exists without a view");
    stopTimers();
    decayTimer = timers(game)[0];
    check(decayTimer && decayTimer.interval === 30000 && !decayTimer.running, "actual thirty-second game timer");
    pet = find(panel, item => typeof item.burstFood === "function");
    food = find(panel, item => item.wasDropped !== undefined && item.game !== undefined);
    soap = find(panel, item => item.wasDropped !== undefined && item.game === undefined);
    bed = find(panel, item => item.pressed !== undefined && item.game !== undefined);
    debug = find(panel, item => item.spacing !== undefined && item.game !== undefined && item.visible !== undefined && item.children && item.children.length === 4);
    check(pet && food && soap && bed && debug, "all actual action children");
    check(find(pet, item => item.volume !== undefined && item.source !== undefined).volume === 0.25 && debug.visible, "selected sound and debug policy");
    if (mode === "cold") {
      check(game.energy >= 48 && game.energy <= 52, "cold original sleep random domain");
      stats({
              hunger: 34,
              happiness: 31,
              cleanliness: 35,
              energy: game.energy
            }, "cold operational read");
      phase = "done";
      console.log("GAME_LIFETIME: COLD_PASS");
      Qt.exit(0);
      return;
    }
    stats({
            hunger: 40,
            happiness: 50,
            cleanliness: 30,
            energy: 50
          }, "initial");
    integerProbe = 32.5;
    check(integerProbe === 32, "original QML int truncation");
    for (var i = 0; i < 50; ++i) {
      var random = game._randFactor();
      check(random >= 0.5 && random < 1.7, "original random factor domain");
    }
    pointer.running = true;
    probe("initial", "food-start");
  }
  function moveTo(item, dy = 0) {
    var pos = item.mapToItem(content, item.width / 2, item.height / 2 + dy);
    var layout = JSON.parse(Quickshell.env("PHA_GAME_LAYOUT"));
    return "move " + Math.round(layout.x + pos.x) + " " + Math.round(layout.y + pos.y) + " " + layout.width + " " + layout.height;
  }
  function save(next) {
    selected.saveSettings(result => {
      try {
        check(result.status === "saved" || result.status === "nothing_to_save", "native operational settlement");
        phase = next;
      } catch (error) {
        fail(error);
      }
    });
    phase = "settling";
  }
  function drive() {
    check(Date.now() - since < (phase === "timer-wait" ? 34000 : 18000), "finite game lifetime phase");
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady)
      setup();
    else if (phase === "food-start" && pointer.ready && !pointer.busy) {
      pointer.send(["button 272 0", moveTo(food)]);
      phase = "food-pointed";
    } else if (phase === "food-pointed" && !pointer.busy && Date.now() - since > 150) {
      pointer.send(["button 272 1"]);
      phase = "food-pressed";
    } else if (phase === "food-pressed" && !pointer.busy && game.eating) {
      pointer.send([moveTo(food, 20)]);
      phase = "food-threshold";
    } else if (phase === "food-threshold" && !pointer.busy) {
      pointer.send([moveTo(pet)]);
      phase = "food-drag";
    } else if (phase === "food-drag" && find(pet, item => item.containsDrag !== undefined && item.keys && item.keys[0] === "food").containsDrag) {
      check(game.eating, "Food drag selects eating animation");
      check(find(pet, item => item.currentState !== undefined).sourceClipRect.x === 40, "actual eating sprite clip");
      pointer.send(["button 272 0"]);
      phase = "food-released";
    } else if (phase === "food-released" && !pointer.busy) {
      check(game.hunger === 50 && !game.eating, "real Food drop feeds selected game");
      check(all(pet, item => typeof item.burst === "function" && item.visible).length === 5, "real Food drop starts five particle animations");
      phase = "food-animation";
    } else if (phase === "food-animation" && Date.now() - since > 750) {
      check(food.scale === 1 && food.opacity === 1 && all(pet, item => typeof item.burst === "function" && item.visible).length === 0, "drop and particle animations settle");
      save("fed-probe");
    } else if (phase === "fed-probe") {
      probe("fed", "soap-start");
    } else if (phase === "soap-start" && !pointer.busy) {
      pointer.send([moveTo(soap), "button 272 1"]);
      phase = "soap-pressed";
    } else if (phase === "soap-pressed" && !pointer.busy && soap._dragging) {
      pointer.send([moveTo(soap, 20)]);
      phase = "soap-threshold";
    } else if (phase === "soap-threshold" && !pointer.busy) {
      pointer.send([moveTo(pet)]);
      phase = "soap-drag";
    } else if (phase === "soap-drag" && game.cleanliness > 30) {
      pointer.send([moveTo(bed), "button 272 0"]);
      check(all(pet, item => typeof item.burst === "function" && item.visible).length === 5, "soap timer starts clean particles");
      phase = "soap-stop";
    } else if (phase === "soap-stop" && Date.now() - since > 200) {
      check(game.cleanliness === 32, "original int clean quantization");
      save("cleaned-probe");
    } else if (phase === "cleaned-probe") {
      probe("cleaned", "ball-start");
    } else if (phase === "ball-start") {
      ball.vx = 20;
      phase = "ball-play";
    } else if (phase === "ball-play" && !ball.canTriggerPlay) {
      ball.vx = 0;
      ball.vy = 0;
      stats({
              hunger: 50,
              happiness: 68,
              cleanliness: 32,
              energy: 47
            }, "Ball physics action");
      save("played-probe");
    } else if (phase === "played-probe") {
      probe("played", "debug-actions");
    } else if (phase === "debug-actions") {
      var actions = Array.from(debug.children);
      check(actions.length === 4, "four Debug actions");
      for (var action of actions)
        action.action();
      stats({
              hunger: 40,
              happiness: 58,
              cleanliness: 22,
              energy: 37
            }, "Debug inputs");
      // Preserve the original unsaved direct happiness/energy debug changes.
      save("debugged-probe");
    } else if (phase === "debugged-probe") {
      probe("debugged", "sleep-start");
    } else if (phase === "sleep-start") {
      find(bed, item => item.released !== undefined).released(null);
      check(game.petState === "sleeping", "actual Bed action sleeps selected game");
      check(find(pet, item => item.currentState !== undefined).currentState === "sleeping", "actual sleeping animation");
      game.decay();
      sleepEnergy = game.energy;
      check(sleepEnergy >= 38 && sleepEnergy <= 42, "original sleeping energy random domain");
      stats({
              hunger: 39,
              happiness: 57,
              cleanliness: 21,
              energy: sleepEnergy
            }, "original sleeping decay quantization");
      save("sleep-probe");
    } else if (phase === "sleep-probe") {
      probe("sleep-decay", "wake-decay");
    } else if (phase === "wake-decay") {
      find(bed, item => item.released !== undefined).released(null);
      check(!game._sleeping, "Bed wakes same game");
      game.decay();
      stats({
              hunger: 38,
              happiness: 56,
              cleanliness: 20,
              energy: sleepEnergy - 1
            }, "original awake decay quantization");
      game.clean(-20);
      check(game.isDirty, "selected dirty state");
      check(find(pet, item => item.currentState !== undefined).sourceClipRect.x === 80, "actual dirty sprite clip");
      game.happiness = 32;
      game.energy = 47;
      game.hunger = 35;
      game.cleanliness = 36;
      game.save();
      game.sleep();
      decayTimer.restart();
      phase = "timer-wait";
    } else if (phase === "timer-wait" && game.energy !== 47) {
      check(game.energy >= 48 && game.energy <= 52, "timer original sleep energy random domain");
      decayTimer.stop();
      stats({
              hunger: 34,
              happiness: 31,
              cleanliness: 35,
              energy: game.energy
            }, "actual thirty-second timer");
      console.log("GAME_TIMER_ELAPSED " + (Date.now() - since));
      save("timer-probe");
    } else if (phase === "timer-probe") {
      probe("timer", "retire-start");
    } else if (phase === "retire-start") {
      retiredContext = selected.settingsContext;
      retiredGame = game;
      retainedFeed = function () {
        food.game?.feed(10);
      };
      retirementTimer = find(game, item => item.interval === 100 && item.repeat !== undefined);
      check(retirementTimer, "actual retirement observer");
      retirementTimer.stop();
      selected.destroy();
      phase = "retire-queued";
    } else if (phase === "retire-queued") {
      retainedFeed();
      check(game.hunger === 34 && !game.current, "queued retired action refuses");
      retirementTimer.restart();
      phase = "retired";
    } else if (phase === "retired" && Date.now() - since > 200) {
      check(!main._games.has(retiredContext) && retiredGame === null && panel.game === null, "native retirement destroys exact game and timer");
      retainedFeed();
      find(bed, item => item.released !== undefined).released(null);
      check(main.gameFor(sibling).current && main.sharedGame.current, "retirement preserves other games");
      probe("retired", "main-destroy");
    } else if (phase === "main-destroy") {
      retiredGame = main.gameFor(sibling);
      main.destroy();
      phase = "main-destroyed";
    } else if (phase === "main-destroyed" && Date.now() - since > 200) {
      check(main === null && retiredGame === null, "actual Main destruction owns game children");
      pointer.stdinEnabled = false;
      phase = "pointer-join";
    } else if (phase === "pointer-join" && pointer.joined) {
      phase = "done";
      console.log("GAME_LIFETIME: PASS");
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 20
    repeat: true
    running: root.phase !== "done"
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
