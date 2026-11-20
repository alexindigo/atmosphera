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

  function _entryIdentity(entry) {
    var identity = Object.assign({}, entry);
    delete identity.timeout;
    delete identity.name;
    delete identity.command;
    delete identity.resumeCommand;
    return JSON.stringify([String(entry.name || ""), String(entry.command || ""), String(entry.resumeCommand || ""), identity]);
  }

  function _loadToModel() {
    if (_saving)
      return;
    // The model owns view-session memory. Reconcile by command identity, not
    // row position; ambiguous identities must never lend memory to a new row.
    var previous = {};
    for (var row = 0; row < entriesModel.count; row++) {
      var item = entriesModel.get(row);
      var key = _entryIdentity(JSON.parse(item.entryJson));
      if (previous[key] === undefined)
        previous[key] = item.rememberedTimeout;
      else
        previous[key] = 0;
    }
    var entries = [];
    try {
      entries = JSON.parse(Settings.data.idle.customCommands);
    } catch (e) {
      Logger.w("CustomSubTab", "Failed to parse customCommands:", e);
    }
    var counts = {};
    for (var entry of entries) {
      var identity = _entryIdentity(entry);
      counts[identity] = (counts[identity] || 0) + 1;
    }
    var unchanged = entries.length === entriesModel.count;
    var rememberedRows = [];
    for (var index = 0; index < entriesModel.count; index++) {
      var old = entriesModel.get(index);
      rememberedRows.push(old.rememberedTimeout);
      if (unchanged && (_entryIdentity(entries[index]) !== _entryIdentity(JSON.parse(old.entryJson)) || entries[index].timeout !== old.timeout))
        unchanged = false;
    }
    entriesModel.clear();
    for (var i = 0; i < entries.length; i++) {
      var timeout = parseInt(entries[i].timeout);
      if (isNaN(timeout) || timeout < 0)
        timeout = 60;
      var entryKey = _entryIdentity(entries[i]);
      var remembered = timeout > 0 ? timeout : (unchanged ? rememberedRows[i] : (counts[entryKey] === 1 ? previous[entryKey] : 0));
      entriesModel.append({
                            "name": String(entries[i].name || ""),
                            "timeout": timeout,
                            "rememberedTimeout": remembered || 60,
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
    entriesModel.remove(index, 1);
    _saveFromModel();
  }

  function _setEntryEnabled(index, checked) {
    var item = entriesModel.get(index);
    var remembered = item.timeout > 0 ? item.timeout : item.rememberedTimeout;
    entriesModel.setProperty(index, "rememberedTimeout", remembered);
    entriesModel.setProperty(index, "timeout", checked ? remembered : 0);
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
      rememberedTimeout: index >= 0 ? entriesModel.get(index).rememberedTimeout : 60,
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
