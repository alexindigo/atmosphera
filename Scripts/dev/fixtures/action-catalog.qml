import QtQuick
import Quickshell
import Quickshell.Io
import "../../../Services/Actions/ActionCommand.js" as ActionCommand

Item {
  id: root
  property var schema: null
  property var catalog: null

  function emitCase(name, output) {
    console.log("ACTION_CASE " + JSON.stringify({
                                                  name: name,
                                                  output: output
                                                }));
  }

  function run() {
    if (!schema || !catalog)
      return;
    schema.cases.forEach(function (test) {
      var action = Object.prototype.hasOwnProperty.call(test, "action") ? test.action : Object.assign({}, root.schema.base, test.patch);
      emitCase("schema:" + test.name, ActionCommand.validate(action, test.origin).valid);
    });
    var tab = catalog.actions.find(function (action) {
      return action.id === "settings-tab";
    });
    var timed = catalog.actions.find(function (action) {
      return action.id === "keep-awake-for";
    });
    var text = {
      id: "text",
      label: "Message",
      description: "Show a message.",
      icon: "terminal",
      command: "atmosphera ipc plugin:example show",
      arguments: [
        {
          name: "message",
          label: "Message",
          type: "text",
          default: "hello"
        }
      ]
    };
    function roundtrip(name, action, values) {
      var command = ActionCommand.compose(action, values);
      var match = ActionCommand.recognize(command, [action]);
      emitCase(name, {
                 command: command,
                 values: match ? match.values : null,
                 label: ActionCommand.displayLabel(action, values)
               });
    }
    roundtrip("tab", tab, {
                tab: "plugins"
              });
    roundtrip("number", timed, {
                seconds: 1200
              });
    roundtrip("space", text, {
                message: "hello world"
              });
    roundtrip("apostrophe", text, {
                message: "it's here"
              });
    ["atmosphera ipc idleInhibitor enableFor 0", "atmosphera ipc idleInhibitor enableFor 9x", "atmosphera ipc settings openTab \"plugins\"", "atmosphera ipc settings openTab plugins ", "atmosphera ipc settings openTab unknown"].forEach(function (command, index) {
      emitCase("reject:" + index, ActionCommand.recognize(command, [tab, timed]) === null);
    });
    emitCase("availability", [ActionCommand.available({
                                                        compositor: "niri"
                                                      }, {
                                                        compositor: "niri",
                                                        loadedPluginIds: []
                                                      }), ActionCommand.available({
                                                                                    compositor: "niri"
                                                                                  }, {
                                                                                    compositor: "sway",
                                                                                    loadedPluginIds: []
                                                                                  }), ActionCommand.available({
                                                                                                                requiresPlugin: "example"
                                                                                                              }, {
                                                                                                                compositor: "niri",
                                                                                                                loadedPluginIds: ["example"]
                                                                                                              }), ActionCommand.available({
                                                                                                                                            requiresPlugin: "example"
                                                                                                                                          }, {
                                                                                                                                            compositor: "niri",
                                                                                                                                            loadedPluginIds: []
                                                                                                                                          })]);
    console.log("ACTION_DONE");
    Qt.quit();
  }

  FileView {
    path: Quickshell.env("ACTION_SCHEMA")
    onLoaded: {
      root.schema = JSON.parse(text());
      root.run();
    }
  }
  FileView {
    path: Quickshell.env("ACTION_CORE")
    onLoaded: {
      root.catalog = JSON.parse(text());
      root.run();
    }
  }
  Timer {
    interval: 15000
    running: true
    onTriggered: Qt.exit(2)
  }
}
