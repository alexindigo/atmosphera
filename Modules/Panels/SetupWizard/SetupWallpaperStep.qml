import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Portals
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  property string selectedDirectory: ""
  property string selectedWallpaper: ""
  property string previewCachedPath: ""
  property var _previewRequest: null
  property int _previewGeneration: 0
  property string previewState: "idle"
  property string errorReason: ""

  signal directoryChanged(string directory)
  signal wallpaperChanged(string wallpaper)

  onSelectedWallpaperChanged: {
    if (selectedWallpaper !== previewCachedPath) {
      requestPreview(selectedWallpaper, false);
    } else {
      retirePreview();
      errorReason = "";
      previewState = selectedWallpaper && visible ? "ready" : "idle";
    }
  }
  onVisibleChanged: if (!visible)
                      retirePreview()
                    else if (selectedWallpaper !== previewCachedPath)
                      requestPreview(selectedWallpaper, false)
  Component.onDestruction: retirePreview()

  spacing: Style.marginL

  // Preview requests have this step's lifetime, not the singleton's lifetime.
  // A failed candidate keeps the last validated preview and user selection.
  function selectWallpaper(path) {
    requestPreview(path, true);
  }
  function retirePreview() {
    ++_previewGeneration;
    _previewRequest?.cancel();
    _previewRequest = null;
  }
  function requestPreview(path, userSelection) {
    retirePreview();
    errorReason = "";
    previewState = path && visible ? "loading" : "idle";
    if (!path && !userSelection)
      previewCachedPath = "";
    if (previewState !== "loading")
      return;
    const generation = _previewGeneration;
    _previewRequest = ImageCacheService.validateLocalImage(path, (output, success, detail) => {
      if (root._previewGeneration !== generation)
        return;
      root._previewRequest = null;
      root.errorReason = success ? "" : detail.reason;
      root.previewState = success ? "ready" : "unavailable";
      if (success) {
        root.previewCachedPath = output;
        if (userSelection) {
          root.selectedWallpaper = path;
          root.wallpaperChanged(path);
        }
      }
    });
  }

  // Large preview area
  Rectangle {
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 180
    color: AtmoColor.mSurfaceVariant
    radius: Style.radiusL

    // Image with rounded corners
    NImageRounded {
      anchors.fill: parent
      visible: previewCachedPath !== ""
      imagePath: previewCachedPath
      radius: Style.radiusL
      borderColor: previewCachedPath !== "" ? AtmoColor.mPrimary : AtmoColor.mOutline
      borderWidth: previewCachedPath !== "" ? 2 : 1
      imageFillMode: Image.PreserveAspectCrop
      animationIntent: "still"
      active: root.visible
    }

    AtmoIcon {
      id: previewWarning
      objectName: "wallpaperPreviewWarning"
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.marginS
      visible: root.previewState === "unavailable"
      icon: Icon.warning
      color: AtmoColor.mError
      Accessible.name: I18n.tr("widgets.file-picker.preview-unavailable")
      Accessible.description: root.errorReason
      HoverHandler {
        onHoveredChanged: {
          if (hovered)
            TooltipService.show(previewWarning, I18n.tr("widgets.file-picker.preview-unavailable") + ": " + root.errorReason);
          else
            TooltipService.hide();
        }
      }
    }

    ColumnLayout {
      anchors.centerIn: parent
      spacing: Style.marginL
      visible: selectedWallpaper === ""

      Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 64
        height: 64
        radius: width / 2
        color: AtmoColor.mPrimary

        AtmoIcon {
          icon: Icon.featured
          pointSize: Style.fontSizeXXL
          color: AtmoColor.mOnPrimary
          anchors.centerIn: parent
        }
      }

      NText {
        text: I18n.tr("setup.wallpaper.select-prompt")
        pointSize: Style.fontSizeL
        color: AtmoColor.mOnSurfaceVariant
        Layout.alignment: Qt.AlignHCenter
        font.weight: Style.fontWeightMedium
      }
    }

    Behavior on border.color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }
  }

  // Wallpaper gallery strip
  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 92
    visible: filteredWallpapers.length > 0

    NScrollView {
      id: galleryScroll
      anchors.fill: parent
      horizontalPolicy: ScrollBar.AsNeeded
      verticalPolicy: ScrollBar.AlwaysOff
      showGradientMasks: false
      reserveScrollbarSpace: false

      // Enable vertical mouse wheel to scroll the horizontal strip by moving contentX
      WheelHandler {
        target: galleryScroll.contentItem
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
          const flick = galleryScroll.contentItem;
          if (!flick)
            return;
          const delta = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0 ? (event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.pixelDelta.x) : (event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x);
          // Move opposite of wheel to scroll content to the right for wheel down
          const step = -delta;
          const maxX = Math.max(0, flick.contentWidth - flick.width);
          let newX = flick.contentX + step;
          if (newX < 0)
            newX = 0;
          if (newX > maxX)
            newX = maxX;
          flick.contentX = newX;
          event.accepted = true;
        }
      }

      RowLayout {
        spacing: Style.marginM
        height: parent.height

        Repeater {
          model: filteredWallpapers
          delegate: Item {
            id: thumbDelegate
            readonly property int baseWidth: 120
            readonly property int baseHeight: 80
            readonly property int thumbRadius: Style.radiusM

            Layout.preferredWidth: baseWidth
            Layout.preferredHeight: baseHeight

            // Static, lifetime-bound shared thumbnail; recognition is not success.
            NImageRounded {
              id: thumbImage
              anchors.fill: parent
              imagePath: modelData
              animationIntent: "still"
              normalize: true
              active: root.visible
              radius: thumbDelegate.thumbRadius
              borderColor: selectedWallpaper === modelData ? AtmoColor.mPrimary : AtmoColor.mOutline
              borderWidth: selectedWallpaper === modelData ? 2 : 1
              imageFillMode: Image.PreserveAspectCrop
              fallbackIcon: "image"
              fallbackIconSize: Style.fontSizeL
            }

            // Loading state; NImageRounded owns the fallback and warning on error.
            Rectangle {
              anchors.fill: parent
              color: AtmoColor.mSurfaceVariant
              radius: thumbDelegate.thumbRadius
              visible: thumbImage.status === Image.Loading

              AtmoIcon {
                icon: Icon.image
                pointSize: Style.fontSizeL
                color: AtmoColor.mOnSurfaceVariant
                anchors.centerIn: parent
              }
            }

            NBusyIndicator {
              anchors.centerIn: parent
              visible: thumbImage.status === Image.Loading
              running: visible
              size: 18
            }

            // Hover overlay
            Rectangle {
              anchors.fill: parent
              radius: thumbDelegate.thumbRadius
              color: AtmoColor.mPrimary
              opacity: hoverHandler.hovered ? 0.1 : 0
              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }
            }

            // Selection badge
            Rectangle {
              visible: selectedWallpaper === modelData
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 6
              width: 24
              height: 24
              radius: width / 2
              color: AtmoColor.mPrimary

              AtmoIcon {
                icon: Icon.check
                pointSize: Style.fontSizeS
                color: AtmoColor.mOnPrimary
                anchors.centerIn: parent
              }
            }

            HoverHandler {
              id: hoverHandler
            }

            TapHandler {
              onTapped: {
                root.selectWallpaper(modelData);
              }
            }
          }
        }
      }
    }
  }

  // Helpful info card
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 80
    color: AtmoColor.mSurfaceVariant
    radius: Style.radiusM
    opacity: 0.4
    visible: filteredWallpapers.length === 0

    RowLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      AtmoIcon {
        icon: Icon.folderOpen
        pointSize: Style.fontSizeL
        color: AtmoColor.mOnSurfaceVariant
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS
        NText {
          text: filteredWallpapers.length === 0 && selectedDirectory !== "" ? I18n.tr("setup.wallpaper.none-in-dir") : I18n.tr("setup.wallpaper.no-dir")
          pointSize: Style.fontSizeM
          font.weight: Style.fontWeightBold
          color: AtmoColor.mOnSurfaceVariant
        }
        NText {
          text: selectedDirectory !== "" ? I18n.tr("setup.wallpaper.no-valid", {
                                                     "dir": selectedDirectory
                                                   }) : I18n.tr("setup.wallpaper.choose-dir")
          pointSize: Style.fontSizeS
          color: AtmoColor.mOnSurfaceVariant
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
          opacity: 0.8
        }
      }
    }
  }

  // Directory selection
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NTextInputButton {
      id: wallpaperPathInput
      label: I18n.tr("setup.wallpaper.dir-label")
      description: I18n.tr("setup.wallpaper.dir-description")
      text: selectedDirectory
      buttonIcon: "folder-open"
      buttonTooltip: I18n.tr("setup.wallpaper.dir-browse")
      Layout.fillWidth: true
      onInputTextChanged: text => {
        selectedDirectory = text;
        directoryChanged(text);
      }
      onButtonClicked: directoryPicker.open()
    }
  }

  // Internal properties and functions
  property list<string> wallpapersList: []
  property list<string> filteredWallpapers: []

  function updateFilteredWallpapers() {
    filteredWallpapers = wallpapersList;
  }

  function refreshWallpapers() {
    if (!selectedDirectory || selectedDirectory === "") {
      wallpapersList = [];
      filteredWallpapers = [];
      return;
    }
    if (typeof WallpaperService !== "undefined" && WallpaperService.getWallpapersList) {
      var wallpapers = WallpaperService.getWallpapersList(Screen.name);
      wallpapersList = wallpapers;
      updateFilteredWallpapers();
      if (wallpapersList.length > 0 && selectedWallpaper === "") {
        selectedWallpaper = wallpapersList[0];
      }
    } else {
      readDirectoryImages(selectedDirectory);
    }
  }

  function readDirectoryImages(directoryPath) {
    // Build find command args dynamically from ImageCacheService filters
    var filters = ImageCacheService.imageFilters;
    var findArgs = ["find", directoryPath, "-type", "f", "("];
    for (var i = 0; i < filters.length; i++) {
      if (i > 0) {
        findArgs.push("-o");
      }
      findArgs.push("-iname");
      findArgs.push(filters[i]);
    }
    findArgs.push(")");
    directoryScanner.command = findArgs;
    directoryScanner.running = true;
    return [];
  }

  onSelectedDirectoryChanged: {
    // A bound/initial selection is presentation, not user intent. The wizard
    // owns preference changes through directoryChanged and wallpaperChanged.
    Qt.callLater(refreshWallpapers);
  }

  Connections {
    target: WallpaperService
    enabled: typeof WallpaperService !== "undefined"
    function onWallpaperListChanged(screenName, count) {
      if (screenName === Screen.name) {
        Qt.callLater(refreshWallpapers);
      }
    }
  }

  Timer {
    id: initialRefreshTimer
    interval: 1000
    running: false
    repeat: false
    onTriggered: refreshWallpapers()
  }

  Component.onCompleted: {
    if (typeof Settings !== "undefined" && Settings.data && Settings.data.wallpaper && Settings.data.wallpaper.directory) {
      selectedDirectory = Settings.data.wallpaper.directory;
    } else {
      selectedDirectory = Quickshell.env("HOME") + "/Pictures/Wallpapers";
    }
    if (typeof WallpaperService !== "undefined" && WallpaperService.currentWallpaper) {
      selectedWallpaper = WallpaperService.currentWallpaper;
    }
    initialRefreshTimer.start();
  }

  PortalFilePicker {
    id: directoryPicker
    selectionMode: "folders"
    title: I18n.tr("setup.wallpaper.dir-select-title")
    initialPath: selectedDirectory || Quickshell.env("HOME") + "/Pictures"
    onAccepted: paths => {
      if (paths.length > 0) {
        selectedDirectory = paths[0];
        directoryChanged(paths[0]);
      }
    }
  }

  Process {
    id: directoryScanner
    command: []
    running: false
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function (exitCode) {
      if (exitCode === 0) {
        var lines = stdout.text.split('\n');
        var images = [];
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim();
          if (line !== '') {
            images.push(line);
          }
        }
        wallpapersList = images;
        updateFilteredWallpapers();
        if (wallpapersList.length > 0 && selectedWallpaper === "") {
          selectedWallpaper = wallpapersList[0];
        }
      }
    }
  }
}
