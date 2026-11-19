import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local state
  property string valueHideMode: widgetData.hideMode !== undefined ? widgetData.hideMode : widgetMetadata.hideMode
  // Deprecated: hideWhenIdle now folded into hideMode = "idle"
  property bool valueHideWhenIdle: widgetData.hideWhenIdle !== undefined ? widgetData.hideWhenIdle : widgetMetadata.hideWhenIdle
  property bool valueShowAlbumArt: widgetData.showAlbumArt !== undefined ? widgetData.showAlbumArt : widgetMetadata.showAlbumArt
  property bool valuePanelShowAlbumArt: widgetData.panelShowAlbumArt !== undefined ? widgetData.panelShowAlbumArt : widgetMetadata.panelShowAlbumArt
  property bool valueShowArtistFirst: widgetData.showArtistFirst !== undefined ? widgetData.showArtistFirst : widgetMetadata.showArtistFirst
  property bool valueShowVisualizer: widgetData.showVisualizer !== undefined ? widgetData.showVisualizer : widgetMetadata.showVisualizer
  property string valueVisualizerType: widgetData.visualizerType !== undefined ? widgetData.visualizerType : widgetMetadata.visualizerType
  property string valueScrollingMode: widgetData.scrollingMode !== undefined ? widgetData.scrollingMode : widgetMetadata.scrollingMode
  property int valueMaxWidth: widgetData.maxWidth !== undefined ? widgetData.maxWidth : widgetMetadata.maxWidth
  property bool valueUseFixedWidth: widgetData.useFixedWidth !== undefined ? widgetData.useFixedWidth : widgetMetadata.useFixedWidth
  property bool valueShowProgressRing: widgetData.showProgressRing !== undefined ? widgetData.showProgressRing : widgetMetadata.showProgressRing
  property bool valueCompactMode: widgetData.compactMode !== undefined ? widgetData.compactMode : widgetMetadata.compactMode
  property string valueTextColor: widgetData.textColor !== undefined ? widgetData.textColor : widgetMetadata.textColor

  Component.onCompleted: {
    if (widgetData && widgetData.hideMode !== undefined) {
      valueHideMode = widgetData.hideMode;
    }
  }

  function saveSettings(fields) {
    if (fields)
      settingsChanged(fields);
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.hide-mode-label")
    description: I18n.tr("bar.media-mini.hide-mode-description")
    model: [
      {
        "key": "visible",
        "name": I18n.tr("hide-modes.visible")
      },
      {
        "key": "hidden",
        "name": I18n.tr("hide-modes.hidden")
      },
      {
        "key": "transparent",
        "name": I18n.tr("hide-modes.transparent")
      },
      {
        "key": "idle",
        "name": I18n.tr("hide-modes.idle")
      }
    ]
    currentKey: root.valueHideMode
    onSelected: key => {
      root.valueHideMode = key;
      saveSettings({hideMode: root.valueHideMode});
    }
    defaultValue: widgetMetadata.hideMode
  }

  NToggle {
    label: I18n.tr("bar.media-mini.show-album-art-label")
    description: I18n.tr("bar.media-mini.show-album-art-description")
    checked: valueShowAlbumArt
    onToggled: checked => {
      valueShowAlbumArt = checked;
      saveSettings({showAlbumArt: valueShowAlbumArt});
    }
    defaultValue: widgetMetadata.showAlbumArt
  }

  NToggle {
    label: I18n.tr("bar.media-mini.show-artist-first-label")
    description: I18n.tr("bar.media-mini.show-artist-first-description")
    checked: valueShowArtistFirst
    onToggled: checked => {
      valueShowArtistFirst = checked;
      saveSettings({showArtistFirst: valueShowArtistFirst});
    }
    defaultValue: widgetMetadata.showArtistFirst
  }

  NToggle {
    label: I18n.tr("bar.media-mini.show-visualizer-label")
    description: I18n.tr("bar.media-mini.show-visualizer-description")
    checked: valueShowVisualizer
    onToggled: checked => {
      valueShowVisualizer = checked;
      saveSettings({showVisualizer: valueShowVisualizer});
    }
    defaultValue: widgetMetadata.showVisualizer
  }

  NComboBox {
    visible: valueShowVisualizer
    label: I18n.tr("bar.media-mini.visualizer-type-label")
    description: I18n.tr("bar.media-mini.visualizer-type-description")
    model: [
      {
        "key": "linear",
        "name": I18n.tr("options.visualizer-types.linear")
      },
      {
        "key": "mirrored",
        "name": I18n.tr("options.visualizer-types.mirrored")
      },
      {
        "key": "wave",
        "name": I18n.tr("options.visualizer-types.wave")
      }
    ]
    currentKey: valueVisualizerType
    onSelected: key => {
      valueVisualizerType = key;
      saveSettings({visualizerType: valueVisualizerType});
    }
    minimumWidth: 200
    defaultValue: widgetMetadata.visualizerType
  }

  NTextInput {
    id: widthInput
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.max-width-label")
    description: I18n.tr("bar.media-mini.max-width-description")
    placeholderText: widgetMetadata.maxWidth
    text: valueMaxWidth
    onTextEdited: saveSettings({maxWidth: parseInt(text) || widgetMetadata.maxWidth})
    defaultValue: String(widgetMetadata.maxWidth)
  }

  NToggle {
    label: I18n.tr("bar.media-mini.use-fixed-width-label")
    description: I18n.tr("bar.media-mini.use-fixed-width-description")
    checked: valueUseFixedWidth
    onToggled: checked => {
      valueUseFixedWidth = checked;
      saveSettings({useFixedWidth: valueUseFixedWidth});
    }
    defaultValue: widgetMetadata.useFixedWidth
  }

  NToggle {
    label: I18n.tr("bar.media-mini.show-progress-ring-label")
    description: I18n.tr("bar.media-mini.show-progress-ring-description")
    checked: valueShowProgressRing
    onToggled: checked => {
      valueShowProgressRing = checked;
      saveSettings({showProgressRing: valueShowProgressRing});
    }
    defaultValue: widgetMetadata.showProgressRing
  }

  NColorChoice {
    currentKey: valueTextColor
    onSelected: key => {
      valueTextColor = key;
      saveSettings({textColor: valueTextColor});
    }
    defaultValue: widgetMetadata.textColor
  }

  NComboBox {
    label: I18n.tr("bar.media-mini.scrolling-mode-label")
    description: I18n.tr("bar.media-mini.scrolling-mode-description")
    model: [
      {
        "key": "always",
        "name": I18n.tr("options.scrolling-modes.always")
      },
      {
        "key": "hover",
        "name": I18n.tr("options.scrolling-modes.hover")
      },
      {
        "key": "never",
        "name": I18n.tr("options.scrolling-modes.never")
      }
    ]
    currentKey: valueScrollingMode
    onSelected: key => {
      valueScrollingMode = key;
      saveSettings({scrollingMode: valueScrollingMode});
    }
    minimumWidth: 200
    defaultValue: widgetMetadata.scrollingMode
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
  }

  NLabel {
    label: I18n.tr("bar.media-mini.panel-section-label")
    description: I18n.tr("bar.media-mini.panel-section-description")
    labelColor: AtmoColor.mPrimary
  }

  NToggle {
    label: I18n.tr("bar.media-mini.show-album-art-label")
    description: I18n.tr("bar.media-mini.show-album-art-description")
    checked: valuePanelShowAlbumArt
    onToggled: checked => {
      valuePanelShowAlbumArt = checked;
      saveSettings({panelShowAlbumArt: valuePanelShowAlbumArt});
    }
    defaultValue: widgetMetadata.panelShowAlbumArt
  }

  NToggle {
    label: I18n.tr("bar.media-mini.compact-mode-label")
    description: I18n.tr("bar.media-mini.compact-mode-description")
    checked: valueCompactMode
    onToggled: checked => {
      valueCompactMode = checked;
      saveSettings({compactMode: valueCompactMode});
    }
    defaultValue: widgetMetadata.compactMode
  }
}
