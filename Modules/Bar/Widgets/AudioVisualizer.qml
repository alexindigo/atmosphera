import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Audio
import qs.Services
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  // Resolve settings: try user settings or defaults from BarWidgetRegistry
  readonly property int visualizerWidth: widgetSettings.width !== undefined ? widgetSettings.width : widgetMetadata.width

  implicitWidth: visualizerWidth
  implicitHeight: Style.capsuleHeight

  Rectangle {
    id: background
    anchors.fill: parent
    radius: Style.radiusS
    color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent
  }

  // Store visualizer type to force re-evaluation
  readonly property string currentVisualizerType: Settings.data.audio.visualizerType

  // Timer to delay reload
  Timer {
    id: reloadTimer
    interval: 50
    onTriggered: {
      visualizerLoader.active = true
    }
  }

  // Force reload when visualizer type changes
  onCurrentVisualizerTypeChanged: {
    visualizerLoader.active = false
    reloadTimer.restart()
  }

  // The Loader dynamically loads the appropriate visualizer based on settings
  Loader {
    id: visualizerLoader
    anchors.fill: parent
    anchors.margins: Style.marginS
    active: false
    asynchronous: false

    sourceComponent: {
      switch (currentVisualizerType) {
      case "linear":
        return linearComponent
      case "mirrored":
        return mirroredComponent
      case "wave":
        return waveComponent
      default:
        return null
      }
    }
  }

  // Click to cycle through visualizer types
  MouseArea {
    id: mouseArea
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    onClicked: mouse => {
                 const types = ["linear", "mirrored", "wave"]
                 const currentIndex = types.indexOf(currentVisualizerType)
                 const nextIndex = (currentIndex + 1) % types.length
                 const newType = types[nextIndex]

                 // Update settings directly
                 Settings.data.audio.visualizerType = newType
               }
  }

  // Initial activation on component complete
  Component.onCompleted: {
    if (currentVisualizerType !== "" && currentVisualizerType !== "none") {
      visualizerLoader.active = true
    }
  }

  Component {
    id: linearComponent
    LinearSpectrum {
      anchors.fill: parent
      values: CavaService.values
      showMinimumSignal: true
      fillColor: Color.mPrimary
    }
  }

  Component {
    id: mirroredComponent
    MirroredSpectrum {
      anchors.fill: parent
      values: CavaService.values
      showMinimumSignal: true
      fillColor: Color.mPrimary
    }
  }

  Component {
    id: waveComponent
    WaveSpectrum {
      anchors.fill: parent
      values: CavaService.values
      showMinimumSignal: true
      fillColor: Color.mPrimary
    }
  }
}
