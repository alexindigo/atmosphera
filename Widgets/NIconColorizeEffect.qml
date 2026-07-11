import QtQuick
import Quickshell
import qs.Commons

ShaderEffect {
  id: root

  // Named mode constants
  readonly property int ModeDock: 0
  readonly property int ModeTray: 1
  readonly property int ModeDistro: 2
  readonly property int ModeHueReplace: 3

  // Shader controls
  property color targetColor: Color.mPrimary
  property real colorizeMode: root.ModeHueReplace
  property real blendStrength: 1.0
  property real hueAdjustment: 0.0

  fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
}
