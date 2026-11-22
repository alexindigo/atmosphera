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
  function imageItems(item) {
    var found = [];
    var walk = node => {
      if (!node)
        return;
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
    var service = Qt.createComponent("file://" + plugins + "/wallcards/src/ThumbnailService.qml");
    thumbnails = service.status === Component.Ready ? service.createObject(root, {
                                                                             cacheDir: Quickshell.env("IMAGE_OUTPUT") + "/unused-wallcards-cache",
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
    if (!root.thumbnailReady)
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
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (root.grabTick < 0 && root.tick >= 30 && root.settled()) {
        root.grabTick = root.tick;
        for (const row of root.created) {
          if (!row.object)
            continue;
          ++root.pending;
          row.object.grabToImage(result => {
            console.log("IMAGE_GRAB|" + JSON.stringify({
                                                         name: row.name,
                                                         saved: result.saveToFile(root.output + "/" + row.name + ".png")
                                                       }));
            --root.pending;
          });
        }
      }
      if (root.grabTick > 0 && root.tick > root.grabTick && root.tick <= root.grabTick + 9) {
        // Motion: frames of the sticker over time.
        var sticker = root.created.find(row => row.name === "sticker");
        if (sticker && sticker.object) {
          var name = "sticker-" + (root.tick - root.grabTick);
          ++root.pending;
          sticker.object.grabToImage(result => {
            console.log("IMAGE_GRAB|" + JSON.stringify({
                                                         name: name,
                                                         saved: result.saveToFile(root.output + "/" + name + ".png")
                                                       }));
            --root.pending;
          });
        }
      }
      if (root.grabTick > 0 && root.tick >= root.grabTick + 12 && !root.pending) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         settledTick: root.grabTick,
                                                         entries: root.created.map(row => ({
                                                           name: row.name,
                                                           error: row.error,
                                                           images: row.object ? root.imageItems(row.object) : []
                                                         })),
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
