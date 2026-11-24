import QtQuick
import qs.Commons
import qs.Services.Power
import qs.Services.UI

Item {
  id: root
  anchors.fill: parent

  property var screen
  property var wallpaperProvider: WallpaperService
  readonly property real displayScale: screen?.devicePixelRatio ?? 1
  onDisplayScaleChanged: Qt.callLater(requestCachedWallpaper)
  readonly property string resolvedWallpaperPath: bgImage.outputUrl
  readonly property string imageState: bgImage.imageState
  readonly property string errorReason: bgImage.errorReason
  property string requestedWallpaperPath: ""
  property color fallbackColor: AtmoColor.mSurface

  Component.onCompleted: {
    if (screen) {
      Qt.callLater(requestCachedWallpaper);
    }
  }

  onScreenChanged: {
    if (screen && width > 0 && height > 0) {
      Qt.callLater(requestCachedWallpaper);
    }
  }

  onWidthChanged: {
    if (screen && width > 0 && height > 0) {
      Qt.callLater(requestCachedWallpaper);
    }
  }

  onHeightChanged: {
    if (screen && width > 0 && height > 0) {
      Qt.callLater(requestCachedWallpaper);
    }
  }

  Connections {
    target: root.wallpaperProvider
    function onWallpaperChanged(screenName, path) {
      if (screen && screenName === screen.name) {
        Qt.callLater(requestCachedWallpaper);
      }
    }
  }

  // The current-wallpaper map loads asynchronously from the cache file;
  // fresh processes (e.g. the bundled locker) request before it's in.
  Connections {
    target: root.wallpaperProvider
    function onIsInitializedChanged() {
      if (root.wallpaperProvider.isInitialized && screen)
        Qt.callLater(requestCachedWallpaper);
    }
  }

  function requestCachedWallpaper() {
    if (!screen || width <= 0 || height <= 0) {
      return;
    }

    if (Settings.data.wallpaper.useSolidColor) {
      requestedWallpaperPath = "";
      return;
    }

    var originalPath = wallpaperProvider.getWallpaper(screen.name) || "";
    if (originalPath === "") {
      requestedWallpaperPath = "";
      return;
    }

    if (wallpaperProvider.isSolidColorPath(originalPath)) {
      requestedWallpaperPath = "";
      return;
    }

    requestedWallpaperPath = originalPath;
  }

  Rectangle {
    anchors.fill: parent
    color: Settings.data.wallpaper.useSolidColor ? Settings.data.wallpaper.solidColor : root.fallbackColor
  }

  NImageBackdrop {
    id: bgImage
    visible: bgImage.source !== "" && Settings.data.wallpaper.enabled && !Settings.data.wallpaper.useSolidColor && (!PowerProfileService.atmospheraPerformanceMode || !Settings.data.atmospheraPerformance.disableWallpaper)
    anchors.fill: parent
    fillMode: Image.PreserveAspectCrop
    source: root.requestedWallpaperPath
    normalize: !Settings.data.wallpaper.useOriginalImages
    sourceSize: Qt.size(Math.max(1, Math.round(width * root.displayScale)), Math.max(1, Math.round(height * root.displayScale)))
    active: visible
    smooth: true
    onImageStateChanged: {
      if (imageState === "unavailable")
        Logger.w("Wallpaper", errorReason);
    }
  }
}
