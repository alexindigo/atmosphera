import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

// NImageText: HTML and Markdown images (inline, block, reference, inline
// HTML inside Markdown, relative and literal paths, repeated, replaced,
// failing, animated), links over images, code that only looks like images,
// and plain text without image work.
ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  readonly property string base: "file://" + inputs + "/"
  property int tick: 0
  property int pending: 0
  property var linkClicks: []
  property var motion: []
  FileView {
    path: Quickshell.env("IMAGE_ICON_DIR") + "/icons.json"
    onLoaded: IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("IMAGE_ICON_DIR"))
  }
  function grab(item, name) {
    ++pending;
    item.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
    });
  }
  function describe(item) {
    var states = item.imageStates.map(state => Object.assign({}, state, {
                                                               link: state.placed ? item.linkAt(state.x + state.width / 2, state.y + state.height / 2) : ""
                                                             }));
    return {
      // Line and paragraph separators as newlines: the log is read by line.
      plain: item.plainText().replace(/[\u2028\u2029]/g, "\n"),
      imageCount: item.imageCount,
      states: states,
      width: item.width,
      height: item.height
    };
  }
  FloatingWindow {
    visible: true
    implicitWidth: 820
    implicitHeight: 620
    color: "white"
    Column {
      spacing: 10
      NImageText {
        id: rich
        width: 400
        color: "black"
        baseUrl: root.base
        text: "A <b>bold</b> <a href='https://example.org/x'>link <img src='Misleading.png' width='32' height='24'></a> tail<br><img src=\"./bracket[0]: image.webp\" width=\"24\" height=\"16\"> again <img src='Misleading.png' width='32' height='24'><!-- <img src='nope.png'> -->"
      }
      NImageText {
        id: markdown
        width: 400
        color: "black"
        format: "markdown"
        baseUrl: root.base
        text: "# Title\n\nText *em* ![still](Still.webp \"t\") and <img src=\"Misleading.png\" width=\"20\" height=\"20\"> inline\n\n![moving][m]\n\n`![code](nope.png)` and \\![escaped](nope.png)\n\n    ![indented](nope.png)\n\n[m]: <Motion.webp>\n"
      }
      NImageText {
        id: failing
        width: 400
        color: "black"
        text: "before <img src='" + root.inputs + "/Corrupt.webp' alt='broken art' width='30' height='30'> after"
      }
      NImageText {
        id: replaced
        width: 400
        color: "black"
        property bool second: false
        text: "swap <img src='" + root.inputs + (second ? "/frame-1.png" : "/Still.svg") + "' width='40' height='30'>"
      }
      NImageText {
        id: plain
        width: 400
        color: "black"
        text: "Plain <b>text</b> only, no image work"
      }
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (root.tick === 30) {
        root.grab(replaced, "replaced-before");
        root.interestsBeforePlain = ImageCacheService.sourceInterestSources().length;
      }
      if (root.tick === 33)
        replaced.second = true;
      if (root.tick >= 40 && root.tick <= 60) {
        var moving = (markdown.imageStates[2] || {});
        if (moving.placed)
          root.grab(markdown, "markdown-" + root.tick);
      }
      if (root.tick === 45) {
        root.grab(rich, "rich");
        root.grab(failing, "failing");
        root.grab(replaced, "replaced-after");
      }
      if (root.tick >= 70 && !root.pending) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         rich: root.describe(rich),
                                                         markdown: root.describe(markdown),
                                                         failing: root.describe(failing),
                                                         replaced: root.describe(replaced),
                                                         plain: root.describe(plain),
                                                         interestSources: ImageCacheService.sourceInterestSources(),
                                                         warningColor: [Math.round(AtmoColor.mError.r * 255), Math.round(AtmoColor.mError.g * 255), Math.round(AtmoColor.mError.b * 255), 255]
                                                       }));
        Qt.quit();
      }
    }
  }
  property int interestsBeforePlain: 0
  Timer {
    interval: 20000
    running: true
    onTriggered: Qt.exit(3)
  }
}
