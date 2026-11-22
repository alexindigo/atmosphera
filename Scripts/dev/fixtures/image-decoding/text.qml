import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Changelog
import qs.Services
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
    implicitHeight: 1000
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
        id: styled
        width: 400
        color: "black"
        format: "styled"
        text: "line one\nline two <img src='" + root.inputs + "/Misleading.png' width='20' height='20'>"
      }
      NImageText {
        id: styledLight
        width: 120
        color: "black"
        format: "styled"
        elide: Text.ElideRight
        maximumLineCount: 1
        text: "<b>light</b> styled text that is long enough to be elided"
      }
      NImageText {
        id: plain
        width: 400
        color: "black"
        text: "Plain <b>text</b> only, no image work"
      }
      // Two lines shown: the image on the first line stays, the one on the
      // third line is cut off with its line. The frame is taller than the
      // text, so the grab would show anything drawn past the cut.
      Item {
        id: cappedFrame
        width: 300
        height: 140
        NImageText {
          id: capped
          width: 300
          color: "black"
          maximumLineCount: 2
          text: "first <img src='" + root.inputs + "/frame-1.png' width='24' height='24'> line<br>second line<br>third <img src='" + root.inputs + "/frame-0.png' width='24' height='24'> line"
        }
      }
      // Settings descriptions (plugin text) with and without an image.
      NLabel {
        id: label
        width: 300
        label: "Label"
        description: "desc <b>bold</b> <img src='" + root.inputs + "/frame-1.png' width='16' height='16'> end"
      }
      NLabel {
        id: labelPlain
        width: 300
        label: "Label"
        description: "plain <b>description</b>"
      }
      Rectangle {
        id: tipTarget
        width: 60
        height: 20
        color: "gray"
      }
      // Qt's rich text would fetch background images (attributes, style
      // attributes, style blocks) by itself, outside the owner. Not loaded;
      // the text stays. The runner's server records any fetch.
      NImageText {
        id: backgrounds
        width: 300
        color: "black"
        readonly property string http: Quickshell.env("IMAGE_TEXT_HTTP")
        text: "<link rel='stylesheet' href='" + http + "/sheet.css'><style>p.b { background-image: url('" + http + "/style-block.png') }</style><table background='" + http + "/table-attr.png' width='200' height='40'><tr><td style=\"background-image: url('" + http + "/td-style.png'); height: 30px\">cell text</td><td background='" + root.inputs
              + "/frame-0.png'>file</td></tr></table><p class='b'>styled paragraph</p>"

      }
    }
  }
  // The actual changelog panel content with notes that carry images: an
  // absolute fixture file and a source relative to the shipped changelog.
  FloatingWindow {
    visible: true
    implicitWidth: 520
    implicitHeight: 520
    color: "white"
    ChangelogContent {
      id: changelog
      anchors.fill: parent
    }
  }
  function imageTexts(item) {
    var found = [];
    var walk = node => {
      if (!node)
        return;
      if ("imageStates" in node && "parsedContent" in node)
        found.push(node);
      for (var i = 0; node.children && i < node.children.length; ++i)
        walk(node.children[i]);
    };
    walk(item);
    return found;
  }
  function tooltipText() {
    var tip = TooltipService.activeTooltip;
    return tip ? root.imageTexts(tip.contentItem)[0] || null : null;
  }
  function changelogText() {
    var found = [];
    var walk = item => {
      if ("imageStates" in item && "parsedContent" in item)
        found.push(item);
      for (var i = 0; item.children && i < item.children.length; ++i)
        walk(item.children[i]);
    };
    walk(changelog);
    return found.filter(item => item.imageCount > 0)[0] || null;
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (!root.notesSet && Version.changelogNotesLoaded && Version.versionKnown) {
        root.notesSet = true;
        // Release notes as the changelog owner holds them after parsing the
        // bundled file (set after its load, which would replace them).
        Version.changelogSections = [
              {
                version: "0.0.1",
                content: "## [0.0.1] - fixture\n\nNotes with art ![still](" + root.inputs + "/Still.webp) and a shipped asset ![talia](Assets/Talia/TaliaParty.png \"Talia\") in the text.\n\n- [a link](https://example.org/notes)\n"
              }
            ];
      }
      if (root.tick === 5)
        TooltipService.show(tipTarget, "tip <b>text</b>\n<img src='" + root.inputs + "/Still.webp' width='40' height='24'> after", "bottom", 1);
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
        root.grab(cappedFrame, "capped");
        root.grab(backgrounds, "backgrounds");
        if (root.changelogText())
          root.grab(root.changelogText(), "changelog");
        if (root.tooltipText())
          root.grab(root.tooltipText(), "tooltip");
        root.grab(root.imageTexts(label)[0], "label");
      }
      if (root.tick >= 70 && !root.pending) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         rich: root.describe(rich),
                                                         markdown: root.describe(markdown),
                                                         failing: root.describe(failing),
                                                         replaced: root.describe(replaced),
                                                         plain: root.describe(plain),
                                                         styled: root.describe(styled),
                                                         styledLight: Object.assign(root.describe(styledLight), {
                                                                                      lightweight: styledLight.lightweight,
                                                                                      truncated: styledLight.truncated
                                                                                    }),
                                                         capped: Object.assign(root.describe(capped), {
                                                                                 truncated: capped.truncated,
                                                                                 lineCount: capped.lineCount,
                                                                                 contentHeight: capped.contentHeight
                                                                               }),
                                                         backgrounds: root.describe(backgrounds),
                                                         tooltip: root.tooltipText() ? Object.assign(root.describe(root.tooltipText()), {
                                                                                                       popupWidth: TooltipService.activeTooltip.implicitWidth,
                                                                                                       popupHeight: TooltipService.activeTooltip.implicitHeight,
                                                                                                       popupVisible: TooltipService.activeTooltip.visible
                                                                                                     }) : {
                                                                                         missing: true
                                                                                       },
                                                         label: Object.assign(root.describe(root.imageTexts(label)[0]), {
                                                                                lightweight: root.imageTexts(label)[0].lightweight
                                                                              }),
                                                         labelPlain: Object.assign(root.describe(root.imageTexts(labelPlain)[0]), {
                                                                                     lightweight: root.imageTexts(labelPlain)[0].lightweight
                                                                                   }),
                                                         changelog: root.changelogText() ? Object.assign(root.describe(root.changelogText()), {
                                                                                                           format: root.changelogText().format,
                                                                                                           baseUrl: root.changelogText().baseUrl,
                                                                                                           releaseContent: Version.releaseContent
                                                                                                         }) : {
                                                                                             missing: true,
                                                                                             versionKnown: Version.versionKnown,
                                                                                             notesLoaded: Version.changelogNotesLoaded,
                                                                                             releaseContent: Version.releaseContent
                                                                                           },
                                                         interestSources: ImageCacheService.sourceInterestSources(),
                                                         warningColor: [Math.round(AtmoColor.mError.r * 255), Math.round(AtmoColor.mError.g * 255), Math.round(AtmoColor.mError.b * 255), 255]
                                                       }));
        Qt.quit();
      }
    }
  }
  property int interestsBeforePlain: 0
  property bool notesSet: false
  // As the shell does at startup: detect the installed version.
  Component.onCompleted: Version.init()
  Timer {
    interval: 20000
    running: true
    onTriggered: Qt.exit(3)
  }
}
