import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Files
import qs.Modules.FileChooser

ShellRoot {
  id: root
  property string mode: "icon"
  property string tag: "initial"
  property string background: "#1e1e1e"
  property int size: 96
  property bool faded: false
  property bool started: false
  property bool recording: false
  property bool grabbing: false
  property int requestedFrames: 0
  property bool terminalRequested: false
  property var samples: []
  property var frames: []
  property string saved: ""
  property string mediaPath: ""
  property string mediaName: "Media.mp4"
  property var descriptor: ({type: "folder", group: "folder", folder: "ordinary", hidden: false})
  readonly property string output: Quickshell.env("FILECHOOSER_RENDER_OUTPUT")
  FileThumbnails { id: thumbnails }
  PanelWindow {
    id: panel
    anchors.top: true
    anchors.left: true
    implicitWidth: 400
    implicitHeight: 240
    color: root.background
    Rectangle {
      id: canvas
      anchors.fill: parent
      color: root.background
      FileIcon {
        id: icon
        x: 20; y: 40
        width: root.size; height: root.size
        compact: root.size === 20
        visible: root.mode === "icon"
        descriptor: Object.assign({}, root.descriptor, {hidden: root.faded})
      }
      Rectangle {
        id: entryCanvas
        x: 20; y: 20
        width: 200; height: 170
        color: root.background
        visible: root.mode === "entry"
        Loader {
          id: entryLoader
          anchors.fill: parent
          active: root.mode === "entry"
          sourceComponent: FileEntry {
            name: (root.faded ? "." : "") + root.mediaName
            path: root.mediaPath
            directory: false
            bytes: 0
            modified: "fixture"
            thumbnailProvider: thumbnails
            thumbnailActive: root.started
          }
        }
      }
    }
  }
  function entryState() {
    return entryLoader.item ? entryLoader.item.thumbnailState : {};
  }
  function snapshot() {
    return JSON.stringify({ready: Settings.isLoaded, tag: tag, mode: mode, hidden: faded, size: size,
      saved: saved, grabbing: grabbing, samples: samples, frames: frames,
      thumbnail: entryState(), geometry: entryLoader.item ? entryLoader.item.artworkGeometry() : {},
      light: icon.paints.highlight.toString(), uiScale: Style.uiScaleRatio});
  }
  Timer {
    interval: 8
    repeat: true
    running: root.recording && !!entryLoader.item
    onTriggered: {
      var t = root.entryState();
      var sample = {time: Date.now(), ready: t.imageReady, reveal: t.reveal, fallbackOpacity: t.fallbackOpacity,
        opacity: t.opacity, duration: t.duration, artworkOpacity: t.artworkOpacity};
      root.samples = root.samples.slice(-249).concat([sample]);
      if (t.imageReady && t.reveal > .05 && t.reveal < .75 && !root.grabbing && root.requestedFrames < 3) {
        root.grabbing = true;
        var file = root.output + "/" + root.tag + "-mid-" + (++root.requestedFrames) + ".png";
        // As in ImageCacheService: capture the real scene, including the opaque
        // backdrop, rather than reimplement its alpha arithmetic in the fixture.
        entryCanvas.grabToImage(function(result) {
          var success = result.saveToFile(file);
          root.frames = root.frames.concat([{file: file, before: sample, after: root.entryState(), saved: success}]);
          root.grabbing = false;
        });
      }
      if (t.imageReady && t.reveal === 1 && !root.grabbing && !root.terminalRequested) {
        root.terminalRequested = true;
        var complete = root.output + "/" + root.tag + "-complete.png";
        entryCanvas.grabToImage(function(result) { result.saveToFile(complete); });
      }
    }
  }
  IpcHandler {
    target: "filechooserRender"
    function state(): string { return root.snapshot(); }
    function palette(text: string): void {
      AtmoColor.skipTransition = true;
      var colors = JSON.parse(text);
      for (var key of Object.keys(colors))
        if (key.startsWith("m")) AtmoColor[key] = colors[key];
      root.background = colors.mSurface;
    }
    function configure(text: string): void {
      var data = JSON.parse(text);
      root.recording = false;
      root.mode = "icon";
      root.started = false;
      root.saved = "";
      root.samples = [];
      root.frames = [];
      root.requestedFrames = 0;
      root.terminalRequested = false;
      root.tag = data.tag;
      root.size = data.size || 96;
      root.faded = data.hidden || false;
      root.descriptor = data.descriptor || root.descriptor;
      root.mediaPath = data.path || "";
      root.mediaName = data.name || "Media.mp4";
      Settings.data.general.animationDisabled = data.reduced || false;
      root.mode = data.mode || "icon";
    }
    function hidden(value: bool): void { root.faded = value; }
    function capture(file: string): void {
      canvas.grabToImage(function(result) { if (result.saveToFile(file)) root.saved = file; });
    }
    function start(): void { root.recording = true; root.started = true; }
    function stopRecording(): void { root.recording = false; }
    function quit(): void { thumbnails.enabled = false; Qt.quit(); }
  }
}
