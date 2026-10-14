// Unit fixture: plugin contract table and root-declaration scanner.
// Run in a private guest copy by plugin-contract-regression.py, which sets
// PLUGIN_CONTRACT_SAMPLE to plugin-contract-sample.qml next to this file.
import QtQuick
import Quickshell
import Quickshell.Io
import "../../../Services/Plugins/PluginContract.js" as PluginContract
import "../../../Helpers/QmlRootDeclarations.js" as RootDeclarations

Item {
  id: probe

  function emit(name, output) {
    console.log("PLUGIN_CONTRACT|" + JSON.stringify({ "case": name, "output": output }));
  }

  function rootCases() {
    return {
      "root:simple": `pragma ComponentBehavior: Bound
import QtQuick
Item {
  property int a: 1
  property string b
}`,
      "root:modifiers": `import QtQuick
Item {
  default property list<Item> kids: []
  required property var req
  readonly property int ro: 2
  required readonly property var combo: 3
  property var plain
  required sized
}`,
      "root:typed": `import QtQuick
import Quickshell.Io
Item {
  property list<var> items: []
  property Quickshell.Io.Process proc: null
  property ShellScreen screen
  property list<list<int>> grid: []
}`,
      "root:alias": `import QtQuick
Item {
  property alias label: text.text
  property alias inner: text
  Text { id: text }
}`,
      "root:nested-child": `import QtQuick
Item {
  property var outer: 1
  Item {
    property var screen
    Item { property var deeper }
  }
}`,
      "root:strings-comments": `import QtQuick
Item {
  // property var commentLine
  /* property var commentBlock
     property var commentBlock2 */
  property string s1: "property var inDouble"
  property string s2: 'property var inSingle'
  property string s3: \x60property var inTemplate\x60
  property string s4: "escaped \\" quote property var inEscape"
  property string s5: "}"
  property int n1: 1 // property var trailing
}`,
      "root:function-body": `import QtQuick
Item {
  property var a: 1
  function f(x) {
    const o = { property: 1 }
    if (x) {
      property var inBody: 3
      return "property var inString"
    }
    return 0
  }
  property var b
}`,
      "root:multiline-value": `import QtQuick
Item {
  property var cfg: {
    "property": 1,
    "inner": { property var deep: 2 }
  }
  property var after: 1
}`,
      "root:regex-literal": `import QtQuick
Item {
  property var rx: /[{}"]/
  property var after2: /\\/{/.source
  property var tail: 1
}`,
      "root:dotted-root": `import QtQuick
QtQuick.Item {
  property var screen
}`,
      "root:empty": `import QtQuick
Item {
  Item { property var nested }
}`
    };
  }

  function runAll(sampleText) {
    emit("entryPoints", PluginContract.entryPoints());
    const entryPoints = PluginContract.entryPoints();
    for (let i = 0; i < entryPoints.length; i++)
      emit("contract:" + entryPoints[i], PluginContract.contextNames(entryPoints[i]));
    emit("contract:unknown", PluginContract.contextNames("nope"));
    emit("contract:constructor", PluginContract.contextNames("constructor"));

    const cases = rootCases();
    const names = Object.keys(cases);
    for (let i = 0; i < names.length; i++)
      emit(names[i], RootDeclarations.rootPropertyNames(cases[names[i]]));
    emit("root:real-file", RootDeclarations.rootPropertyNames(sampleText));
    console.log("PLUGIN_CONTRACT_DONE");
    finish.start();
  }

  FileView {
    id: sample
    path: Quickshell.env("PLUGIN_CONTRACT_SAMPLE") || ""
    onLoaded: probe.runAll(sample.text())
    onLoadFailed: function (error) {
      console.log("PLUGIN_CONTRACT_ERROR|sample load failed: " + error);
      Qt.exit(3);
    }
  }

  Timer {
    id: finish
    interval: 100
    onTriggered: Qt.exit(0)
  }

  Timer {
    interval: 15000
    running: true
    onTriggered: Qt.exit(2)
  }
}
