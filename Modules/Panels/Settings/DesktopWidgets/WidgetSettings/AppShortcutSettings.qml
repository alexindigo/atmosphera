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

  Component.onCompleted: _rebuildAppList()

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

  function save() {
    settingsChanged({
                      appId: valueAppId,
                      customLabel: valueCustomLabel,
                      showLabel: valueShowLabel,
                      singleClick: valueSingleClick,
                      showBackground: valueShowBg,
                      roundedCorners: valueRounded
                    });
  }
}
