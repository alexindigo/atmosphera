import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

Popup {
  id: root

  property int widgetIndex: -1
  property var widgetData: null
  property string widgetId: ""
  property string sectionId: "" // Not used for desktop widgets, but required by NSectionEditor
  property var screen: null
  property var settingsCache: ({})
  // Optional anchor rect — if set, dialog positions itself beside this rect
  // (so it doesn't cover the widget being edited).
  property real anchorX: -1
  property real anchorY: -1
  property real anchorW: 0
  property real anchorH: 0

  readonly property real maxHeight: (screen ? screen.height : (parent ? parent.height : 800)) * 0.8

  signal updateWidgetSettings(string section, int index, var settings)

  width: Math.max(content.implicitWidth + padding * 2, 500)
  height: Math.min(content.implicitHeight + padding * 2, maxHeight)
  padding: Style.marginXL
  modal: true
  closePolicy: Popup.NoAutoClose
  dim: false

  // Position: if anchor rect is set, place beside the widget without covering it.
  // Try right → left → above → below → clamped fallback.
  readonly property real _parentW: parent ? parent.width : 0
  readonly property real _parentH: parent ? parent.height : 0
  readonly property real _gap: Style.marginM

  // Preferred candidate positions computed once per size/anchor change
  readonly property var _positioned: {
    if (root.anchorX < 0) {
      // No anchor — center in parent
      return {
        "x": Math.round((_parentW - width) / 2),
        "y": Math.round((_parentH - height) / 2)
      };
    }

    var minX = Style.marginM;
    var maxX = _parentW - width - Style.marginM;
    var minY = Style.marginM;
    var maxY = _parentH - height - Style.marginM;

    // Try right of widget
    var rx = root.anchorX + root.anchorW + _gap;
    if (rx + width <= _parentW - Style.marginM) {
      var ry = Math.max(minY, Math.min(root.anchorY, maxY));
      return {
        "x": rx,
        "y": ry
      };
    }

    // Try left of widget
    var lx = root.anchorX - width - _gap;
    if (lx >= Style.marginM) {
      var ly = Math.max(minY, Math.min(root.anchorY, maxY));
      return {
        "x": lx,
        "y": ly
      };
    }

    // Try below widget
    var by = root.anchorY + root.anchorH + _gap;
    if (by + height <= _parentH - Style.marginM) {
      var bx = Math.max(minX, Math.min(root.anchorX, maxX));
      return {
        "x": bx,
        "y": by
      };
    }

    // Try above widget
    var ay = root.anchorY - height - _gap;
    if (ay >= Style.marginM) {
      var ax = Math.max(minX, Math.min(root.anchorX, maxX));
      return {
        "x": ax,
        "y": ay
      };
    }

    // Fallback — no space to avoid covering. Clamp on-screen.
    return {
      "x": Math.max(minX, Math.min(root.anchorX, maxX)),
      "y": Math.max(minY, Math.min(root.anchorY, maxY))
    };
  }

  x: _positioned.x
  y: _positioned.y

  onOpened: {
    if (widgetData && widgetId) {
      loadWidgetSettings();
    }
    forceActiveFocus();
  }

  background: Rectangle {
    id: bgRect
    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mPrimary
    border.width: Style.borderM
  }

  contentItem: FocusScope {
    id: focusScope
    focus: true

    ColumnLayout {
      id: content
      anchors.fill: parent
      spacing: Style.marginM

      RowLayout {
        id: titleRow
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight

        NText {
          text: I18n.tr("system.widget-settings-title", {
                          "widget": DesktopWidgetRegistry.getWidgetDisplayName(root.widgetId)
                        })
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mPrimary
          Layout.fillWidth: true
        }

        NIconButton {
          icon: Icon.close
          tooltipText: I18n.tr("common.close")
          onClicked: saveAndClose()
        }
      }

      Rectangle {
        id: separator
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
      }

      // Scrollable settings area
      NScrollView {
        id: scrollView
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 100
        gradientColor: Color.mSurface

        ColumnLayout {
          width: scrollView.availableWidth
          spacing: Style.marginM

          Loader {
            id: settingsLoader
            Layout.fillWidth: true
            Layout.preferredWidth: 500
            onStatusChanged: {
              if (status === Loader.Error) {
                Logger.e("DesktopWidgetSettingsDialog", "Settings loader error:", settingsLoader.errorString(), "source:", source);
              } else if (status === Loader.Ready) {
                Logger.d("DesktopWidgetSettingsDialog", "Settings loader ready:", source);
              }
            }
            onLoaded: {
              if (item) {
                Qt.callLater(() => {
                  var firstInput = findFirstFocusable(item);
                  if (firstInput) {
                    firstInput.forceActiveFocus();
                  } else {
                    focusScope.forceActiveFocus();
                  }
                });
              }
            }

            function findFirstFocusable(item) {
              if (!item)
                return null;
              if (item.focus !== undefined && item.focus === true)
                return item;
              if (item.children) {
                for (var i = 0; i < item.children.length; i++) {
                  var child = item.children[i];
                  if (child && child.focus !== undefined && child.focus === true)
                    return child;
                  var found = findFirstFocusable(child);
                  if (found)
                    return found;
                }
              }
              return null;
            }
          }
        }
      }
    }
  }

  // Mouse area for a draggable popup
  MouseArea {
    x: titleRow.x
    y: titleRow.y
    width: titleRow.width
    height: titleRow.height
    z: -1

    cursorShape: Qt.OpenHandCursor

    property real pressX: 0
    property real pressY: 0

    onPressed: mouse => {
      pressX = mouse.x;
      pressY = mouse.y;
      cursorShape = Qt.ClosedHandCursor;
    }

    onReleased: {
      cursorShape = Qt.OpenHandCursor;
    }

    onPositionChanged: mouse => {
      if (pressed) {
        var deltaX = mouse.x - pressX;
        var deltaY = mouse.y - pressY;

        root.x += deltaX;
        root.y += deltaY;
      }
    }
  }

  Timer {
    id: saveTimer
    running: false
    interval: 150
    onTriggered: {
      root.updateWidgetSettings(root.sectionId, root.widgetIndex, root.settingsCache);
    }
  }

  Connections {
    target: settingsLoader.item
    ignoreUnknownSignals: true
    function onSettingsChanged(newSettings) {
      if (newSettings) {
        root.settingsCache = newSettings;
        saveTimer.start();
      }
    }

    function onSettingsSaved(newSettings) {
      if (newSettings) {
        root.updateWidgetSettings(root.sectionId, root.widgetIndex, newSettings);
      }
    }
  }

  function saveAndClose() {
    if (settingsLoader.item && typeof settingsLoader.item.saveSettings === 'function') {
      var newSettings = settingsLoader.item.saveSettings();
      if (newSettings) {
        root.updateWidgetSettings(root.sectionId, root.widgetIndex, newSettings);
      }
    }
    root.close();
  }

  function loadWidgetSettings() {
    Logger.d("DesktopWidgetSettingsDialog", "loadWidgetSettings:", widgetId, "widgetIndex:", widgetIndex, "sectionId:", sectionId);

    // Handle plugin widgets
    if (DesktopWidgetRegistry.isPluginWidget(widgetId)) {
      var pluginId = widgetId.replace("plugin:", "");
      var manifest = PluginRegistry.getPluginManifest(pluginId);

      var pluginDir = PluginRegistry.getPluginDir(pluginId);
      var loadVersion = PluginRegistry.pluginLoadVersions[pluginId] || 0;
      var api = PluginService.getPluginAPI(pluginId);

      var settingsPath;
      if (manifest && manifest.entryPoints && manifest.entryPoints.desktopWidgetSettings) {
        settingsPath = "file://" + pluginDir + "/" + manifest.entryPoints.desktopWidgetSettings;

        var widgetSettings = {};
        widgetSettings.data = widgetData || {};
        widgetSettings.metadata = DesktopWidgetRegistry.widgetMetadata[widgetId] || {};
        widgetSettings.save = function () {
          var newSettings = Object.assign({}, widgetSettings.data);
          root.settingsCache = newSettings;
          saveTimer.start();
        };

        settingsLoader.setSource(settingsPath + "?v=" + loadVersion, {
                                   "pluginApi": api,
                                   "widgetSettings": widgetSettings
                                 });
      } else {
        Logger.w("DesktopWidgetSettingsDialog", "Plugin does not have desktop widget settings:", pluginId);

        // Fallback to the plugin settings
        if (manifest && manifest.entryPoints && manifest.entryPoints.settings) {
          settingsPath = "file://" + pluginDir + "/" + manifest.entryPoints.settings;

          settingsLoader.setSource(settingsPath + "?v=" + loadVersion, {
                                     "pluginApi": api
                                   });
        } else {
          Logger.w("DesktopWidgetSettingsDialog", "Plugin does not have settings:", pluginId);
        }
      }

      return;
    }

    // Handle core widgets
    const source = DesktopWidgetRegistry.widgetSettingsMap[widgetId];
    Logger.d("DesktopWidgetSettingsDialog", "core widget source:", source);
    if (source) {
      var currentWidgetData = widgetData;
      var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
      var foundWidget = false;
      for (var i = 0; i < monitorWidgets.length; i++) {
        if (monitorWidgets[i].name === sectionId) {
          var widgets = monitorWidgets[i].widgets || [];
          if (widgetIndex >= 0 && widgetIndex < widgets.length) {
            currentWidgetData = widgets[widgetIndex];
            foundWidget = true;
          }
          break;
        }
      }
      Logger.d("DesktopWidgetSettingsDialog", "foundWidget:", foundWidget, "monitorWidgets count:", monitorWidgets.length, "sectionId:", sectionId);
      var fullPath = Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/DesktopWidgets/" + source);
      Logger.d("DesktopWidgetSettingsDialog", "fullPath:", fullPath);
      settingsLoader.setSource(fullPath, {
                                 "widgetData": currentWidgetData,
                                 "widgetMetadata": DesktopWidgetRegistry.widgetMetadata[widgetId]
                               });
    } else {
      Logger.w("DesktopWidgetSettingsDialog", "No settings source for widget:", widgetId);
    }
  }
}
