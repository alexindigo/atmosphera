import QtQuick
import qs.Commons
import qs.Services.Compositor
import qs.Services.Power
import qs.Services.UI

Item {
  id: root
  anchors.fill: parent

  property var screen
  property string resolvedWallpaperPath: ""
  property color fallbackColor: Color.mSurface

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
    target: WallpaperService
    function onWallpaperChanged(screenName, path) {
      if (screen && screenName === screen.name) {
        Qt.callLater(requestCachedWallpaper);
      }
    }
  }

  Connections {
    target: CompositorService
    function onDisplayScalesChanged() {
      if (screen && width > 0 && height > 0) {
        Qt.callLater(requestCachedWallpaper);
      }
    }
  }

  function requestCachedWallpaper() {
    if (!screen || width <= 0 || height <= 0) {
      return;
    }

    if (Settings.data.wallpaper.useSolidColor) {
      resolvedWallpaperPath = "";
      return;
    }

    var originalPath = WallpaperService.getWallpaper(screen.name) || "";
    if (originalPath === "") {
      resolvedWallpaperPath = "";
      return;
    }

    if (WallpaperService.isSolidColorPath(originalPath)) {
      resolvedWallpaperPath = "";
      return;
    }

    if (!ImageCacheService || !ImageCacheService.initialized) {
      resolvedWallpaperPath = originalPath;
      return;
    }

    var compositorScale = CompositorService.getDisplayScale(screen.name);
    var targetWidth = Math.round(width * compositorScale);
    var targetHeight = Math.round(height * compositorScale);
    if (targetWidth <= 0 || targetHeight <= 0) {
      return;
    }

    ImageCacheService.getLarge(originalPath, targetWidth, targetHeight, function (cachedPath, success) {
      resolvedWallpaperPath = success ? cachedPath : originalPath;
    });
  }

  Rectangle {
    anchors.fill: parent
    color: Settings.data.wallpaper.useSolidColor ? Settings.data.wallpaper.solidColor : root.fallbackColor
  }

  Image {
    id: bgImage
    visible: bgImage.source !== "" && Settings.data.wallpaper.enabled && !Settings.data.wallpaper.useSolidColor && (!PowerProfileService.atmospheraPerformanceMode || !Settings.data.atmospheraPerformance.disableWallpaper)
    anchors.fill: parent
    fillMode: Image.PreserveAspectCrop
    source: resolvedWallpaperPath
    cache: false
    smooth: true
    mipmap: false
  }
}
