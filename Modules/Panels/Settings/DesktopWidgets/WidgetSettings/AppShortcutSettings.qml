import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  ListModel {
    id: appListModel
  }

  function _rebuildAppList() {
    appListModel.clear();
    var apps = (DesktopEntries.applications.values || []).filter(a => a && !a.noDisplay && !a.hidden).sort((a, b) => (a.name || "").localeCompare(b.name || ""));
    for (var i = 0; i < apps.length; i++) {
      appListModel.append({
                            key: apps[i].id,
                            name: apps[i].name || apps[i].id
                          });
    }
  }

  Component.onCompleted: {
    _rebuildAppList();
    rebuildEnvVarsModel();
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      _rebuildAppList();
    }
  }

  property string valueAppId: widgetData?.appId ?? ""
  property string valueCustomLabel: widgetData?.customLabel ?? ""
  property bool valueShowLabel: widgetData?.showLabel !== false
  property bool valueSingleClick: widgetData?.singleClick === true
  property bool valueShowBg: widgetData?.showBackground !== false
  property bool valueRounded: widgetData?.roundedCorners !== false
  property var valueEnvVars: widgetData?.environmentVars ?? []
  property real valueBlendStrength: widgetData?.blendStrength ?? Settings.data.desktopWidgets.iconBlendStrength
  property real valueHueAdjustment: widgetData?.hueAdjustment ?? Settings.data.desktopWidgets.iconHueAdjustment

  ListModel {
    id: envVarsModel
  }

  function rebuildEnvVarsModel() {
    envVarsModel.clear();
    var vars = root.valueEnvVars || [];
    for (var i = 0; i < vars.length; i++) {
      var v = vars[i];
      envVarsModel.append({
                            key: v.key || "",
                            value: v.value || ""
                          });
    }
  }

  NSearchableComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.app-shortcut-application-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-application-description")
    model: appListModel
    currentKey: root.valueAppId
    placeholder: I18n.tr("panels.desktop-widgets.app-shortcut-application-placeholder")
    onSelected: k => {
      root.valueAppId = k;
      save();
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.app-shortcut-custom-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-custom-label-description")
    text: root.valueCustomLabel
    onTextChanged: {
      root.valueCustomLabel = text;
      save();
    }
  }

  NToggle {
    label: I18n.tr("panels.desktop-widgets.app-shortcut-show-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-show-label-description")
    checked: root.valueShowLabel
    onToggled: c => {
      root.valueShowLabel = c;
      save();
    }
  }

  NToggle {
    label: I18n.tr("panels.desktop-widgets.app-shortcut-single-click")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-single-click-description")
    checked: root.valueSingleClick
    onToggled: c => {
      root.valueSingleClick = c;
      save();
    }
  }

  NToggle {
    label: I18n.tr("panels.desktop-widgets.app-shortcut-show-background")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-show-background-description")
    checked: root.valueShowBg
    onToggled: c => {
      root.valueShowBg = c;
      save();
    }
  }

  NToggle {
    label: I18n.tr("panels.desktop-widgets.app-shortcut-rounded-corners")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-rounded-corners-description")
    checked: root.valueRounded
    onToggled: c => {
      root.valueRounded = c;
      save();
    }
  }

  NDivider {
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  NHeader {
    label: I18n.tr("panels.desktop-widgets.app-shortcut-environment-vars-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-environment-vars-description")
  }

  Repeater {
    model: envVarsModel

    delegate: RowLayout {
      width: parent.width
      spacing: Style.marginS

      NTextInput {
        Layout.fillWidth: true
        placeholderText: I18n.tr("panels.desktop-widgets.app-shortcut-env-var-key-placeholder")
        text: model.key
        onTextChanged: {
          envVarsModel.setProperty(index, "key", text);
          save();
        }
      }

      NTextInput {
        Layout.fillWidth: true
        placeholderText: I18n.tr("panels.desktop-widgets.app-shortcut-env-var-value-placeholder")
        text: model.value
        onTextChanged: {
          envVarsModel.setProperty(index, "value", text);
          save();
        }
      }

      NButton {
        icon: Icon.trash
        tooltipText: I18n.tr("common.remove")
        onClicked: {
          envVarsModel.remove(index);
          save();
        }
      }
    }
  }

  NButton {
    text: I18n.tr("panels.desktop-widgets.app-shortcut-env-var-add")
    icon: Icon.add
    onClicked: {
      envVarsModel.append({
                            key: "",
                            value: ""
                          });
    }
  }

  NDivider {
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  NHeader {
    label: I18n.tr("panels.desktop-widgets.app-shortcut-icon-colorize-label")
    description: I18n.tr("panels.desktop-widgets.app-shortcut-icon-colorize-description")
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.icon-blend-strength-label")
    from: 0
    to: 1
    stepSize: 0.05
    showReset: true
    value: root.valueBlendStrength
    defaultValue: Settings.data.desktopWidgets.iconBlendStrength
    onMoved: v => {
      root.valueBlendStrength = v;
      save();
    }
    text: Math.round(root.valueBlendStrength * 100) + "%"
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.icon-hue-adjustment-label")
    from: -180
    to: 180
    stepSize: 5
    showReset: true
    value: root.valueHueAdjustment
    defaultValue: Settings.data.desktopWidgets.iconHueAdjustment
    onMoved: v => {
      root.valueHueAdjustment = v;
      save();
    }
    text: (root.valueHueAdjustment > 0 ? "+" : "") + root.valueHueAdjustment + "°"
  }

  function save() {
    var envVars = [];
    for (var i = 0; i < envVarsModel.count; i++) {
      var item = envVarsModel.get(i);
      if (item.key && item.key.trim() !== "") {
        envVars.push({
                       key: item.key.trim(),
                       value: item.value
                     });
      }
    }

    settingsChanged({
                      appId: valueAppId,
                      customLabel: valueCustomLabel,
                      showLabel: valueShowLabel,
                      singleClick: valueSingleClick,
                      showBackground: valueShowBg,
                      roundedCorners: valueRounded,
                      environmentVars: envVars,
                      blendStrength: valueBlendStrength,
                      hueAdjustment: valueHueAdjustment
                    });
  }
}
