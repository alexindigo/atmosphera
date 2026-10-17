import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Keyboard
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  width: parent.width

  NLabel {
    label: I18n.tr("panels.general.shortcuts-title")
    description: I18n.tr("panels.general.shortcuts-description")
    Layout.fillWidth: true
  }

  Repeater {
    model: [
      {
        "value": "none",
        "label": I18n.tr("setup.bindings.none-label"),
        "description": I18n.tr("setup.bindings.none-description")
      },
      {
        "value": "macos",
        "label": I18n.tr("setup.bindings.macos-label"),
        "description": I18n.tr("setup.bindings.macos-description")
      }
    ]
    delegate: Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 72
      radius: Style.radiusL
      color: BindingsService.requestedEnvironment === modelData.value ? (AtmoColor.mPrimaryContainer || AtmoColor.mSurfaceVariant) : AtmoColor.mSurfaceVariant
      border.color: BindingsService.requestedEnvironment === modelData.value ? AtmoColor.mPrimary : AtmoColor.mOutline
      border.width: BindingsService.requestedEnvironment === modelData.value ? 2 : 1

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          BindingsService.requestEnvironment(modelData.value);
        }
      }

      RowLayout {
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        Rectangle {
          width: 20
          height: 20
          radius: width / 2
          color: "transparent"
          border.color: BindingsService.requestedEnvironment === modelData.value ? AtmoColor.mPrimary : AtmoColor.mOutline
          border.width: 2

          Rectangle {
            anchors.centerIn: parent
            width: 10
            height: 10
            radius: width / 2
            color: AtmoColor.mPrimary
            visible: BindingsService.requestedEnvironment === modelData.value
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS

          NText {
            text: modelData.label
            pointSize: Style.fontSizeM
            font.weight: Style.fontWeightBold
            color: AtmoColor.mPrimary
          }

          NText {
            text: modelData.description
            pointSize: Style.fontSizeS
            color: AtmoColor.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }
      }
    }
  }

  NBindingsQueueStatus {
    Layout.fillWidth: true
    queueStatus: BindingsService.status
    retry: function () {
      BindingsService.retryHead();
    }
  }

  // ——— Input method switching ———

  property string _importStatus: ""

  // list<var> values are not JS arrays (Array.isArray is false): copy them by index and length.
  function _copyList(list) {
    var out = [];
    if (!list || typeof list.length !== "number")
      return out;
    for (var i = 0; i < list.length; i++)
      out.push(String(list[i]));
    return out;
  }

  // A plain copy of switch `index` of Settings.data.inputMethod.switches.
  function _switchAt(index) {
    var list = Settings.data.inputMethod.switches;
    var sw = list && index < list.length ? list[index] : null;
    return {
      "keys": root._copyList(sw ? sw.keys : []),
      "target": sw ? String(sw.target || "") : "",
      "mode": sw && sw.mode === "set" ? "set" : "toggle",
      "label": sw ? String(sw.label || "") : ""
    };
  }

  // Writes a new switches array: a copy of every switch, changed by `mutate(copies)`.
  function _writeSwitches(mutate) {
    var list = Settings.data.inputMethod.switches;
    var next = [];
    for (var i = 0; i < list.length; i++)
      next.push(root._switchAt(i));
    mutate(next);
    Settings.data.inputMethod.switches = next;
  }

  function _patchSwitch(index, patch) {
    root._writeSwitches(function (next) {
      for (var key in patch)
        next[index][key] = patch[key];
    });
  }

  function _addSwitch() {
    root._writeSwitches(function (next) {
      next.push({
                  "keys": [],
                  "target": "",
                  "mode": "toggle",
                  "label": ""
                });
    });
  }

  function _removeSwitch(index) {
    root._writeSwitches(function (next) {
      next.splice(index, 1);
    });
  }

  // Input-method choices from fcitx5's installed list; the target stays selectable when it is not installed.
  function _imChoices(target) {
    var out = [];
    var ims = InputMethodService.availableIMs;
    var listed = false;
    for (var i = 0; ims && i < ims.length; i++) {
      var im = ims[i];
      var name = im.name || im.uniqueName;
      if (im.language)
        name += " (" + im.language + ")";
      out.push({
                 "key": im.uniqueName,
                 "name": name
               });
      if (im.uniqueName === target)
        listed = true;
    }
    if (target && !listed)
      out.push({
                 "key": target,
                 "name": target + " (" + I18n.tr("panels.general.input-method-not-installed") + ")"
               });
    return out;
  }

  function _modeChoices() {
    return [
          {
            "key": "toggle",
            "name": I18n.tr("panels.general.input-method-mode-toggle")
          },
          {
            "key": "set",
            "name": I18n.tr("panels.general.input-method-mode-set")
          }
        ];
  }

  // The refusal of a recorded combo, or "": refused when it is malformed or an Atmosphera file binds it.
  function _comboMessage(combo) {
    var refusal = InputMethodService.validateCombo(combo);
    if (refusal !== "")
      return I18n.tr("panels.general.input-method-invalid-combo", {
                       "reason": refusal
                     });
    var owner = InputMethodBinds.conflictFor(combo);
    if (owner !== "")
      return I18n.tr("panels.general.input-method-bound-by", {
                       "owner": owner
                     });
    return "";
  }

  function _importLegacy() {
    InputMethodBinds.importLegacyI18n(function (count, error) {
      root._importStatus = error ? I18n.tr("panels.general.input-method-import-failed", {
                                             "error": error
                                           }) : I18n.tr("panels.general.input-method-import-done", {
                                                          "count": count
                                                        });
    });
  }

  NLabel {
    label: I18n.tr("panels.general.input-method-title")
    description: I18n.tr("panels.general.input-method-description")
    Layout.fillWidth: true
  }

  NText {
    visible: !InputMethodService.fcitx5Available
    text: I18n.tr("panels.general.input-method-unavailable")
    pointSize: Style.fontSizeS
    color: AtmoColor.mOnSurfaceVariant
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  ColumnLayout {
    id: inputMethodControls
    Layout.fillWidth: true
    spacing: Style.marginM
    enabled: InputMethodService.fcitx5Available
    opacity: enabled ? 1.0 : 0.6

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM
      visible: InputMethodBinds.customI18nFile

      NText {
        Layout.fillWidth: true
        text: I18n.tr("panels.general.input-method-custom-file")
        pointSize: Style.fontSizeS
        color: AtmoColor.mError
        wrapMode: Text.WordWrap
      }

      NButton {
        text: I18n.tr("panels.general.input-method-import")
        icon: Icon.download
        outlined: true
        onClicked: root._importLegacy()
      }
    }

    NText {
      visible: root._importStatus !== ""
      Layout.fillWidth: true
      text: root._importStatus
      pointSize: Style.fontSizeS
      color: AtmoColor.mOnSurfaceVariant
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: Settings.data.inputMethod.switches.length

      delegate: Rectangle {
        id: switchCard
        required property int index
        readonly property var sw: root._switchAt(index)

        Layout.fillWidth: true
        implicitHeight: switchColumn.implicitHeight + Style.marginL * 2
        radius: Style.radiusL
        color: AtmoColor.mSurfaceVariant
        border.color: AtmoColor.mOutline
        border.width: Style.borderS

        ColumnLayout {
          id: switchColumn
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginM

          NComboBox {
            Layout.fillWidth: true
            label: I18n.tr("panels.general.input-method-target-label")
            model: root._imChoices(switchCard.sw.target)
            currentKey: switchCard.sw.target
            placeholder: I18n.tr("panels.general.input-method-target-placeholder")
            onSelected: key => root._patchSwitch(switchCard.index, {
                                                   "target": key
                                                 })
          }

          NKeybindRecorder {
            Layout.fillWidth: true
            label: I18n.tr("panels.general.input-method-keys-label")
            currentKeybinds: switchCard.sw.keys
            superCountsAsModifier: true
            conflictCheck: root._comboMessage
            onKeybindsChanged: newKeybinds => root._patchSwitch(switchCard.index, {
                                                                  "keys": newKeybinds
                                                                })
          }

          NComboBox {
            Layout.fillWidth: true
            label: I18n.tr("panels.general.input-method-mode-label")
            model: root._modeChoices()
            currentKey: switchCard.sw.mode
            onSelected: key => root._patchSwitch(switchCard.index, {
                                                   "mode": key
                                                 })
          }

          NTextInput {
            Layout.fillWidth: true
            label: I18n.tr("panels.general.input-method-label-label")
            placeholderText: I18n.tr("panels.general.input-method-label-placeholder")
            text: switchCard.sw.label
            onEditingFinished: root._patchSwitch(switchCard.index, {
                                                   "label": text
                                                 })
          }

          NButton {
            Layout.alignment: Qt.AlignRight
            text: I18n.tr("common.remove")
            icon: Icon.trash
            outlined: true
            onClicked: root._removeSwitch(switchCard.index)
          }
        }
      }
    }

    NButton {
      text: I18n.tr("panels.general.input-method-add")
      icon: Icon.add
      outlined: true
      onClicked: root._addSwitch()
    }

    NKeybindRecorder {
      Layout.fillWidth: true
      label: I18n.tr("panels.general.input-method-next-label")
      description: I18n.tr("panels.general.input-method-next-description")
      currentKeybinds: root._copyList(Settings.data.inputMethod.nextKeys)
      allowEmpty: true
      superCountsAsModifier: true
      conflictCheck: root._comboMessage
      onKeybindsChanged: newKeybinds => Settings.data.inputMethod.nextKeys = newKeybinds
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.fillHeight: true
  }
}
