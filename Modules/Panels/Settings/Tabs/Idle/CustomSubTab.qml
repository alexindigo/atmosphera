import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Power
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true
  enabled: Settings.data.idle.enabled

  property bool _saving: false

  ListModel {
    id: entriesModel
  }

  function _loadToModel() {
    if (_saving)
      return;
    entriesModel.clear();
    var entries = [];
    try {
      entries = JSON.parse(Settings.data.idle.customCommands);
    } catch (e) {
      Logger.w("CustomSubTab", "Failed to parse customCommands:", e);
    }
    for (var i = 0; i < entries.length; i++) {
      entriesModel.append({
                            "name": String(entries[i].name || ""),
                            "timeout": parseInt(entries[i].timeout) || 60,
                            "command": String(entries[i].command || ""),
                            "resumeCommand": String(entries[i].resumeCommand || "")
                          });
    }
  }

  function _saveFromModel() {
    _saving = true;
    var arr = [];
    for (var i = 0; i < entriesModel.count; i++) {
      var item = entriesModel.get(i);
      arr.push({
                 "name": item.name,
                 "timeout": item.timeout,
                 "command": item.command,
                 "resumeCommand": item.resumeCommand
               });
    }
    Settings.data.idle.customCommands = JSON.stringify(arr);
    _saving = false;
  }

  function _removeEntry(index) {
    entriesModel.remove(index, 1);
    _saveFromModel();
  }

  Component.onCompleted: Qt.callLater(_loadToModel)

  Connections {
    target: Settings.data.idle
    function onCustomCommandsChanged() {
      root._loadToModel();
    }
  }

  // Shared Edit Popup
  IdleCommandEditPopup {
    id: editPopup
    parent: Overlay.overlay
  }

  function createEntryEditor(index) {
    var leaf = Settings.createEditor("idle.customCommands");
    var entries;
    try {
      entries = JSON.parse(leaf.initialValue);
    } catch (error) {
      leaf.discard();
      return null;
    }
    if (!Array.isArray(entries) || index < -1 || index >= entries.length) {
      leaf.discard();
      return null;
    }
    var initial = index === -1 ? {name: "", timeout: 60, command: "", resumeCommand: ""} : entries[index];
    return {
      initialValue: {name: initial.name || "", timeout: initial.timeout === undefined ? 60 : initial.timeout, command: initial.command || "", resumeCommand: initial.resumeCommand || ""},
      apply: function (value, callback) {
        // Start from the captured owning leaf, never the view's possibly newer
        // index/model. The leaf adapter rejects any intervening list change.
        var changed = JSON.parse(leaf.initialValue);
        if (index === -1)
          changed.push(value);
        else
          changed[index] = Object.assign({}, changed[index], value);
        leaf.apply(JSON.stringify(changed), callback);
      },
      discard: function () { return leaf.discard(); }
    };
  }

  function openEdit(index) {
    if (editPopup.visible || editPopup.busy)
      return;
    var editor = createEntryEditor(index);
    if (!editor) {
      Logger.e("CustomSubTab", "Cannot edit invalid or stale custom command");
      return;
    }
    editPopup.showName = true;
    editPopup.openEditor(editor, editor.initialValue, index);
  }

  NLabel {
    label: I18n.tr("panels.idle.custom-label")
    description: I18n.tr("panels.idle.custom-description")
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
    Layout.bottomMargin: Style.marginS
  }

  Repeater {
    model: entriesModel

    delegate: RowLayout {
      id: entryDelegate
      required property int index
      required property string name
      required property int timeout
      required property string command
      required property string resumeCommand

      spacing: Style.marginM
      Layout.fillWidth: true

      NLabel {
        Layout.fillWidth: true
        label: entryDelegate.name || I18n.tr("panels.idle.custom-entry-unnamed")
        description: I18n.trp("common.second", entryDelegate.timeout)
        labelColor: (entryDelegate.command || entryDelegate.resumeCommand) ? AtmoColor.mPrimary : AtmoColor.mOnSurface
      }

      AtmoIconButton {
        icon: Icon.settings
        tooltipText: I18n.tr("common.edit")
        onClicked: root.openEdit(entryDelegate.index)
      }

      AtmoIconButton {
        icon: Icon.trash
        tooltipText: I18n.tr("panels.idle.custom-entry-delete")
        onClicked: root._removeEntry(entryDelegate.index)
      }
    }
  }

  NButton {
    text: I18n.tr("panels.idle.custom-add")
    icon: Icon.add
    enabled: Settings.data.idle.enabled
    onClicked: {
      root.openEdit(-1);
    }
  }
}
