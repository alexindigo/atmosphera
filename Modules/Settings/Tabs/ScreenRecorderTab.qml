import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  spacing: Style.marginL * scaling

  NHeader {
    label: I18n.tr("settings.screen-recorder.general.section.label")
    description: I18n.tr("settings.screen-recorder.general.section.description")
  }

  // Output Folder
  ColumnLayout {
    spacing: Style.marginS * scaling
    Layout.fillWidth: true

    NTextInputButton {
      label: I18n.tr("settings.screen-recorder.general.output-folder.label")
      description: I18n.tr("settings.screen-recorder.general.output-folder.description")
      placeholderText: Quickshell.env("HOME") + "/Videos"
      text: Settings.data.screenRecorder.directory
      buttonIcon: "folder-open"
      buttonTooltip: I18n.tr("settings.screen-recorder.general.output-folder.tooltip")
      onInputEditingFinished: Settings.data.screenRecorder.directory = text
      onButtonClicked: folderPicker.open()
    }

    // Show Cursor
    NToggle {
      label: I18n.tr("settings.screen-recorder.general.show-cursor.label")
      description: I18n.tr("settings.screen-recorder.general.show-cursor.description")
      checked: Settings.data.screenRecorder.showCursor
      onToggled: checked => Settings.data.screenRecorder.showCursor = checked
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Video Settings
  ColumnLayout {
    spacing: Style.marginL * scaling
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.screen-recorder.video.section.label")
      description: I18n.tr("settings.screen-recorder.video.section.description")
    }

    // Source
    NComboBox {
      label: I18n.tr("settings.screen-recorder.video.video-source.label")
      description: I18n.tr("settings.screen-recorder.video.video-source.description")
      model: [
        {
          key: "portal",
          name: I18n.tr("options.screen-recording.sources.portal")
        },
        {
          key: "screen",
          name: I18n.tr("options.screen-recording.sources.screen")
        }
      ]
      currentKey: Settings.data.screenRecorder.videoSource
      onSelected: key => Settings.data.screenRecorder.videoSource = key
    }

    // Frame Rate
    NComboBox {
      label: I18n.tr("settings.screen-recorder.video.frame-rate.label")
      description: I18n.tr("settings.screen-recorder.video.frame-rate.description")
      model: ListModel {
        ListElement {
          key: "30"
          name: "30 FPS"
        }
        ListElement {
          key: "60"
          name: "60 FPS"
        }
        ListElement {
          key: "100"
          name: "100 FPS"
        }
        ListElement {
          key: "120"
          name: "120 FPS"
        }
        ListElement {
          key: "144"
          name: "144 FPS"
        }
        ListElement {
          key: "165"
          name: "165 FPS"
        }
        ListElement {
          key: "240"
          name: "240 FPS"
        }
      }
      currentKey: Settings.data.screenRecorder.frameRate
      onSelected: key => Settings.data.screenRecorder.frameRate = key
    }

    // Video Quality
    NComboBox {
      label: I18n.tr("settings.screen-recorder.video.video-quality.label")
      description: I18n.tr("settings.screen-recorder.video.video-quality.description")
      model: ListModel {
        ListElement {
          key: "medium"
          name: "Medium"
        }
        ListElement {
          key: "high"
          name: "High"
        }
        ListElement {
          key: "very_high"
          name: "Very high"
        }
        ListElement {
          key: "ultra"
          name: "Ultra"
        }
      }
      currentKey: Settings.data.screenRecorder.quality
      onSelected: key => Settings.data.screenRecorder.quality = key
    }

    // Video Codec
    NComboBox {
      label: I18n.tr("settings.screen-recorder.video.video-codec.label")
      description: I18n.tr("settings.screen-recorder.video.video-codec.description")
      model: ListModel {
        ListElement {
          key: "h264"
          name: "H264"
        }
        ListElement {
          key: "hevc"
          name: "HEVC"
        }
        ListElement {
          key: "av1"
          name: "AV1"
        }
        ListElement {
          key: "vp8"
          name: "VP8"
        }
        ListElement {
          key: "vp9"
          name: "VP9"
        }
      }
      currentKey: Settings.data.screenRecorder.videoCodec
      onSelected: key => Settings.data.screenRecorder.videoCodec = key
    }

    // Color Range
    NComboBox {
      label: I18n.tr("settings.screen-recorder.video.color-range.label")
      description: I18n.tr("settings.screen-recorder.video.color-range.description")
      model: ListModel {
        ListElement {
          key: "limited"
          name: "Limited"
        }
        ListElement {
          key: "full"
          name: "Full"
        }
      }
      currentKey: Settings.data.screenRecorder.colorRange
      onSelected: key => Settings.data.screenRecorder.colorRange = key
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Audio Settings
  ColumnLayout {
    spacing: Style.marginL * scaling
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.screen-recorder.audio.section.label")
      description: I18n.tr("settings.screen-recorder.audio.section.description")
    }

    // Audio Source
    NComboBox {
      label: I18n.tr("settings.screen-recorder.audio.audio-source.label")
      description: I18n.tr("settings.screen-recorder.audio.audio-source.description")
      model: ListModel {
        ListElement {
          key: "default_output"
          name: "System output"
        }
        ListElement {
          key: "default_input"
          name: "Microphone input"
        }
        ListElement {
          key: "both"
          name: "System output + microphone input"
        }
      }
      currentKey: Settings.data.screenRecorder.audioSource
      onSelected: key => Settings.data.screenRecorder.audioSource = key
    }

    // Audio Codec
    NComboBox {
      label: I18n.tr("settings.screen-recorder.audio.audio-codec.label")
      description: I18n.tr("settings.screen-recorder.audio.audio-codec.description")
      model: ListModel {
        ListElement {
          key: "opus"
          name: "Opus"
        }
        ListElement {
          key: "aac"
          name: "AAC"
        }
      }
      currentKey: Settings.data.screenRecorder.audioCodec
      onSelected: key => Settings.data.screenRecorder.audioCodec = key
    }
  }

  NFilePicker {
    id: folderPicker
    pickerType: "folder"
    title: I18n.tr("settings.screen-recorder.general.select-output-folder")
    initialPath: Settings.data.screenRecorder.directory || Quickshell.env("HOME") + "/Videos"
    onAccepted: paths => Settings.data.screenRecorder.directory = paths[0]
  }
}
