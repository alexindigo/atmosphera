import QtQuick
import Quickshell
import Quickshell.Io
import "../../../Helpers/WallpaperSelection.js" as Selection
import qs.Services.Locker

ShellRoot {
  id: root
  property bool dark: false
  property bool solid: false
  property int changes: 0
  property int checks: 0
  readonly property string screenName: Quickshell.screens[0].name

  function check(actual, expected) {
    if (actual !== expected)
      throw new Error("wallpaper-selection: " + actual + " != " + expected);
    checks++;
  }
  Component.onCompleted: {
    check(Selection.effective(null, false), "");
    check(Selection.effective("legacy", false), "legacy");
    check(Selection.effective("legacy", true), "legacy");
    check(Selection.effective({
                                light: "light",
                                dark: "dark"
                              }, false), "light");
    check(Selection.effective({
                                light: "light",
                                dark: "dark"
                              }, true), "dark");
    check(Selection.effective({
                                light: "light"
                              }, true), "light");
    check(Selection.effective({
                                dark: "dark"
                              }, false), "dark");
    check(Selection.effective({}, true), "");
    var screens = [
          {
            name: "first"
          },
          {
            name: "second"
          }
        ];
    check(Selection.select({
                             first: "own",
                             second: "other"
                           }, screens, "first", false, "fallback"), "own");
    check(Selection.select({
                             second: {
                               dark: "inherited"
                             }
                           }, screens, "first", true, "fallback"), "inherited");
    check(Selection.select({
                             disconnected: "ignored"
                           }, screens, "first", false, "fallback"), "fallback");
    check(Selection.select({}, screens, "first", false, ""), "");
  }
  LockWallpaper {
    id: reader
    cacheFile: Quickshell.env("LOCKER_WALLPAPER_CACHE")
    darkMode: root.dark
    useSolidColor: root.solid
    solidColor: "#123456"
    onWallpaperChanged: (name, path) => {
      if (name === root.screenName)
        root.changes++;
    }
  }
  IpcHandler {
    target: "wallpaperProof"
    function status(): string {
      return JSON.stringify({
                              ready: reader.isInitialized,
                              name: root.screenName,
                              path: reader.getWallpaper(root.screenName),
                              changes: root.changes,
                              checks: root.checks,
                              solidPath: reader.isSolidColorPath(reader.getWallpaper(root.screenName))
                            });
    }
    function appearance(dark: bool, solid: bool): void {
      root.dark = dark;
      root.solid = solid;
    }
    function exit(): void {
      Qt.quit();
    }
  }
}
