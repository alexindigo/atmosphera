import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Services.Media
import qs.Widgets
import qs.Widgets.AudioSpectrum

Item {
  id: root

  property ShellScreen screen
  property var widgetData: null
  property int widgetIndex: -1

  property bool isDragging: false
  property real dragOffsetX: 0
  property real dragOffsetY: 0
  property real baseX: (widgetData && widgetData.x !== undefined) ? widgetData.x : 100
  property real baseY: (widgetData && widgetData.y !== undefined) ? widgetData.y : 200

  readonly property bool showPrev: hasPlayer && MediaService.canGoPrevious
  readonly property bool showNext: hasPlayer && MediaService.canGoNext
  readonly property int visibleButtonCount: 1 + (showPrev ? 1 : 0) + (showNext ? 1 : 0)
  readonly property int baseWidth: 400 * Style.uiScaleRatio
  readonly property int buttonWidth: 32 * Style.uiScaleRatio
  readonly property int buttonSpacing: Style.marginXS
  readonly property int controlsWidth: visibleButtonCount * buttonWidth + (visibleButtonCount > 1 ? (visibleButtonCount - 1) * buttonSpacing : 0)

  implicitWidth: baseWidth - (3 - visibleButtonCount) * (buttonWidth + buttonSpacing)
  implicitHeight: contentLayout.implicitHeight + Style.marginM * 2
  width: implicitWidth
  height: implicitHeight

  x: isDragging ? dragOffsetX : baseX
  y: isDragging ? dragOffsetY : baseY
  
  // Update base position from widgetData when not dragging
  onWidgetDataChanged: {
    if (!isDragging) {
      baseX = (widgetData && widgetData.x !== undefined) ? widgetData.x : 100;
      baseY = (widgetData && widgetData.y !== undefined) ? widgetData.y : 200;
    }
  }

  readonly property bool hasPlayer: MediaService.currentPlayer !== null
  readonly property bool isPlaying: MediaService.isPlaying

  property color textColor: Color.mOnSurface
  Rectangle {
    anchors.fill: parent
    anchors.margins: -Style.marginS
    color: Settings.data.desktopWidgets.editMode ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.1) : "transparent"
    border.color: (Settings.data.desktopWidgets.editMode || isDragging) ? (isDragging ? Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5) : Color.mPrimary) : "transparent"
    border.width: Settings.data.desktopWidgets.editMode ? 3 : (isDragging ? 2 : 0)
    radius: Style.radiusL + Style.marginS
    z: -1
  }

  // Material 3 styled container with elevation
  Rectangle {
    id: container
    anchors.fill: parent
    radius: Style.radiusL
    color: Color.mSurface
    border {
      width: 1
      color: Qt.alpha(Color.mOutline, 0.12)
    }
    clip: true
    visible: (widgetData && widgetData.showBackground !== undefined) ? widgetData.showBackground : true

    Item {
      anchors.fill: parent
      anchors.margins: Style.marginXS
      z: 0
      clip: true
      layer.enabled: true
      layer.smooth: true
      layer.samples: 4
      layer.effect: MultiEffect {
        maskEnabled: true
        maskThresholdMin: 0.95
        maskSpreadAtMin: 0.0
        maskSource: ShaderEffectSource {
          sourceItem: Rectangle {
            width: container.width - Style.marginXS * 2
            height: container.height - Style.marginXS * 2
            radius: Math.max(0, Style.radiusL - Style.marginXS)
            color: "white"
            antialiasing: true
            smooth: true
          }
          smooth: true
          mipmap: true
        }
      }

      Loader {
        anchors.fill: parent
        active: (widgetData && widgetData.visualizerType) && widgetData.visualizerType !== "" && widgetData.visualizerType !== "none"

        sourceComponent: {
          var visualizerType = (widgetData && widgetData.visualizerType) ? widgetData.visualizerType : "";
          switch (visualizerType) {
          case "linear":
            return linearComponent;
          case "mirrored":
            return mirroredComponent;
          case "wave":
            return waveComponent;
          default:
            return null;
          }
        }

        Component {
          id: linearComponent
          NLinearSpectrum {
            anchors.fill: parent
            values: CavaService.values
            fillColor: Color.mPrimary
            opacity: 0.6
          }
        }

        Component {
          id: mirroredComponent
          NMirroredSpectrum {
            anchors.fill: parent
            values: CavaService.values
            fillColor: Color.mPrimary
            opacity: 0.6
          }
        }

        Component {
          id: waveComponent
          NWaveSpectrum {
            anchors.fill: parent
            values: CavaService.values
            fillColor: Color.mPrimary
            opacity: 0.6
          }
        }
      }
    }

    layer.enabled: Settings.data.general.enableShadows && !root.isDragging && ((widgetData && widgetData.showBackground !== undefined) ? widgetData.showBackground : true)
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowBlur: Style.shadowBlur * 1.5
      shadowOpacity: Style.shadowOpacity * 0.6
      shadowColor: Color.black
      shadowHorizontalOffset: Settings.data.general.shadowOffsetX
      shadowVerticalOffset: Settings.data.general.shadowOffsetY
      blurMax: Style.shadowBlurMax
    }
  }

  MouseArea {
    id: dragArea
    anchors.fill: parent
    z: 1
    enabled: Settings.data.desktopWidgets.editMode
    cursorShape: enabled && isDragging ? Qt.ClosedHandCursor : (enabled ? Qt.OpenHandCursor : Qt.ArrowCursor)
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    propagateComposedEvents: true
    
    property point pressPos: Qt.point(0, 0)
    property bool isDraggingWidget: false

    onPressed: mouse => {
      // Don't start drag if clicking on control buttons
      var clickX = mouse.x;
      var clickY = mouse.y;
      
      var buttonArea = controlsRow.mapToItem(root, 0, 0);
      var buttonWidth = controlsRow.width;
      var buttonHeight = controlsRow.height;
      
      if (clickX >= buttonArea.x && clickX <= buttonArea.x + buttonWidth &&
          clickY >= buttonArea.y && clickY <= buttonArea.y + buttonHeight) {
        mouse.accepted = false;
        return;
      }
      
      pressPos = Qt.point(mouse.x, mouse.y);
      dragOffsetX = root.x;
      dragOffsetY = root.y;
      isDragging = true;
      isDraggingWidget = true;
      // Update base position to current position when starting drag
      baseX = root.x;
      baseY = root.y;
    }

    onPositionChanged: mouse => {
      if (isDragging && isDraggingWidget && pressed) {
        var globalPos = mapToItem(root.parent, mouse.x, mouse.y);
        var newX = globalPos.x - pressPos.x;
        var newY = globalPos.y - pressPos.y;
        
        if (root.parent && root.width > 0 && root.height > 0) {
          newX = Math.max(0, Math.min(newX, root.parent.width - root.width));
          newY = Math.max(0, Math.min(newY, root.parent.height - root.height));
        }
        
        if (root.parent && root.parent.checkCollision && root.parent.checkCollision(root, newX, newY)) {
          return;
        }
        
        dragOffsetX = newX;
        dragOffsetY = newY;
      }
    }

    onReleased: mouse => {
      if (isDragging && widgetIndex >= 0) {
        var widgets = Settings.data.desktopWidgets.widgets.slice();
        if (widgetIndex < widgets.length) {
          widgets[widgetIndex] = Object.assign({}, widgets[widgetIndex], {
            "x": dragOffsetX,
            "y": dragOffsetY
          });
          Settings.data.desktopWidgets.widgets = widgets;
        }
        // Update base position to final position
        baseX = dragOffsetX;
        baseY = dragOffsetY;
        isDragging = false;
        isDraggingWidget = false;
      }
    }

    onCanceled: {
      isDragging = false;
      isDraggingWidget = false;
    }
  }

  RowLayout {
    id: contentLayout
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginS
    z: 1

    Item {
      Layout.preferredWidth: 64 * Style.uiScaleRatio
      Layout.preferredHeight: 64 * Style.uiScaleRatio
      Layout.alignment: Qt.AlignVCenter

      NImageRounded {
        visible: hasPlayer
        anchors.fill: parent
        radius: width / 2
        imagePath: MediaService.trackArtUrl
        fallbackIcon: isPlaying ? "media-pause" : "media-play"
        fallbackIconSize: 20 * Style.uiScaleRatio
        borderWidth: 0
      }

      NIcon {
        visible: !hasPlayer
        anchors.centerIn: parent
        icon: "disc"
        pointSize: 24
        color: Color.mOnSurfaceVariant
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      NText {
        Layout.fillWidth: true
        text: hasPlayer ? (MediaService.trackTitle || "Unknown Track") : "No media playing"
        pointSize: Style.fontSizeS
        font.weight: Style.fontWeightSemiBold
        color: Color.mOnSurface
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      NText {
        visible: hasPlayer && MediaService.trackArtist
        Layout.fillWidth: true
        text: MediaService.trackArtist || ""
        pointSize: Style.fontSizeXS
        font.weight: Style.fontWeightRegular
        color: Color.mOnSurfaceVariant
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }

    RowLayout {
      id: controlsRow
      spacing: Style.marginXS
      z: 10

      NIconButton {
        visible: showPrev
        baseSize: 32
        icon: "media-prev"
        enabled: hasPlayer && MediaService.canGoPrevious
        colorBg: Color.mSurfaceVariant
        colorFg: enabled ? Color.mPrimary : Color.mOnSurfaceVariant
        onClicked: {
          if (enabled) MediaService.previous();
        }
      }

      NIconButton {
        baseSize: 36
        icon: isPlaying ? "media-pause" : "media-play"
        enabled: hasPlayer && (MediaService.canPlay || MediaService.canPause)
        colorBg: Color.mPrimary
        colorFg: Color.mOnPrimary
        colorBgHover: Qt.lighter(Color.mPrimary, 1.1)
        colorFgHover: Color.mOnPrimary
        onClicked: {
          if (enabled) {
            MediaService.playPause();
          }
        }
      }

      NIconButton {
        visible: showNext
        baseSize: 32
        icon: "media-next"
        enabled: hasPlayer && MediaService.canGoNext
        colorBg: Color.mSurfaceVariant
        colorFg: enabled ? Color.mPrimary : Color.mOnSurfaceVariant
        onClicked: {
          if (enabled) MediaService.next();
        }
      }
    }
  }
}

