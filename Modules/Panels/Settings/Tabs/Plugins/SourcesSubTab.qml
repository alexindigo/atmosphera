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
  Layout.fillWidth: true

  property string homeDir: ""

  Component.onCompleted: {
    var getHome = Qt.createQmlObject('import QtQuick; import Quickshell.Io; Process { command: ["sh", "-c", "echo $HOME"]; stdout: StdioCollector {} }', root, "GetHome");
    getHome.stdout.onStreamFinished.connect(function () {
      root.homeDir = getHome.stdout.text.trim();
      getHome.destroy();
    });
    getHome.running = true;
  }

  function sourceIcon(url) {
    if (!url)
      return "brand-git";
    if (url.startsWith("file://"))
      return "folder";
    var domain = url;
    var protoIdx = domain.indexOf("://");
    if (protoIdx !== -1)
      domain = domain.substring(protoIdx + 3);
    var slashIdx = domain.indexOf("/");
    if (slashIdx !== -1)
      domain = domain.substring(0, slashIdx);
    var colonIdx = domain.indexOf(":");
    if (colonIdx !== -1)
      domain = domain.substring(0, colonIdx);
    var atIdx = domain.indexOf("@");
    if (atIdx !== -1)
      domain = domain.substring(atIdx + 1);
    var dotIdx = domain.lastIndexOf(".");
    if (dotIdx !== -1)
      domain = domain.substring(0, dotIdx);
    domain = domain.replace(/[^a-zA-Z0-9-]/g, "");
    var brandIcon = "brand-" + domain;
    if (brandIcon in Icons.icons)
      return brandIcon;
    return "brand-git";
  }

  function normalizeSourceUrl(input) {
    if (!input)
      return "";
    if (input.startsWith("file://"))
      return input;
    if (input.startsWith("~")) {
      return "file://" + root.homeDir + input.substring(1);
    }
    if (input.startsWith("/"))
      return "file://" + input;
    var firstSlash = input.indexOf("/");
    var firstWord = firstSlash === -1 ? input : input.substring(0, firstSlash);
    if (firstWord.indexOf(".") !== -1)
      return "https://" + input;
    return input;
  }

  // List of plugin sources
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    Repeater {
      id: pluginSourcesRepeater
      model: PluginRegistry.pluginSources || []

      delegate: NBox {
        Layout.fillWidth: true
        implicitHeight: sourceRow.implicitHeight + Style.margin2L
        color: Color.mSurface

        RowLayout {
          id: sourceRow
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginM

          NIcon {
            icon: root.sourceIcon(modelData.url)
            pointSize: Style.fontSizeL
          }

          ColumnLayout {
            spacing: 2
            Layout.fillWidth: true

            NText {
              text: modelData.name
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            NText {
              text: modelData.url
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              Layout.fillWidth: true
              elide: Text.ElideRight
            }
          }

          NIconButton {
            icon: "pencil"
            tooltipText: I18n.tr("panels.plugins.sources-edit-tooltip")
            baseSize: Style.baseWidgetSize * 0.7
            onClicked: {
              sourceDialog.editSource(modelData.name, modelData.url);
              sourceDialog.open();
            }
          }

          NIconButton {
            icon: "trash"
            tooltipText: I18n.tr("panels.plugins.sources-remove-tooltip")
            baseSize: Style.baseWidgetSize * 0.7
            onClicked: {
              PluginRegistry.removePluginSource(modelData.url);
            }
          }

          NToggle {
            checked: modelData.enabled !== false
            baseSize: Style.baseWidgetSize * 0.7
            onToggled: checked => {
              PluginRegistry.setSourceEnabled(modelData.url, checked);
              PluginService.refreshAvailablePlugins();
              ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.refresh-refreshing"));
            }
          }
        }
      }
    }
  }

  NButton {
    text: I18n.tr("panels.plugins.sources-add-custom")
    icon: "plus"
    onClicked: {
      sourceDialog.addSource();
      sourceDialog.open();
    }
    Layout.fillWidth: true
  }

  Popup {
    id: sourceDialog
    parent: Overlay.overlay
    modal: true
    dim: false
    anchors.centerIn: parent
    width: 500
    padding: Style.marginL

    property string editingUrl: ""

    function addSource() {
      editingUrl = "";
      sourceNameInput.text = "";
      sourceUrlInput.text = "";
    }

    function editSource(name, url) {
      editingUrl = url;
      sourceNameInput.text = name;
      sourceUrlInput.text = url;
    }

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
        label: sourceDialog.editingUrl ? I18n.tr("panels.plugins.sources-edit-dialog-title") : I18n.tr("panels.plugins.sources-add-dialog-title")
        description: sourceDialog.editingUrl ? I18n.tr("panels.plugins.sources-edit-dialog-description") : I18n.tr("panels.plugins.sources-add-dialog-description")
      }

      NTextInput {
        id: sourceNameInput
        label: I18n.tr("panels.plugins.sources-add-dialog-name")
        placeholderText: I18n.tr("panels.plugins.sources-add-dialog-name-placeholder")
        Layout.fillWidth: true
      }

      RowLayout {
        spacing: Style.marginS
        Layout.fillWidth: true

        NTextInput {
          id: sourceUrlInput
          label: I18n.tr("panels.plugins.sources-add-dialog-url")
          placeholderText: I18n.tr("panels.plugins.sources-add-dialog-url-placeholder")
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "folder"
          tooltipText: I18n.tr("panels.plugins.sources-add-dialog-browse")
          border.width: 0
          Layout.preferredWidth: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio
          Layout.preferredHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio
          Layout.alignment: Qt.AlignBottom
          colorBg: "transparent"
          colorBgHover: Qt.alpha(Color.mPrimary, 0.1)
          onClicked: folderPicker.openFilePicker()
        }
      }

      NFilePicker {
        id: folderPicker
        title: I18n.tr("panels.plugins.sources-add-dialog-browse-title")
        selectionMode: "folders"
        onAccepted: function (paths) {
          sourceUrlInput.text = paths[0];
        }
      }

      RowLayout {
        spacing: Style.marginM
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }

        NButton {
          text: "Preview"
          icon: "folder"
          outlined: true
          onClicked: folderPicker.openFilePicker()
        }

        NButton {
          text: I18n.tr("common.cancel")
          onClicked: sourceDialog.close()
        }

        NButton {
          text: sourceDialog.editingUrl ? I18n.tr("common.save") : I18n.tr("common.add")
          backgroundColor: Color.mPrimary
          textColor: Color.mOnPrimary
          enabled: sourceNameInput.text.length > 0 && sourceUrlInput.text.length > 0
          onClicked: {
            var url = root.normalizeSourceUrl(sourceUrlInput.text);
            var success = sourceDialog.editingUrl ? PluginRegistry.editPluginSource(sourceDialog.editingUrl, sourceNameInput.text, url) : PluginRegistry.addPluginSource(sourceNameInput.text, url);
            if (success) {
              ToastService.showNotice(I18n.tr("panels.plugins.title"), sourceDialog.editingUrl ? I18n.tr("panels.plugins.sources-edit-dialog-success") : I18n.tr("panels.plugins.sources-add-dialog-success"));
              PluginService.refreshAvailablePlugins();
              sourceDialog.close();
            } else {
              ToastService.showError(I18n.tr("panels.plugins.title"), sourceDialog.editingUrl ? I18n.tr("panels.plugins.sources-edit-dialog-error") : I18n.tr("panels.plugins.sources-add-dialog-error"));
            }
          }
        }
      }
    }
  }

  // Listen to plugin registry changes
  Connections {
    target: PluginRegistry

    function onPluginsChanged() {
      // Force model refresh for plugin sources
      pluginSourcesRepeater.model = undefined;
      Qt.callLater(function () {
        pluginSourcesRepeater.model = Qt.binding(function () {
          return PluginRegistry.pluginSources || [];
        });
      });
    }
  }
}
