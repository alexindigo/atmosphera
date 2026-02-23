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
                            "timeout": parseInt(entries[i].timeout) || 60,
                            "command": String(entries[i].command || "")
                          });
    }
  }

  function _saveFromModel() {
    _saving = true;
    var arr = [];
    for (var i = 0; i < entriesModel.count; i++) {
      var item = entriesModel.get(i);
      arr.push({
                 "timeout": item.timeout,
                 "command": item.command
               });
    }
    Settings.data.idle.customCommands = JSON.stringify(arr);
    _saving = false;
  }

  Component.onCompleted: _loadToModel()

  Connections {
    target: Settings.data.idle
    function onCustomCommandsChanged() {
      root._loadToModel();
    }
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

    delegate: ColumnLayout {
      id: entryDelegate
      required property int index
      required property int timeout
      required property string command

      spacing: Style.marginM
      Layout.fillWidth: true

      property bool _initialized: false

      Component.onCompleted: {
        commandInput.text = entryDelegate.command;
        _initialized = false;
        timeoutSpinBox.value = entryDelegate.timeout;
        _initialized = true;
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NSpinBox {
          id: timeoutSpinBox
          Layout.fillWidth: true
          label: I18n.tr("panels.idle.custom-entry-timeout")
          from: 1
          to: 86400
          suffix: "s"
          onValueChanged: {
            if (entryDelegate._initialized && !root._saving) {
              entriesModel.setProperty(entryDelegate.index, "timeout", value);
              root._saveFromModel();
            }
          }
        }

        NIconButton {
          icon: "trash"
          tooltipText: I18n.tr("panels.idle.custom-entry-delete")
          Layout.alignment: Qt.AlignBottom
          onClicked: {
            entriesModel.remove(entryDelegate.index, 1);
            root._saveFromModel();
          }
        }
      }

      NTextInput {
        id: commandInput
        Layout.fillWidth: true
        label: I18n.tr("panels.idle.custom-entry-command")
        placeholderText: "notify-send \"Idle\""
        fontFamily: Settings.data.ui.fontFixed
        onTextChanged: {
          if (entryDelegate._initialized && !root._saving) {
            entriesModel.setProperty(entryDelegate.index, "command", text);
            root._saveFromModel();
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
        visible: entryDelegate.index < entriesModel.count - 1
      }
    }
  }

  NButton {
    text: I18n.tr("panels.idle.custom-add")
    icon: "add"
    enabled: Settings.data.idle.enabled
    onClicked: {
      entriesModel.append({
                            "timeout": 60,
                            "command": ""
                          });
      root._saveFromModel();
    }
  }
}
