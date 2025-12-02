import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  width: parent.width

  // ------------------------------
  // Section 1: Installed Plugins
  // ------------------------------
  NHeader {
    label: I18n.tr("settings.plugins.installed.label")
    description: I18n.tr("settings.plugins.installed.description")
  }

  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    Repeater {
      id: installedPluginsRepeater

      model: {
        // Make this reactive to PluginRegistry changes
        var _ = PluginRegistry.installedPlugins; // Force dependency
        var __ = PluginRegistry.pluginStates;    // Force dependency

        var allIds = PluginRegistry.getAllInstalledPluginIds();
        var plugins = [];
        for (var i = 0; i < allIds.length; i++) {
          var manifest = PluginRegistry.getPluginManifest(allIds[i]);
          if (manifest) {
            plugins.push(manifest);
          }
        }
        return plugins;
      }

      delegate: NBox {
        Layout.fillWidth: true
        implicitHeight: rowLayout.implicitHeight + Style.marginL * 2
        color: Color.mSurface

        RowLayout {
          id: rowLayout
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginM

          NLabel {
            label: modelData.name
            description: modelData.description
          }

          NIconButton {
            icon: "settings"
            tooltipText: I18n.tr("settings.plugins.settings.tooltip")
            baseSize: Style.baseWidgetSize * 0.7
            visible: modelData.entryPoints?.settings !== undefined
            onClicked: {
              pluginSettingsDialog.openPluginSettings(modelData);
            }
          }

          NIconButton {
            icon: "trash"
            tooltipText: I18n.tr("settings.plugins.uninstall.tooltip")
            baseSize: Style.baseWidgetSize * 0.7
            onClicked: {
              uninstallDialog.pluginToUninstall = modelData;
              uninstallDialog.open();
            }
          }

          NToggle {
            checked: PluginRegistry.isPluginEnabled(modelData.id)
            baseSize: Style.baseWidgetSize * 0.7
            onToggled: function (checked) {
              if (checked) {
                PluginService.enablePlugin(modelData.id);
              } else {
                PluginService.disablePlugin(modelData.id);
              }
            }
          }
        }
      }
    }

    NLabel {
      visible: PluginRegistry.getAllInstalledPluginIds().length === 0
      label: I18n.tr("settings.plugins.installed.no-plugins")
      description: I18n.tr("settings.plugins.installed.no-plugins.description")
      Layout.fillWidth: true
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // ------------------------------
  // Section 2: Available Plugins
  // ------------------------------
  NHeader {
    label: I18n.tr("settings.plugins.available.label")
    description: I18n.tr("settings.plugins.available.description")
  }

  // Filter controls
  RowLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    NButton {
      text: I18n.tr("settings.plugins.filter.all")
      backgroundColor: pluginFilter === "all" ? Color.mPrimary : Color.mSurfaceVariant
      textColor: pluginFilter === "all" ? Color.mOnPrimary : Color.mOnSurfaceVariant
      onClicked: pluginFilter = "all"
    }

    NButton {
      text: I18n.tr("settings.plugins.filter.downloaded")
      backgroundColor: pluginFilter === "downloaded" ? Color.mPrimary : Color.mSurfaceVariant
      textColor: pluginFilter === "downloaded" ? Color.mOnPrimary : Color.mOnSurfaceVariant
      onClicked: pluginFilter = "downloaded"
    }

    NButton {
      text: I18n.tr("settings.plugins.filter.not-downloaded")
      backgroundColor: pluginFilter === "notDownloaded" ? Color.mPrimary : Color.mSurfaceVariant
      textColor: pluginFilter === "notDownloaded" ? Color.mOnPrimary : Color.mOnSurfaceVariant
      onClicked: pluginFilter = "notDownloaded"
    }

    Item {
      Layout.fillWidth: true
    }

    NIconButton {
      icon: "refresh"
      tooltipText: I18n.tr("settings.plugins.refresh.tooltip")
      onClicked: {
        PluginService.refreshAvailablePlugins();
        ToastService.showNotice(I18n.tr("settings.plugins.refresh.refreshing"));
      }
    }
  }

  property string pluginFilter: "all"

  // Available plugins list
  NScrollView {
    Layout.fillWidth: true
    Layout.preferredHeight: 400

    NListView {
      id: pluginListView
      spacing: Style.marginM

      model: {
        var all = PluginService.availablePlugins || [];
        var filtered = [];

        for (var i = 0; i < all.length; i++) {
          var plugin = all[i];
          var downloaded = plugin.downloaded || false;

          if (pluginFilter === "all") {
            filtered.push(plugin);
          } else if (pluginFilter === "downloaded" && downloaded) {
            filtered.push(plugin);
          } else if (pluginFilter === "notDownloaded" && !downloaded) {
            filtered.push(plugin);
          }
        }

        return filtered;
      }

      delegate: RowLayout {
        width: pluginListView.width
        spacing: Style.marginM

        Rectangle {
          width: 48
          height: 48
          radius: Style.radiusM
          color: Color.mSurfaceContainerHigh

          NIcon {
            anchors.centerIn: parent
            icon: "plugin"
            pointSize: Style.fontSizeXL
          }
        }

        ColumnLayout {
          spacing: 2
          Layout.fillWidth: true

          NText {
            text: modelData.name
            font.weight: Font.Medium
            color: Color.mOnSurface
          }

          NText {
            text: modelData.description
            font.pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          RowLayout {
            spacing: Style.marginS

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
              text: modelData.author
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: "•"
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: modelData.source?.name || "Unknown"
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }
          }
        }

        // Downloaded indicator
        NIcon {
          icon: "check-circle"
          pointSize: Style.fontSizeM
          color: Color.mPrimary
          visible: modelData.downloaded === true
        }

        // Install/Uninstall button
        NButton {
          text: modelData.downloaded ? I18n.tr("settings.plugins.uninstall") : I18n.tr("settings.plugins.install")
          onClicked: {
            if (modelData.downloaded) {
              uninstallDialog.pluginToUninstall = modelData;
              uninstallDialog.open();
            } else {
              installPlugin(modelData);
            }
          }
        }

        // Enable/Disable toggle (only for downloaded plugins)
        NToggle {
          visible: modelData.downloaded === true
          checked: modelData.enabled || false
          onToggled: function (checked) {
            if (checked) {
              PluginService.enablePlugin(modelData.id);
            } else {
              PluginService.disablePlugin(modelData.id);
            }
          }
        }
      }
    }
  }

  NLabel {
    visible: pluginListView.count === 0
    label: I18n.tr("settings.plugins.available.no-plugins")
    description: I18n.tr("settings.plugins.available.no-plugins.description")
    Layout.fillWidth: true
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // ------------------------------
  // Section 3: Plugin Sources
  // ------------------------------
  NCollapsible {
    Layout.fillWidth: true
    label: I18n.tr("settings.plugins.sources.label")
    description: I18n.tr("settings.plugins.sources.description")
    expanded: false

    ColumnLayout {
      spacing: Style.marginM
      Layout.fillWidth: true

      // List of plugin sources
      Repeater {
        model: PluginRegistry.pluginSources || []

        delegate: RowLayout {
          spacing: Style.marginM
          Layout.fillWidth: true

          NIcon {
            icon: "brand-github"
            pointSize: Style.fontSizeM
          }

          ColumnLayout {
            spacing: 2
            Layout.fillWidth: true

            NText {
              text: modelData.name
              font.weight: Font.Medium
              color: Color.mOnSurface
            }

            NText {
              text: modelData.url
              font.pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
          }

          NIconButton {
            icon: "trash"
            tooltipText: I18n.tr("settings.plugins.sources.remove.tooltip")
            visible: index !== 0 // Cannot remove official source
            onClicked: {
              PluginRegistry.removePluginSource(modelData.url);
            }
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      // Add custom repository
      NButton {
        text: I18n.tr("settings.plugins.sources.add-custom")
        icon: "plus"
        onClicked: {
          addSourceDialog.open();
        }
        Layout.fillWidth: true
      }
    }
  }

  // ------------------------------
  // Dialogs
  // ------------------------------

  // Add source dialog
  Popup {
    id: addSourceDialog
    modal: true
    dim: false
    anchors.centerIn: parent
    width: 500
    padding: Style.marginL

    ColumnLayout {
      width: parent.width
      spacing: Style.marginL

      NHeader {
        label: I18n.tr("settings.plugins.sources.add-dialog.title")
        description: I18n.tr("settings.plugins.sources.add-dialog.description")
      }

      NTextInput {
        id: sourceNameInput
        label: I18n.tr("settings.plugins.sources.add-dialog.name")
        placeholderText: I18n.tr("settings.plugins.sources.add-dialog.name.placeholder")
        Layout.fillWidth: true
      }

      NTextInput {
        id: sourceUrlInput
        label: I18n.tr("settings.plugins.sources.add-dialog.url")
        placeholderText: "https://github.com/user/repo"
        Layout.fillWidth: true
      }

      RowLayout {
        spacing: Style.marginM
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }

        NButton {
          text: I18n.tr("common.cancel")
          onClicked: addSourceDialog.close()
        }

        NButton {
          text: I18n.tr("common.add")
          backgroundColor: Color.mPrimary
          textColor: Color.mOnPrimary
          enabled: sourceNameInput.text.length > 0 && sourceUrlInput.text.length > 0
          onClicked: {
            if (PluginRegistry.addPluginSource(sourceNameInput.text, sourceUrlInput.text)) {
              ToastService.showNotice(I18n.tr("settings.plugins.sources.add-dialog.success"));
              PluginService.refreshAvailablePlugins();
              addSourceDialog.close();
              sourceNameInput.text = "";
              sourceUrlInput.text = "";
            } else {
              ToastService.showNotice(I18n.tr("settings.plugins.sources.add-dialog.error"));
            }
          }
        }
      }
    }
  }

  // Uninstall confirmation dialog
  Popup {
    id: uninstallDialog
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
        label: I18n.tr("settings.plugins.uninstall-dialog.title")
        description: I18n.tr("settings.plugins.uninstall-dialog.description").replace("%1", uninstallDialog.pluginToUninstall?.name || "")
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
          text: I18n.tr("settings.plugins.uninstall")
          backgroundColor: Color.mPrimary
          textColor: Color.mOnPrimary
          onClicked: {
            if (uninstallDialog.pluginToUninstall) {
              root.uninstallPlugin(uninstallDialog.pluginToUninstall.id);
              uninstallDialog.close();
            }
          }
        }
      }
    }
  }

  // Plugin settings dialog
  Popup {
    id: pluginSettingsDialog
    modal: true
    dim: false
    anchors.centerIn: parent
    width: Math.max(settingsContent.implicitWidth + padding * 2, 500)
    height: settingsContent.implicitHeight + padding * 2
    padding: Style.marginXL

    property var currentPlugin: null
    property var currentPluginApi: null

    background: Rectangle {
      color: Color.mSurface
      radius: Style.radiusL
      border.color: Color.mPrimary
      border.width: Style.borderM
    }

    contentItem: FocusScope {
      focus: true

      ColumnLayout {
        id: settingsContent
        anchors.fill: parent
        spacing: Style.marginM

        // Header
        RowLayout {
          Layout.fillWidth: true

          NText {
            text: I18n.tr("system.plugin-settings-title", {
                            "plugin": pluginSettingsDialog.currentPlugin?.name || ""
                          })
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mPrimary
            Layout.fillWidth: true
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("tooltips.close")
            onClicked: pluginSettingsDialog.close()
          }
        }

        // Separator
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Color.mOutline
        }

        // Settings loader
        Loader {
          id: settingsLoader
          Layout.fillWidth: true
        }

        // Action buttons
        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.marginM
          spacing: Style.marginM

          Item {
            Layout.fillWidth: true
          }

          NButton {
            text: I18n.tr("common.cancel")
            outlined: true
            onClicked: pluginSettingsDialog.close()
          }

          NButton {
            text: I18n.tr("common.apply")
            icon: "check"
            onClicked: {
              if (settingsLoader.item && settingsLoader.item.saveSettings) {
                settingsLoader.item.saveSettings();
                pluginSettingsDialog.close();
                ToastService.showNotice(I18n.tr("settings.plugins.settings-saved"));
              }
            }
          }
        }
      }
    }

    function openPluginSettings(pluginManifest) {
      currentPlugin = pluginManifest;

      // Get plugin API
      currentPluginApi = PluginService.getPluginAPI(pluginManifest.id);
      if (!currentPluginApi) {
        Logger.e("PluginsTab", "Cannot open settings: plugin not loaded:", pluginManifest.id);
        ToastService.showNotice(I18n.tr("settings.plugins.settings-error-not-loaded"));
        return;
      }

      // Get plugin directory
      var pluginDir = PluginRegistry.getPluginDir(pluginManifest.id);
      var settingsPath = pluginDir + "/" + pluginManifest.entryPoints.settings;

      // Load settings component
      settingsLoader.setSource("file://" + settingsPath, {
                                 "pluginApi": currentPluginApi
                               });

      open();
    }
  }

  // ------------------------------
  // Functions
  // ------------------------------

  function installPlugin(pluginMetadata) {
    ToastService.show(I18n.tr("settings.plugins.installing").replace("%1", pluginMetadata.name));

    PluginService.installPlugin(pluginMetadata, function (success, error) {
      if (success) {
        ToastService.showNotice(I18n.tr("settings.plugins.install-success").replace("%1", pluginMetadata.name));
      } else {
        ToastService.showNotice(I18n.tr("settings.plugins.install-error").replace("%1", error || "Unknown error"));
      }
    });
  }

  function uninstallPlugin(pluginId) {
    var manifest = PluginRegistry.getPluginManifest(pluginId);
    var pluginName = manifest?.name || pluginId;

    ToastService.showNotice(I18n.tr("settings.plugins.uninstalling").replace("%1", pluginName));

    PluginService.uninstallPlugin(pluginId, function (success, error) {
      if (success) {
        ToastService.showNotice(I18n.tr("settings.plugins.uninstall-success").replace("%1", pluginName));
      } else {
        ToastService.showNotice(I18n.tr("settings.plugins.uninstall-error").replace("%1", error || "Unknown error"));
      }
    });
  }

  // Listen to plugin registry changes
  Connections {
    target: PluginRegistry

    function onPluginsChanged() {
      // Force model refresh for installed plugins
      installedPluginsRepeater.model = undefined;
      Qt.callLater(function () {
        installedPluginsRepeater.model = Qt.binding(function () {
          var allIds = PluginRegistry.getAllInstalledPluginIds();
          var plugins = [];
          for (var i = 0; i < allIds.length; i++) {
            var manifest = PluginRegistry.getPluginManifest(allIds[i]);
            if (manifest) {
              plugins.push(manifest);
            }
          }
          return plugins;
        });
      });
    }
  }

  // Listen to plugin service signals
  Connections {
    target: PluginService

    function onAvailablePluginsUpdated() {
      // Force model refresh
      pluginListView.model = undefined;
      Qt.callLater(function () {
        pluginListView.model = Qt.binding(function () {
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
    }
  }
}
