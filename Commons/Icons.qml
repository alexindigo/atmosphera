pragma Singleton

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  // Expose the font family name for easy access (fallback for Noctalia compat)
  readonly property string fontFamily: currentFontLoader ? currentFontLoader.name : ""
  readonly property string defaultIcon: "circle-off"
  readonly property var icons: IconRegistry.resolved
  readonly property var aliases: ({})
  readonly property string fontPath: "/Assets/Fonts/tabler/atmosphera-tabler-icons.ttf"

  // Current active font loader (fallback for Noctalia compat)
  property FontLoader currentFontLoader: null
  property int fontVersion: 0

  readonly property string cacheBustingPath: Quickshell.shellDir + fontPath + "?v=" + fontVersion + "&t=" + Date.now()

  signal fontReloaded

  Component.onCompleted: {
    Logger.i("Icons", "Service started");
    loadFontWithCacheBusting();
  }

  Connections {
    target: Quickshell
    function onReloadCompleted() {
      Logger.d("Icons", "Quickshell reload completed - forcing font reload");
      reloadFont();
    }
  }

  function get(iconName) {
    var resolved = IconRegistry.resolved[iconName];
    return resolved ? resolved.char : undefined;
  }

  function loadFontWithCacheBusting() {
    if (currentFontLoader) {
      currentFontLoader.destroy();
      currentFontLoader = null;
    }

    currentFontLoader = Qt.createQmlObject(`
                                           import QtQuick
                                           FontLoader {
                                           source: "${cacheBustingPath}"
                                           }
                                           `, root, "dynamicFontLoader_" + fontVersion);

    currentFontLoader.statusChanged.connect(function () {
      if (currentFontLoader.status === FontLoader.Ready) {
        Logger.d("Icons", "Font loaded successfully:", currentFontLoader.name, "(version " + fontVersion + ")");
        fontReloaded();
      } else if (currentFontLoader.status === FontLoader.Error) {
        Logger.e("Icons", "Font failed to load (version " + fontVersion + ")");
      }
    });
  }

  function reloadFont() {
    fontVersion++;
    loadFontWithCacheBusting();
  }
}
