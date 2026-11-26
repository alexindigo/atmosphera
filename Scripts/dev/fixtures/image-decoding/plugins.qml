import Qt.labs.folderlistmodel
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Actual plugin roots from the delivered plugins tree, created with the
// inputs their plugin normally provides (pluginApi stubs carry only data).
// Every owner-backed image item under each root is reported and grabbed.
ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  readonly property string plugins: Quickshell.env("IMAGE_PLUGINS")
  // Remote terminal output with image markup and every printable ASCII
  // character; hermes-ssh-chat escapes it all (orchestrator decision).
  readonly property string httpBase: Quickshell.env("IMAGE_HTTP_BASE")
  readonly property var terminalLines: [Array.from({
                                                     length: 95
                                                   }, (_, i) => String.fromCharCode(32 + i)).join(""), "<img src=\"" + httpBase + "/terminal.png\">", "![art](" + httpBase + "/terminal-md.png)", "<table background=\"" + httpBase + "/terminal-bg.png\"><tr><td>cell</td></tr></table>"]
  property int tick: 0
  property int pending: 0
  property var created: []
  property var thumbnailReady: false
  FileView {
    path: Quickshell.env("IMAGE_ICON_DIR") + "/icons.json"
    onLoaded: IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("IMAGE_ICON_DIR"))
  }
  function api(extra) {
    return Object.assign({
                           pluginSettings: ({}),
                           manifest: ({
                                        metadata: ({
                                                     defaultSettings: ({})
                                                   })
                                      }),
                           mainInstance: null,
                           tr: key => key,
                           saveSettings: () => {}
                         }, extra || {});
  }
  readonly property var entries: [
    {
      name: "kde-phone",
      file: "kde-connect/PhoneDisplay.qml",
      props: {
        width: 120,
        height: 220,
        backgroundImage: inputs + "/Still.webp"
      }
    },
    {
      name: "valent-phone",
      file: "valent-connect/PhoneDisplay.qml",
      props: {
        width: 120,
        height: 220,
        backgroundImage: inputs + "/Still.webp"
      }
    },
    {
      name: "clipboard-image",
      file: "clipboard/ClipboardItem.qml",
      props: {
        width: 300,
        height: 120,
        itemType: "image",
        entryId: "7",
        pluginApi: api({
                         mainInstance: {
                           imageCache: {
                             "7": "file://" + inputs + "/Misleading.png"
                           },
                           imageCacheRevision: 1,
                           getImage: function () {},
                           getFileMeta: function () {}
                         }
                       })
      }
    },
    {
      name: "sticker",
      file: "custom-sticker/DesktopWidget.qml",
      props: {
        pluginApi: api(),
        widgetData: {
          image: inputs + "/Motion.webp"
        }
      }
    },
    {
      name: "lwe-preview",
      file: "linux-wallpaperengine-controller/components/wallpaper/PreviewCard.qml",
      props: {
        width: 360,
        pluginApi: api(),
        selectedWallpaperData: {
          thumb: inputs + "/Still.webp",
          motionPreview: "",
          name: "Fixture",
          id: "1",
          // The plugin escapes descriptions; BBCode images become links.
          description: "Workshop [b]text[/b] [img]https://example.org/x.png[/img] <img src='" + inputs + "/frame-1.png'>"
        }
      }
    },
    {
      name: "lwe-motion",
      file: "linux-wallpaperengine-controller/components/wallpaper/PreviewCard.qml",
      props: {
        width: 360,
        pluginApi: api(),
        selectedWallpaperData: {
          thumb: "",
          motionPreview: inputs + "/Motion.webp",
          name: "Fixture",
          id: "2"
        }
      }
    },
    {
      name: "hermes-avatar",
      file: "hermes-agent/components/HermesAvatar.qml",
      props: {
        width: 48,
        height: 48,
        iconPath: inputs + "/Still.webp"
      }
    },
    {
      name: "hermes-avatar-failed",
      file: "hermes-agent/components/HermesAvatar.qml",
      props: {
        width: 48,
        height: 48,
        iconPath: inputs + "/Corrupt.webp"
      }
    },
    {
      name: "hermes-terminal",
      file: "hermes-ssh-chat/TerminalView.qml",
      props: {
        width: 900,
        height: 160,
        rawText: terminalLines.join("\r\n")
      }
    },
    {
      name: "chat-markdown",
      file: "assistant-panel/MessageBubble.qml",
      props: {
        width: 400,
        pluginApi: api(),
        message: {
          role: "assistant",
          content: "Here is art ![art](" + inputs + "/Still.webp) in a reply."
        }
      }
    }
  ]
  function plainText(item) {
    if (!item)
      return null;
    if ("getText" in item && "textFormat" in item)
      // Paragraph/line separators become newlines (the report is one log line).
      return item.getText(0, item.length).replace(/[\u2028\u2029]/g, "\n");
    for (var i = 0; item.children && i < item.children.length; ++i) {
      var found = plainText(item.children[i]);
      if (found !== null)
        return found;
    }
    return null;
  }
  function imageItems(item) {
    var found = [];
    var walk = node => {
      if (!node)
        return;
      // NImageRounded, including an upstream owner's failure without a URL.
      if ("sourceFailureCode" in node && "imagePath" in node)
        found.push({
                     kind: "rounded",
                     state: node.imageState,
                     code: node.errorCode,
                     reason: node.errorReason,
                     source: String(node.imagePath),
                     visible: node.visible
                   });
      if ("imageStates" in node && "parsedContent" in node) {
        found.push({
                     kind: "text",
                     states: node.imageStates,
                     count: node.imageCount
                   });
      } else if ("imageState" in node && "errorCode" in node && "source" in node) {
        found.push({
                     kind: "imageSource" in node ? "rounded" : "image",
                     state: node.imageState,
                     code: node.errorCode,
                     source: String(node.source),
                     frames: node.imageResult ? node.imageResult.frames || 0 : 0,
                     animated: node.imageResult ? !!node.imageResult.animated : false,
                     visible: node.visible
                   });
        return;
      }
      for (var i = 0; node.children && i < node.children.length; ++i)
        walk(node.children[i]);
    };
    walk(item);
    return found;
  }
  FloatingWindow {
    visible: true
    implicitWidth: 900
    implicitHeight: 1200
    color: "white"
    Flow {
      id: container
      anchors.fill: parent
      spacing: 8
    }
  }
  // mpvpaper and video-wallpaper: the actual video thumbnail producers over a
  // folder with one video and one broken file; video-wallpaper's actual
  // panel. The mpvpaper tile uses the same direct source as its delegate.
  // The settings and main stand-ins carry data and delegate to the producer.
  readonly property string videos: inputs + "/videos"
  property var mpvThumbs: null
  property var vwThumbs: null
  property var vwFolder: null
  property int videoPhase: 0
  property var failedVideo: ({})
  readonly property string redVideo: videos + "/Red.mp4"
  readonly property string badVideo: videos + "/Broken.mp4"
  QtObject {
    id: mpvSettings
    property string wallpapersFolder: root.videos
    property bool thumbCacheReady: false
    property bool active: true
    property string currentWallpaper: root.badVideo
  }
  QtObject {
    id: mpvMain
    readonly property bool thumbCacheReady: mpvSettings.thumbCacheReady
    function getThumbUrl(path) {
      return root.mpvThumbs ? root.mpvThumbs.getThumbUrl(path) : "";
    }
    function getThumbFailure(path) {
      return root.mpvThumbs ? root.mpvThumbs.getThumbFailure(path) : ({
                                                                        code: "",
                                                                        reason: ""
                                                                      });
    }
  }
  QtObject {
    id: vwMain
    function getThumbPath(path) {
      return root.vwThumbs ? root.vwThumbs.thumbnailFor(path) : "";
    }
    function getThumbFailure(path) {
      return root.vwThumbs ? root.vwThumbs.failureFor(path) : ({
                                                                 code: "",
                                                                 reason: ""
                                                               });
    }
  }
  FolderListModel {
    id: mpvFolder
    folder: "file://" + root.videos
    nameFilters: ["*.mp4"]
    showDirs: false
    onStatusChanged: if (status === FolderListModel.Ready && root.mpvThumbs)
                       root.mpvThumbs.thumbGeneration()
  }
  function createVideoProducers() {
    var mpv = Qt.createComponent("file://" + plugins + "/mpvpaper/main/Thumbnails.qml");
    mpvThumbs = mpv.status === Component.Ready ? mpv.createObject(root, {
                                                                    pluginApi: api({
                                                                                     pluginSettings: mpvSettings
                                                                                   }),
                                                                    active: true,
                                                                    settingsContext: mpvSettings,
                                                                    currentWallpaper: Qt.binding(() => mpvSettings.currentWallpaper),
                                                                    thumbCacheReady: Qt.binding(() => mpvSettings.thumbCacheReady),
                                                                    folderModel: mpvFolder
                                                                  }) : null;
    if (!mpvThumbs)
      console.log("IMAGE_PLUGIN_ERROR|" + mpv.errorString());
    else if (mpvFolder.status === FolderListModel.Ready)
      mpvThumbs.thumbGeneration();
    var tiles = Qt.createQmlObject("import QtQuick; Row { width: 640; height: 180; spacing: 8 }", container);
    for (const name of ["Broken.mp4", "Red.mp4"]) {
      const path = root.videos + "/" + name;
      const tile = Qt.createQmlObject("import qs.Widgets; NImageRounded { width: 300; height: 168; fallbackIcon: \"alert-circle\" }", tiles);
      tile.imagePath = path;
    }
    created.push({
                   name: "mpv-tiles",
                   object: mpvThumbs ? tiles : null,
                   error: mpvThumbs ? "" : mpv.errorString()
                 });
    var folder = Qt.createComponent("file://" + plugins + "/video-wallpaper/common/FolderModel.qml");
    vwFolder = folder.status === Component.Ready ? folder.createObject(root, {
                                                                         folder: root.videos,
                                                                         filters: ["*.mp4"]
                                                                       }) : null;
    var vw = Qt.createComponent("file://" + plugins + "/video-wallpaper/main/Thumbnails.qml");
    vwThumbs = vwFolder && vw.status === Component.Ready ? vw.createObject(root, {
                                                                             pluginApi: api({
                                                                                              pluginSettings: {
                                                                                                wallpapersFolder: root.videos
                                                                                              }
                                                                                            }),
                                                                             folderModel: vwFolder,
                                                                             requestedPaths: [root.badVideo]
                                                                           }) : null;
    var holder = Qt.createQmlObject("import QtQuick; Item { width: 880; height: 420 }", container);
    var panel = Qt.createComponent("file://" + plugins + "/video-wallpaper/panel/PerScreenPanel.qml");
    var object = vwThumbs && panel.status === Component.Ready ? panel.createObject(holder, {
                                                                                     pluginApi: api({
                                                                                                      mainInstance: vwMain
                                                                                                    }),
                                                                                     screenName: "fixture",
                                                                                     selectWallpaper: () => {},
                                                                                     writeMonitorSetting: () => {},
                                                                                     thumbCacheReady: Qt.binding(() => root.vwFolder.ready),
                                                                                     folderModel: vwFolder
                                                                                   }) : null;
    created.push({
                   name: "vw-panel",
                   object: object ? holder : null,
                   error: object ? "" : [folder.errorString(), vw.errorString(), panel.errorString()].join(" ")
                 });
  }
  // wallcards' thumbnails and colors from the shared owner.
  property var thumbnails: null
  Component.onCompleted: {
    for (const entry of entries) {
      var component = Qt.createComponent("file://" + plugins + "/" + entry.file);
      var object = component.status === Component.Ready ? component.createObject(container, entry.props) : null;
      created.push({
                     name: entry.name,
                     object: object,
                     error: object ? "" : component.errorString()
                   });
    }
    createVideoProducers();
    var service = Qt.createComponent("file://" + plugins + "/wallcards/src/ThumbnailService.qml");
    thumbnails = service.status === Component.Ready ? service.createObject(root, {
                                                                             imageFilter: ["png", "webp"],
                                                                             videoFilter: ["mp4"],
                                                                             wallpaperDir: inputs + "/wallcards"
                                                                           }) : null;
    if (!thumbnails)
      console.log("IMAGE_PLUGIN_ERROR|" + service.errorString());
    else
      thumbnails.ready.connect(() => root.thumbnailReady = true);
  }
  // Settled: no owner-backed image under any root is still loading, and the
  // wallcards thumbnails are done.
  function settled() {
    if (!root.thumbnailReady || root.videoPhase !== 1 || !mpvSettings.thumbCacheReady || !root.vwThumbs?.thumbCacheReady)
      return false;
    for (const row of root.created) {
      if (!row.object)
        continue;
      for (const image of root.imageItems(row.object)) {
        if (image.kind === "text" ? image.states.length < image.count || image.states.some(state => state.state === "loading" || !state.state) : image.state === "loading")
          return false;
      }
    }
    return true;
  }
  property int grabTick: -1
  function grab(item, name) {
    ++pending;
    if (item.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
    }))
      return true;
    --pending;
    console.error("Plugin grab rejected: " + name);
    Qt.exit(3);
    return false;
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (root.videoPhase === 0 && root.vwThumbs?.generationFailed && mpvSettings.thumbCacheReady && root.mpvThumbs.getThumbFailure(root.badVideo).code) {
        root.failedVideo = {
          mpv: root.mpvThumbs.getThumbFailure(root.badVideo),
          vw: root.vwThumbs.failureFor(root.badVideo)
        };
        root.videoPhase = 1;
        mpvSettings.currentWallpaper = root.redVideo;
        root.mpvThumbs.thumbGeneration();
        root.vwThumbs.requestedPaths = [root.redVideo];
      }
      if (root.grabTick < 0 && root.tick >= 30 && root.settled()) {
        root.grabTick = root.tick;
        for (const row of root.created) {
          if (!row.object)
            continue;
          if (!root.grab(row.object, row.name))
            return;
        }
      }
      if (root.grabTick > 0 && root.tick > root.grabTick && root.tick <= root.grabTick + 9) {
        // Motion: frames of the sticker over time.
        var sticker = root.created.find(row => row.name === "sticker");
        if (sticker && sticker.object && !root.grab(sticker.object, "sticker-" + (root.tick - root.grabTick)))
          return;
      }
      if (root.grabTick > 0 && root.tick >= root.grabTick + 12 && !root.pending) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         settledTick: root.grabTick,
                                                         entries: root.created.map(row => ({
                                                           name: row.name,
                                                           error: row.error,
                                                           images: row.object ? root.imageItems(row.object) : []
                                                         })),
                    terminal: root.plainText(root.created.find(row => row.name === "hermes-terminal").object),
                    terminalLines: root.terminalLines,
                    videos: {
                      mpvReady: mpvSettings.thumbCacheReady,
                      vwSettled: root.vwThumbs ? root.vwThumbs.settled : false,
                      vwReady: root.vwThumbs ? root.vwThumbs.thumbCacheReady : false,
                      failed: root.failedVideo,
                      mpvPath: root.mpvThumbs.getThumbPath(root.redVideo),
                      vwPath: root.vwThumbs.pathFor(root.redVideo),
                      obsoleteMpv: root.mpvThumbs.getThumbFailure(root.badVideo),
                      obsoleteVw: root.vwThumbs.failureFor(root.badVideo)
                    },
                    wallcards: root.thumbnails ? {
                                                   ready: root.thumbnailReady,
                                                   loading: root.thumbnails.loading,
                                                   files: root.thumbnails.files
                                                 } : null,
                    warningColor: [Math.round(AtmoColor.mError.r * 255), Math.round(AtmoColor.mError.g * 255), Math.round(AtmoColor.mError.b * 255), 255]
      }));
        Qt.quit();
      }
    }
  }
  Timer {
    interval: 80000
    running: true
    onTriggered: Qt.exit(3)
  }
}
