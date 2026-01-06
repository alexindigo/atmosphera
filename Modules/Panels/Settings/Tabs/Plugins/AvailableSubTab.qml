import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../../../Helpers/FuzzySort.js" as Fuzzysort
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property string pluginFilter: "all"
  property string pluginSearchText: ""

  function stripAuthorEmail(author) {
    if (!author)
      return "";
    var lastBracket = author.lastIndexOf("<");
    if (lastBracket >= 0) {
      return author.substring(0, lastBracket).trim();
    }
    return author;
  }

  // Filter controls
  RowLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    NTabBar {
      id: filterTabBar
      Layout.fillWidth: true
      spacing: Style.marginM
      currentIndex: 0
      onCurrentIndexChanged: {
        if (currentIndex === 0)
          root.pluginFilter = "all";
        else if (currentIndex === 1)
          root.pluginFilter = "downloaded";
        else if (currentIndex === 2)
          root.pluginFilter = "notDownloaded";
      }

      NTabButton {
        Layout.fillWidth: true
        text: I18n.tr("launcher.categories.all")
        tabIndex: 0
        checked: root.pluginFilter === "all"
      }

      NTabButton {
        Layout.fillWidth: true
        text: I18n.tr("panels.plugins.filter-downloaded")
        tabIndex: 1
        checked: root.pluginFilter === "downloaded"
      }

      NTabButton {
        Layout.fillWidth: true
        text: I18n.tr("panels.plugins.filter-not-downloaded")
        tabIndex: 2
        checked: root.pluginFilter === "notDownloaded"
      }
    }

    NIconButton {
      icon: "refresh"
      tooltipText: I18n.tr("panels.plugins.refresh-tooltip")
      baseSize: Style.baseWidgetSize * 0.9
      onClicked: {
        PluginService.refreshAvailablePlugins();
        checkUpdatesTimer.restart();
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.refresh-refreshing"));
      }
    }
  }

  // Search input
  NTextInput {
    placeholderText: I18n.tr("placeholders.search")
    inputIconName: "search"
    text: root.pluginSearchText
    onTextChanged: root.pluginSearchText = text
    Layout.fillWidth: true
  }

  // Available plugins list
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    Repeater {
      id: availablePluginsRepeater

      model: {
        var all = PluginService.availablePlugins || [];
        var filtered = [];

        // First apply download filter
        for (var i = 0; i < all.length; i++) {
          var plugin = all[i];
          var downloaded = plugin.downloaded || false;

          if (root.pluginFilter === "all") {
            filtered.push(plugin);
          } else if (root.pluginFilter === "downloaded" && downloaded) {
            filtered.push(plugin);
          } else if (root.pluginFilter === "notDownloaded" && !downloaded) {
            filtered.push(plugin);
          }
        }

        // Then apply fuzzy search if there's search text
        var query = root.pluginSearchText.trim();
        if (query !== "") {
          var results = Fuzzysort.go(query, filtered, {
                                       "keys": ["name", "description"],
                                       "threshold": 0.35,
                                       "limit": 50
                                     });
          filtered = [];
          for (var j = 0; j < results.length; j++) {
            filtered.push(results[j].obj);
          }
        } else {
          // Sort by lastUpdated (most recent first) when not searching
          filtered.sort(function (a, b) {
            var dateA = a.lastUpdated ? new Date(a.lastUpdated).getTime() : 0;
            var dateB = b.lastUpdated ? new Date(b.lastUpdated).getTime() : 0;
            return dateB - dateA;
          });
        }

        return filtered;
      }

      delegate: NBox {
        id: pluginBox
        property bool isHovered: hoverHandler.hovered

        Layout.fillWidth: true
        Layout.leftMargin: Style.borderS
        Layout.rightMargin: Style.borderS
        implicitHeight: Math.round(contentColumn.implicitHeight + Style.marginL * 2)
        color: Color.mSurface

        Behavior on implicitHeight {
          NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
          }
        }

        HoverHandler {
          id: hoverHandler
        }

        ColumnLayout {
          id: contentColumn
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginS

          RowLayout {
            spacing: Style.marginM
            Layout.fillWidth: true

            NIcon {
              icon: "plugin"
              pointSize: Style.fontSizeL
              color: Color.mOnSurface
            }

            NText {
              text: modelData.name
              color: Color.mOnSurface
              elide: Text.ElideRight
            }

            // Description excerpt - visible when not hovered
            NText {
              visible: !pluginBox.isHovered && modelData.description
              text: modelData.description || ""
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            // Spacer when hovered or no description
            Item {
              visible: pluginBox.isHovered || !modelData.description
              Layout.fillWidth: true
            }

            // Downloaded indicator
            NIcon {
              icon: "circle-check"
              pointSize: Style.fontSizeL
              color: Color.mPrimary
              visible: modelData.downloaded === true
            }

            // Install/Uninstall button
            NIconButton {
              icon: modelData.downloaded ? "trash" : "download"
              baseSize: Style.baseWidgetSize * 0.7
              tooltipText: modelData.downloaded ? I18n.tr("common.uninstall") : I18n.tr("common.install")
              onClicked: {
                if (modelData.downloaded) {
                  // Construct composite key for available plugins
                  var pluginData = Object.assign({}, modelData);
                  pluginData.compositeKey = PluginRegistry.generateCompositeKey(modelData.id, modelData.source?.url || "");
                  uninstallDialog.pluginToUninstall = pluginData;
                  uninstallDialog.open();
                } else {
                  installPlugin(modelData);
                }
              }
            }
          }

          // Description - visible on hover
          NText {
            visible: pluginBox.isHovered && modelData.description
            text: modelData.description || ""
            font.pointSize: Style.fontSizeXS
            color: Color.mOnSurface
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          // Details row - visible on hover
          RowLayout {
            visible: pluginBox.isHovered
            spacing: Style.marginS
            Layout.fillWidth: true

            NText {
              text: "v" + modelData.version
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: "•"
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: stripAuthorEmail(modelData.author)
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: "•"
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: modelData.source ? modelData.source.name : ""
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            Item {
              Layout.fillWidth: true
            }
          }
        }
      }
    }

    NLabel {
      visible: availablePluginsRepeater.count === 0
      label: I18n.tr("panels.plugins.available-no-plugins-label")
      description: I18n.tr("panels.plugins.available-no-plugins-description")
      Layout.fillWidth: true
    }
  }

  // Uninstall confirmation dialog
  Popup {
    id: uninstallDialog
    parent: Overlay.overlay
    modal: true
    dim: false
    anchors.centerIn: parent
    width: 400 * Style.uiScaleRatio
    padding: Style.marginL

    property var pluginToUninstall: null

    background: Rectangle {
      color: Color.mSurface
      radius: Style.radiusS
      border.color: Color.mPrimary
      border.width: Style.borderM
    }

    contentItem: ColumnLayout {
      width: parent.width
      spacing: Style.marginL

      NHeader {
        label: I18n.tr("panels.plugins.uninstall-dialog-title")
        description: I18n.tr("panels.plugins.uninstall-dialog-description", {
                               "plugin": uninstallDialog.pluginToUninstall?.name || ""
                             })
      }

      RowLayout {
        spacing: Style.marginM
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }

        NButton {
          text: I18n.tr("common.cancel")
          onClicked: uninstallDialog.close()
        }

        NButton {
          text: I18n.tr("common.uninstall")
          backgroundColor: Color.mPrimary
          textColor: Color.mOnPrimary
          onClicked: {
            if (uninstallDialog.pluginToUninstall) {
              uninstallPlugin(uninstallDialog.pluginToUninstall.compositeKey);
              uninstallDialog.close();
            }
          }
        }
      }
    }
  }

  // Timer to check for updates after refresh starts
  Timer {
    id: checkUpdatesTimer
    interval: 100
    onTriggered: {
      PluginService.checkForUpdates();
    }
  }

  function installPlugin(pluginMetadata) {
    ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.installing", {
                                                                       "plugin": pluginMetadata.name
                                                                     }));

    PluginService.installPlugin(pluginMetadata, false, function (success, error, registeredKey) {
      if (success) {
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.install-success", {
                                                                           "plugin": pluginMetadata.name
                                                                         }));
        // Auto-enable the plugin after installation (use registered key which may be composite)
        PluginService.enablePlugin(registeredKey);
      } else {
        ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.install-error", {
                                                                          "error": error || "Unknown error"
                                                                        }));
      }
    });
  }

  function uninstallPlugin(pluginId) {
    var manifest = PluginRegistry.getPluginManifest(pluginId);
    var pluginName = manifest?.name || pluginId;

    ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.uninstalling", {
                                                                       "plugin": pluginName
                                                                     }));

    PluginService.uninstallPlugin(pluginId, function (success, error) {
      if (success) {
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.uninstall-success", {
                                                                           "plugin": pluginName
                                                                         }));
      } else {
        ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.uninstall-error", {
                                                                          "error": error || "Unknown error"
                                                                        }));
      }
    });
  }

  // Listen to plugin service signals
  Connections {
    target: PluginService

    function onAvailablePluginsUpdated() {
      // Force model refresh for available plugins
      availablePluginsRepeater.model = undefined;
      Qt.callLater(function () {
        availablePluginsRepeater.model = Qt.binding(function () {
          var all = PluginService.availablePlugins || [];
          var filtered = [];

          for (var i = 0; i < all.length; i++) {
            var plugin = all[i];
            var downloaded = plugin.downloaded || false;

            if (root.pluginFilter === "all") {
              filtered.push(plugin);
            } else if (root.pluginFilter === "downloaded" && downloaded) {
              filtered.push(plugin);
            } else if (root.pluginFilter === "notDownloaded" && !downloaded) {
              filtered.push(plugin);
            }
          }

          return filtered;
        });
      });

      // Manually trigger update check after a small delay to ensure all registries are loaded
      Qt.callLater(function () {
        PluginService.checkForUpdates();
      });
    }
  }
}
