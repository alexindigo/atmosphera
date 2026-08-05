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
        "name": "Compact"
      },
      {
        "key": "regular",
        "name": "Regular"
      },
      {
        "key": "large",
        "name": "Large"
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
        "key": "topLeft",
        "name": "Top left"
      },
      {
        "key": "topCenter",
        "name": "Top center"
      },
      {
        "key": "topRight",
        "name": "Top right"
      },
      {
        "key": "bottomLeft",
        "name": "Bottom left"
      },
      {
        "key": "bottomCenter",
        "name": "Bottom center"
      },
      {
        "key": "bottomRight",
        "name": "Bottom right"
      }
    ]
    currentKey: root.editCorner
    defaultValue: "bottomRight"
    onSelected: function (key) {
      root.editCorner = key;
    }
  }

  NToggle {
    label: "Hide icons"
    description: "Don't draw app icons on the map tiles"
    checked: pluginApi?.pluginSettings?.hideIcons ?? false
    onToggled: checked => {
      pluginApi.pluginSettings.hideIcons = checked;
      pluginApi.saveSettings();
    }
  }

  NToggle {
    label: "Hide on click"
    description: "Close the map after clicking a window tile"
    checked: pluginApi?.pluginSettings?.hideOnClick ?? false
    onToggled: checked => {
      pluginApi.pluginSettings.hideOnClick = checked;
      pluginApi.saveSettings();
    }
  }

  NToggle {
    label: "Show terminal process icon (if available)"
    description: "On terminal tiles, show the icon of the app running in the foreground instead of the terminal's icon"
    checked: pluginApi?.pluginSettings?.terminalIcons ?? true
    onToggled: checked => {
      pluginApi.pluginSettings.terminalIcons = checked;
      pluginApi.saveSettings();
    }
  }

  NToggle {
    label: "Browser tab favicons"
    description: "On browser tiles, show the current tab's site favicon (resolved locally from browser history — no network access)"
    checked: pluginApi?.pluginSettings?.browserIcons ?? true
    onToggled: checked => {
      pluginApi.pluginSettings.browserIcons = checked;
      pluginApi.saveSettings();
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
