import QtQuick
import Quickshell
import Quickshell.Io
import "../../Helpers/WallpaperSelection.js" as WallpaperSelection

// A lock consumes the shell's wallpaper cache. It must not start directory
// scans, downloads, automation, theme generation or registry initialization.
Scope {
  id: root
  required property string cacheFile
  required property bool darkMode
  required property bool useSolidColor
  required property string solidColor
  property bool isInitialized: false
  signal wallpaperChanged(string screenName, string path)

  function getWallpaper(name) {
    if (useSolidColor)
      return "solid://" + solidColor;
    return WallpaperSelection.select(cache.wallpapers, Quickshell.screens, name, darkMode, cache.defaultWallpaper);
  }

  function isSolidColorPath(path) { return typeof path === "string" && path.startsWith("solid://"); }

  function notify() {
    if (!isInitialized)
      return;
    for (var screen of Quickshell.screens)
      wallpaperChanged(screen.name, getWallpaper(screen.name));
  }

  onDarkModeChanged: notify()
  onUseSolidColorChanged: notify()
  onSolidColorChanged: notify()

  FileView {
    path: root.cacheFile
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    adapter: JsonAdapter {
      id: cache
      property var wallpapers: ({})
      property string defaultWallpaper: ""
    }
    onLoaded: { root.isInitialized = true; root.notify(); }
    onLoadFailed: { root.isInitialized = true; root.notify(); }
  }
}
