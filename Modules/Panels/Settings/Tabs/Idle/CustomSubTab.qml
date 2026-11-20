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
  // View-session memory only; the stored command shape stays unchanged.
  property var _rememberedTimeouts: []

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
      var timeout = parseInt(entries[i].timeout);
      if (isNaN(timeout) || timeout < 0)
        timeout = 60;
      if (timeout > 0)
        _rememberedTimeouts[i] = timeout;
      entriesModel.append({
                            "name": String(entries[i].name || ""),
                            "timeout": timeout,
                            "rememberedTimeout": _rememberedTimeouts[i] || 60,
                            "entryJson": JSON.stringify(entries[i]),
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
      arr.push(Object.assign(JSON.parse(item.entryJson), {
                               "name": item.name,
                               "timeout": item.timeout,
                               "command": item.command,
                               "resumeCommand": item.resumeCommand
                             }));
    }
    Settings.data.idle.customCommands = JSON.stringify(arr);
    _saving = false;
  }

  function _removeEntry(index) {
    _rememberedTimeouts.splice(index, 1);
    entriesModel.remove(index, 1);
    _saveFromModel();
  }

  function _setEntryEnabled(index, checked) {
    var item = entriesModel.get(index);
    if (item.timeout > 0)
      _rememberedTimeouts[index] = item.timeout;
    entriesModel.setProperty(index, "rememberedTimeout", _rememberedTimeouts[index] || 60);
    entriesModel.setProperty(index, "timeout", checked ? (_rememberedTimeouts[index] || 60) : 0);
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
    onSaved: {
      var index = editPopup.editIndex < 0 ? entriesModel.count - 1 : editPopup.editIndex;
      root._rememberedTimeouts[index] = editPopup.rememberedTimeoutValue;
      entriesModel.setProperty(index, "rememberedTimeout", editPopup.rememberedTimeoutValue);
    }
  }

  function createEntryEditor(index) {
    var leaf = Settings.createEditor("idle.customCommands");
    if (!leaf)
      return null;
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
    var initial = index === -1 ? {
                                   name: "",
                                   timeout: 60,
                                   command: "",
                                   resumeCommand: ""
                                 } : entries[index];
    return {
      rememberedTimeout: index >= 0 ? (_rememberedTimeouts[index] || 60) : 60,
      initialValue: {
        name: initial.name || "",
        timeout: initial.timeout === undefined ? 60 : initial.timeout,
        command: initial.command || "",
        resumeCommand: initial.resumeCommand || ""
      },
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
      discard: function () {
        return leaf.discard();
      }
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
      required property int rememberedTimeout
      required property string command
      required property string resumeCommand

      spacing: Style.marginM
      Layout.fillWidth: true

      NLabel {
        Layout.fillWidth: true
        enabled: entryDelegate.timeout > 0
        label: entryDelegate.name || I18n.tr("panels.idle.custom-entry-unnamed")
        description: I18n.trp("common.second", entryDelegate.timeout > 0 ? entryDelegate.timeout : entryDelegate.rememberedTimeout)
        labelColor: enabled && (entryDelegate.command || entryDelegate.resumeCommand) ? AtmoColor.mPrimary : AtmoColor.mOnSurface
      }

      NToggle {
        Layout.fillWidth: false
        Accessible.name: entryDelegate.name || I18n.tr("panels.idle.custom-entry-unnamed")
        checked: entryDelegate.timeout > 0
        onToggled: checked => root._setEntryEnabled(entryDelegate.index, checked)
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
