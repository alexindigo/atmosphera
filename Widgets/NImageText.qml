pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../Helpers/ImageTextSources.js" as ImageTextSources
import qs.Commons
import qs.Services.UI

// Rich text or Markdown that can carry images (notifications, changelog,
// plugin README/chat). Qt's text layout never loads the images: each one is
// a sized transparent slot in the text, and an NImage from the shared image
// owner is laid over the slot, so fallback decoding and animation work and a
// failure is a labelled placeholder. Links, styles and text flow stay Qt's.
// NText never decodes images; it is for shell-authored strings only.
Item {
  id: root

  property string text: ""
  // "rich" (Qt's HTML subset) or "markdown".
  property string format: "rich"
  // Base for relative image sources (for example a README's location).
  property string baseUrl: ""
  property color color: AtmoColor.mOnSurface
  property string family: Settings.data.ui.fontDefault
  property real pointSize: Style.fontSizeM
  property bool applyUiScale: true
  property int fontWeight: Style.fontWeightMedium
  property int wrapMode: TextEdit.Wrap
  property int horizontalAlignment: TextEdit.AlignLeft
  // 0: unlimited. Otherwise the text is cut after this many laid-out lines.
  property int maximumLineCount: 0
  property bool animationsPlaying: true

  readonly property font font: edit.font
  readonly property string hoveredLink: edit.hoveredLink
  readonly property real contentWidth: edit.contentWidth
  readonly property real contentHeight: edit.contentHeight
  readonly property int lineCount: edit.lineCount
  readonly property bool truncated: _clipHeight >= 0 && _clipHeight < edit.contentHeight
  readonly property int imageCount: parsedContent.images.length
  // Per image: { state, code, reason, x, y, width, height } for observers.
  readonly property var imageStates: _states

  signal linkActivated(string link)
  signal linkHovered(string link)

  function linkAt(x, y) {
    return edit.linkAt(x, y);
  }
  // Laid-out text; each image is U+FFFC.
  function plainText() {
    return edit.getText(0, edit.length);
  }

  readonly property string slotUrl: "file://" + Quickshell.shellDir + "/Assets/image-text-slot.png"
  readonly property var parsedContent: ImageTextSources.parse(text, format, baseUrl, slotUrl)
  property string _html: ""
  property var _order: []
  property var _sizes: []
  property var _states: []
  property var _geometry: []
  property real _clipHeight: -1

  implicitWidth: edit.implicitWidth
  implicitHeight: _clipHeight >= 0 ? Math.min(_clipHeight, edit.implicitHeight) : edit.implicitHeight
  clip: _clipHeight >= 0

  readonly property real _fontScale: {
    const scale = root.family === Settings.data.ui.fontDefault ? Settings.data.ui.fontDefaultScale : Settings.data.ui.fontFixedScale;
    return applyUiScale ? scale * Style.uiScaleRatio : scale;
  }
  readonly property real _lineSize: Math.max(8, Math.ceil(edit.font.pixelSize > 0 ? edit.font.pixelSize : edit.font.pointSize * 1.33))
  // Images never exceed the text width; their decode request is bounded by it.
  readonly property real imageMaximumWidth: Math.max(_lineSize, width > 0 ? width : 640)

  function _size(index) {
    var image = parsedContent.images[index];
    var state = _states[index] || {};
    var width = image.width;
    var height = image.height;
    if (state.state === "ready" && state.naturalWidth > 0 && state.naturalHeight > 0) {
      if (!width && !height) {
        width = state.naturalWidth;
        height = state.naturalHeight;
      } else if (!width) {
        width = Math.round(height * state.naturalWidth / state.naturalHeight);
      } else if (!height) {
        height = Math.round(width * state.naturalHeight / state.naturalWidth);
      }
    } else if (!width || !height) {
      // Loading or failed without declared size: a line-sized placeholder.
      width = width || _lineSize * 1.25;
      height = height || _lineSize * 1.25;
    }
    if (width > imageMaximumWidth) {
      height = height * imageMaximumWidth / width;
      width = imageMaximumWidth;
    }
    return {
      width: Math.max(1, Math.round(width)),
      height: Math.max(1, Math.round(height))
    };
  }

  function _relayout() {
    var sizes = [];
    for (var i = 0; i < parsedContent.images.length; ++i)
      sizes.push(_size(i));
    _sizes = sizes;
    var source = parsedContent.text;
    if (format === "markdown") {
      // Qt's own Markdown reading, then its HTML form, where slot sizes can
      // be declared. Font matches the visible text so spans keep it.
      converter.textFormat = TextEdit.MarkdownText;
      converter.text = source;
      converter.textFormat = TextEdit.RichText;
      source = converter.getFormattedText(0, converter.length);
      converter.text = "";
    }
    _html = ImageTextSources.sized(source, slotUrl, sizes);
    _order = ImageTextSources.order(_html, slotUrl);
    geometry.restart();
  }

  function _measure() {
    var plain = edit.getText(0, edit.length);
    var slots = [];
    for (var i = 0; i < plain.length; ++i) {
      if (plain.charCodeAt(i) === 0xFFFC)
        slots.push(i);
    }
    // The k-th object character is the k-th slot of the laid-out HTML.
    var position = {};
    for (var k = 0; k < Math.min(slots.length, _order.length); ++k)
      position[_order[k]] = slots[k];
    var placed = [];
    for (var n = 0; n < parsedContent.images.length; ++n) {
      var size = _sizes[n] || {
        width: 1,
        height: 1
      };
      if (position[n] !== undefined) {
        var rect = edit.positionToRectangle(position[n]);
        placed.push({
                      x: rect.x,
                      y: rect.y,
                      width: size.width,
                      height: size.height,
                      placed: true
                    });
      } else {
        placed.push({
                      x: 0,
                      y: 0,
                      width: 0,
                      height: 0,
                      placed: false
                    });
      }
    }
    if (slots.length !== _order.length || _order.length !== parsedContent.images.length)
      Logger.w("NImageText", "Laid out", slots.length, "of", parsedContent.images.length, "images");
    _geometry = placed;
    if (maximumLineCount > 0 && edit.lineCount > maximumLineCount) {
      // Bottom of the last allowed line: the first position whose line top
      // starts the next line.
      var tops = [];
      for (var p = 0; p <= edit.length; ++p) {
        var top = edit.positionToRectangle(p).y;
        if (!tops.length || top > tops[tops.length - 1] + 0.5)
          tops.push(top);
        if (tops.length > maximumLineCount)
          break;
      }
      _clipHeight = tops.length > maximumLineCount ? tops[maximumLineCount] : -1;
    } else {
      _clipHeight = -1;
    }
    _publishStates();
  }

  function _report(index, image) {
    if (!image || index >= parsedContent.images.length)
      return;
    var states = _states.slice();
    var result = image.imageResult || {};
    var before = states[index] || {};
    states[index] = {
      state: image.imageState,
      code: image.errorCode,
      reason: image.errorReason,
      naturalWidth: image.imageState === "ready" ? result.width || 0 : 0,
      naturalHeight: image.imageState === "ready" ? result.height || 0 : 0,
      frames: image.imageState === "ready" ? result.frames || 1 : 0
    };
    _states = states;
    if (before.state !== states[index].state || before.naturalWidth !== states[index].naturalWidth)
      relayout.restart();
  }

  function _publishStates() {
    var states = _states.slice();
    for (var i = 0; i < _geometry.length; ++i)
      states[i] = Object.assign({}, states[i] || {}, _geometry[i]);
    _states = states;
  }

  onParsedContentChanged: {
    _states = [];
    relayout.restart();
  }
  onImageMaximumWidthChanged: relayout.restart()
  onFormatChanged: relayout.restart()
  onMaximumLineCountChanged: geometry.restart()
  Component.onCompleted: _relayout()

  Timer {
    id: relayout
    interval: 0
    onTriggered: root._relayout()
  }
  Timer {
    id: geometry
    interval: 0
    onTriggered: root._measure()
  }

  TextEdit {
    id: converter
    visible: false
    width: root.width
    font: edit.font
    readOnly: true
  }

  TextEdit {
    id: edit
    width: root.width
    readOnly: true
    selectByMouse: false
    activeFocusOnPress: false
    textFormat: TextEdit.RichText
    text: root._html
    color: root.color
    wrapMode: root.wrapMode
    horizontalAlignment: root.horizontalAlignment
    font.family: root.family
    font.pointSize: Math.max(1, root.pointSize * root._fontScale)
    font.weight: root.fontWeight
    onLinkActivated: link => root.linkActivated(link)
    onLinkHovered: link => root.linkHovered(link)
    onContentSizeChanged: geometry.restart()
    onFontChanged: relayout.restart()
    onWidthChanged: geometry.restart()
    HoverHandler {
      cursorShape: edit.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
  }

  // Images over their slots. No input handlers: clicks reach the text, so an
  // image inside a link activates the link.
  Repeater {
    model: root.parsedContent.images.length
    Item {
      id: slot
      required property int index
      readonly property var image: root.parsedContent.images[index] || {}
      readonly property var place: root._geometry[index] || {}
      x: place.x || 0
      y: place.y || 0
      width: place.width || 0
      height: place.height || 0
      visible: !!place.placed

      NImage {
        id: picture
        anchors.fill: parent
        source: slot.image.source || ""
        animationIntent: "preserve"
        fillMode: Image.Stretch
        imageTransform: "contain"
        sourceSize: Qt.size(Math.ceil(root.imageMaximumWidth * Screen.devicePixelRatio), Math.ceil(root.imageMaximumWidth * Screen.devicePixelRatio))
        paused: !root.animationsPlaying || !root.visible || Settings.data.general.animationDisabled
        // Read the settled result after the state notification (the failure
        // reason is published after the state).
        onImageStateChanged: Qt.callLater(() => root._report(slot.index, picture))
        Component.onCompleted: root._report(slot.index, picture)
        Accessible.role: Accessible.Graphic
        Accessible.name: slot.image.alt || slot.image.title || ""
      }

      // Unavailable or empty source: a labelled placeholder, never nothing.
      Rectangle {
        anchors.fill: parent
        visible: picture.imageState === "unavailable" || !slot.image.source
        color: "transparent"
        radius: Math.min(width, height) / 6
        border.width: 1
        border.color: AtmoColor.mError
        Accessible.role: Accessible.Graphic
        Accessible.name: slot.image.alt || I18n.tr("widgets.file-picker.preview-unavailable")
        Accessible.description: picture.errorReason || I18n.tr("widgets.file-picker.preview-unavailable")

        AtmoIcon {
          anchors.centerIn: parent
          icon: "photo-off"
          pointSize: Math.max(1, Math.min(parent.width, parent.height) * 0.45)
          applyUiScale: false
          color: AtmoColor.mError
        }
        HoverHandler {
          onHoveredChanged: {
            if (hovered)
              TooltipService.show(parent, (slot.image.alt ? slot.image.alt + ": " : "") + (picture.errorReason || I18n.tr("widgets.file-picker.preview-unavailable")));
            else
              TooltipService.hide();
          }
        }
      }
    }
  }
}
