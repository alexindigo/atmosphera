import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import qs.Widgets

ShellRoot {
  id: root
  property int step: 0
  property var selections: []
  property var commands: []
  property int selectedBefore: 0
  property string savedArguments: "--user-value"

  function check(name, passed, observed) {
    console.log("COMBO_CASE " + JSON.stringify({
                                                 name: name,
                                                 passed: !!passed,
                                                 observed: observed
                                               }));
  }

  function find(item, predicate) {
    if (predicate(item))
      return item;
    var children = item.children || [];
    for (var i = 0; i < children.length; ++i) {
      var found = find(children[i], predicate);
      if (found)
        return found;
    }
    return null;
  }

  ListModel {
    id: first
  }
  ListModel {
    id: second
    ListElement {
      key: "z"
      name: "Other"
      section: "Apps"
    }
  }
  Window {
    visible: true
    width: 600
    height: 500
    NSearchableComboBox {
      id: picker
      width: 500
      stacked: true
      model: first
      customEntry: true
      sectionRole: "section"
      onSelected: key => {
        root.selections = root.selections.concat([key]);
        root.savedArguments = "--default";
      }
      onCustomEntered: text => root.commands = root.commands.concat([text])
    }
  }
  Timer {
    interval: 80
    repeat: true
    running: true
    onTriggered: {
      switch (root.step++) {
      case 0:
        first.append({
                       key: "a",
                       name: "Match A",
                       section: "Apps"
                     });
        first.append({
                       key: "b",
                       name: "Match B",
                       section: "Apps"
                     });
        first.append({
                       key: "c",
                       name: "Match C",
                       section: "Apps"
                     });
        picker.searchText = "Match";
        picker._highlight = 2;
        first.clear();
        break;
      case 1:
        picker.selectHighlighted();
        check("stale-no-match", commands.length === 0 && picker._highlight === -1, {
                commands: commands,
                highlight: picker._highlight
              });
        commands = [];
        picker._highlight = -1;
        picker.navigate(1);
        picker.selectHighlighted();
        check("explicit-run", commands.join() === "Match", commands);
        picker.searchText = "";
        first.append({
                       key: "a",
                       name: "Match A",
                       section: "Apps"
                     });
        first.append({
                       key: "b",
                       name: "Match B",
                       section: "Apps"
                     });
        break;
      case 2:
        picker.customEntry = false;
        picker.selectOnNavigation = true;
        picker._highlight = 1;
        savedArguments = "--user-value";
        selectedBefore = selections.length;
        picker.navigate(1);
        check("clamped-navigation", selections.length === selectedBefore && savedArguments === "--user-value", {
                selections: selections,
                args: savedArguments
              });
        selectedBefore = selections.length;
        picker.navigate(-1);
        check("changed-navigation", selections.length === selectedBefore + 1 && selections[selections.length - 1] === "a", selections);
        var combo = find(picker, function (item) {
          return item.popup !== undefined && item.wheelEnabled !== undefined;
        });
        check("wheel-default", combo && !combo.wheelEnabled, combo ? combo.wheelEnabled : null);
        picker.customEntry = true;
        picker.selectOnNavigation = false;
        picker.searchText = "Match";
        picker._highlight = 1;
        first.move(1, 0, 1);
        break;
      case 3:
        check("move-identity", picker.activeModel.get(0).key === "b" && picker._highlight === 0, {
                first: picker.activeModel.get(0).key,
                highlight: picker._highlight
              });
        picker.model = second;
        break;
      case 4:
        selectedBefore = selections.length;
        var commandBefore = commands.length;
        picker.selectHighlighted();
        check("replacement-invalidates", selections.length === selectedBefore && commands.length === commandBefore && picker._highlight === -1, {
                selections: selections,
                commands: commands,
                highlight: picker._highlight
              });
        picker.model = first;
        picker.searchText = "Match";
        break;
      case 5:
        picker._highlight = 0;
        selectedBefore = selections.length;
        first.clear();
        var commandBefore = commands.length;
        picker.selectHighlighted();
        check("pending-rejects", selections.length === selectedBefore && commands.length === commandBefore, {
                selections: selections,
                commands: commands
              });
        picker["__proofFilters"] = 0;
        for (var i = 0; i < 100; ++i)
          first.append({
                         key: "k" + i,
                         name: "Match " + i,
                         section: "Apps"
                       });
        break;
      case 6:
        check("bulk-refresh", picker.activeModel.count === 100 && picker["__proofFilters"] === 1, {
                count: picker.activeModel.count,
                refilters: picker["__proofFilters"]
              });
        picker.searchText = "echo $$ $& $` $'";
        var combo = find(picker, function (item) {
          return item.popup !== undefined && item.wheelEnabled !== undefined;
        });
        var run = find(combo.popup.contentItem, function (item) {
          return item.text !== undefined && String(item.text).indexOf("Run command:") === 0;
        });
        check("literal-preview", run && run.text === "Run command: " + picker.searchText, run ? run.text : null);
        picker.searchText = "Match";
        picker._highlight = picker._choiceCount;
        first.remove(0);
        break;
      case 7:
        check("footer-identity", picker._highlight === picker._choiceCount, {
                highlight: picker._highlight,
                count: picker._choiceCount
              });
        picker.customEntry = false;
        picker.searchText = "";
        first.clear();
        break;
      case 8:
        selectedBefore = selections.length;
        picker.navigate(1);
        check("empty-navigation", picker._highlight === -1 && selections.length === selectedBefore, {
                highlight: picker._highlight,
                selections: selections
              });
        first.append({
                       key: "a",
                       name: "Match A",
                       section: "Apps"
                     });
        picker.searchText = "Match";
        picker._highlight = 0;
        break;
      case 9:
        first.set(0, {
                    key: "replaced",
                    name: "Match New",
                    section: "Apps"
                  });
        break;
      case 10:
        selectedBefore = selections.length;
        picker.selectHighlighted();
        check("same-index-replacement", picker._highlight === -1 && selections.length === selectedBefore, {
                highlight: picker._highlight,
                selections: selections
              });
        picker._highlight = 0;
        first.setProperty(0, "name", "Match Renamed");
        break;
      default:
        check("data-change-identity", picker._highlight === 0 && picker.activeModel.get(0).name === "Match Renamed", {
                highlight: picker._highlight,
                row: picker.activeModel.get(0)
              });
        console.log("COMBO_DONE");
        stop();
        Qt.quit();
      }
    }
  }
}
