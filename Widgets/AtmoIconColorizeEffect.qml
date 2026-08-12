import QtQuick
import Quickshell
import qs.Commons

ShaderEffect {
  id: root

  // Named mode constants
  readonly property int modeDock: 0
  readonly property int modeTray: 1
  readonly property int modeDistro: 2
  readonly property int modeHueReplace: 3

  // Shader controls
  property color targetColor: Color.mPrimary
  property real colorizeMode: root.modeHueReplace
  property real blendStrength: 1.0
  property real hueAdjustment: 0.0

  fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
}
