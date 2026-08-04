import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  property string editPanelSize: pluginApi?.pluginSettings?.panelSize || pluginApi?.manifest?.metadata?.defaultSettings?.panelSize || "regular"
  property string editCorner: pluginApi?.pluginSettings?.corner || pluginApi?.manifest?.metadata?.defaultSettings?.corner || "bottomRight"

  NText {
    text: "Panel"
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NComboBox {
    Layout.fillWidth: true
    label: "Size"
    description: "Panel size limit — the map still shrinks to fit its content below the limit"
    model: [
      {
        "key": "compact",
        "name": "Compact (300×200)"
      },
      {
        "key": "regular",
        "name": "Regular (440×200 — Control Center width)"
      },
      {
        "key": "large",
        "name": "Large (880×400 — 2× Control Center)"
      }
    ]
    currentKey: root.editPanelSize
    defaultValue: "regular"
    onSelected: function (key) {
      root.editPanelSize = key;
    }
  }

  NComboBox {
    Layout.fillWidth: true
    label: "Corner"
    description: "Which screen corner the map anchors to"
    model: [
      {
        "key": "bottomRight",
        "name": "Bottom right"
      },
      {
        "key": "bottomLeft",
        "name": "Bottom left"
      },
      {
        "key": "topRight",
        "name": "Top right"
      },
      {
        "key": "topLeft",
        "name": "Top left"
      }
    ]
    currentKey: root.editCorner
    defaultValue: "bottomRight"
    onSelected: function (key) {
      root.editCorner = key;
    }
  }

  function saveSettings() {
    if (!pluginApi) {
      Logger.e("NiriWindowsMap", "Cannot save settings: pluginApi is null");
      return;
    }
    pluginApi.pluginSettings.panelSize = root.editPanelSize;
    pluginApi.pluginSettings.corner = root.editCorner;
    pluginApi.saveSettings();
  }
}
