import QtQuick
import qs.Commons
import qs.Services.Compositor
import qs.Widgets

Item {
  id: pillContainer

  required property var workspace
  required property bool isVertical

  // These must be provided by the parent Workspace widget
  required property real baseDimensionRatio
  required property real capsuleHeight
  required property string labelMode
  required property int characterCount
  required property real textRatio
  required property bool showLabelsOnlyWhenOccupied
  required property var colorMap
  required property string focusedColor
  required property string occupiedColor
  required property string emptyColor
  required property real masterProgress
  required property bool effectsActive
  required property color effectColor
  required property var getWorkspaceWidth
  required property var getWorkspaceHeight

  // Fixed dimension (cross-axis)
  readonly property real fixedDimension: Style.toOdd(capsuleHeight * baseDimensionRatio)

  // Fixed dimension set directly, varying dimension handled by states
  width: isVertical ? fixedDimension : getWorkspaceWidth(workspace, false)
  height: isVertical ? getWorkspaceHeight(workspace, false) : fixedDimension

  states: [
    State {
      name: "active"
      when: workspace.isActive
      PropertyChanges {
        target: pillContainer
        width: isVertical ? fixedDimension : getWorkspaceWidth(workspace, true)
        height: isVertical ? getWorkspaceHeight(workspace, true) : fixedDimension
      }
    }
  ]

  transitions: [
    Transition {
      from: "inactive"
      to: "active"
      NumberAnimation {
        property: isVertical ? "height" : "width"
        duration: Style.animationNormal
        easing.type: Easing.OutBack
      }
    },
    Transition {
      from: "active"
      to: "inactive"
      NumberAnimation {
        property: isVertical ? "height" : "width"
        duration: Style.animationNormal
        easing.type: Easing.OutBack
      }
    }
  ]

  Rectangle {
    id: pill
    anchors.fill: parent
    radius: Style.radiusM
    z: 0

    color: {
      if (workspace.isFocused)
        return colorMap[focusedColor][0];
      if (workspace.isUrgent)
        return Color.mError;
      if (workspace.isOccupied)
        return colorMap[occupiedColor][0];
      return Qt.alpha(colorMap[emptyColor][0], 0.3);
    }

    Loader {
      active: (labelMode !== "none") && (!showLabelsOnlyWhenOccupied || workspace.isOccupied || workspace.isFocused)
      sourceComponent: Component {
        NText {
          x: Style.pixelAlignCenter(pill.width, width)
          y: Style.pixelAlignCenter(pill.height, height)
          text: {
            if (workspace.name && workspace.name.length > 0) {
              if (labelMode === "name") {
                return workspace.name.substring(0, characterCount);
              }
              if (labelMode === "index+name") {
                // Vertical mode: compact format (no space, first char only)
                // Horizontal mode: full format (space, more chars)
                if (isVertical) {
                  return workspace.idx.toString() + workspace.name.substring(0, 1);
                }
                return workspace.idx.toString() + " " + workspace.name.substring(0, characterCount);
              }
            }
            return workspace.idx.toString();
          }
          family: Settings.data.ui.fontFixed
          // Size based on the fixed dimension (cross-axis)
          pointSize: (isVertical ? pillContainer.width : pillContainer.height) * textRatio
          applyUiScale: false
          font.capitalization: Font.AllUppercase
          font.weight: Style.fontWeightBold
          wrapMode: Text.Wrap
          color: {
            if (workspace.isFocused)
              return colorMap[focusedColor][1];
            if (workspace.isUrgent)
              return Color.mOnError;
            if (workspace.isOccupied)
              return colorMap[occupiedColor][1];
            return colorMap[emptyColor][1];
          }
        }
      }
    }

    MouseArea {
      id: pillMouseArea
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true
      onClicked: {
        CompositorService.switchToWorkspace(workspace);
      }
    }

    // Material 3-inspired smooth animations
    Behavior on scale {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutBack
      }
    }
    Behavior on color {
      enabled: !Color.isTransitioning
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.InOutCubic
      }
    }
    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationFast
        easing.type: Easing.InOutCubic
      }
    }
    Behavior on radius {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutBack
      }
    }
  }

  Behavior on width {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutBack
    }
  }
  Behavior on height {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutBack
    }
  }

  // Burst effect overlay for focused pill
  Rectangle {
    id: pillBurst
    anchors.centerIn: pillContainer
    width: pillContainer.width + 18 * masterProgress * scale
    height: pillContainer.height + 18 * masterProgress * scale
    radius: width / 2
    color: "transparent"
    border.color: effectColor
    border.width: Math.max(1, Math.round((2 + 6 * (1.0 - masterProgress))))
    opacity: effectsActive && workspace.isFocused ? (1.0 - masterProgress) * 0.7 : 0
    visible: effectsActive && workspace.isFocused
    z: 1
  }
}
