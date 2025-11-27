import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons

/**
* CircularAvatarRenderer - Hidden window for rendering circular avatars
*
* This component safely uses ClippingRectangle in a separate hidden window to
* pre-render circular avatar images. The rendered images are saved as PNGs
* with transparent backgrounds, which can then be used in the UI without
* any shader effects (avoiding Qt 6.8 crashes).
*
* Usage:
*   var renderer = component.createObject(null, {
*     imagePath: "file:///path/to/avatar.png",
*     outputPath: "/path/to/output_circular.png",
*     username: "ItsLemmy"
*   });
*   renderer.renderComplete.connect(function(success) {
*     if (success) console.log("Rendered!");
*     renderer.destroy();
*   });
*/
PanelWindow {
  id: root

  // Input properties
  property string imagePath: ""
  property string outputPath: ""
  property string username: ""

  // Hidden window configuration
  implicitWidth: 256
  implicitHeight: 256
  visible: true // Must be visible for grabToImage to work
  color: "transparent"

  // Wayland configuration - hide it from user view
  WlrLayershell.layer: WlrLayer.Bottom // Render below everything
  WlrLayershell.exclusionMode: ExclusionMode.Ignore
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // Position it off-screen or behind everything
  anchors {
    left: true
    top: true
  }
  margins {
    left: -512// Off-screen to the left
    top: -512  // Off-screen to the top
  }

  signal renderComplete(bool success)

  // Use ClippingRectangle safely (not in GridView, not visible)
  ClippingRectangle {
    id: clipper
    anchors.fill: parent
    radius: width * 0.5 // Make it circular
    color: "transparent"

    Image {
      id: sourceImage
      anchors.fill: parent
      source: root.imagePath
      fillMode: Image.PreserveAspectCrop
      smooth: true
      mipmap: true
      asynchronous: true

      onStatusChanged: {
        if (status === Image.Ready) {
          // Image loaded successfully, capture it on next frame
          Qt.callLater(captureCircular);
        } else if (status === Image.Error) {
          Logger.e("CircularAvatarRenderer", "Failed to load image for", root.username);
          root.renderComplete(false);
        }
      }
    }
  }

  function captureCircular() {
    clipper.grabToImage(function (result) {
      if (result.saveToFile(root.outputPath)) {
        Logger.d("CircularAvatarRenderer", "Saved circular avatar for", root.username, "to", root.outputPath);
        root.renderComplete(true);
      } else {
        Logger.e("CircularAvatarRenderer", "Failed to save circular avatar for", root.username);
        root.renderComplete(false);
      }
    }, Qt.size(root.width, root.height));
  }
}
