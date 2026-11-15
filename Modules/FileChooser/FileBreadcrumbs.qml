import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.Files
import qs.Widgets

Item {
  id: root
  required property var browser
  property Item focusOwner: null
  readonly property bool menuOpen: folders.visible
  readonly property var menuEntries: folders.entries
  function menuGeometry() { return folders.geometry(); }
  readonly property bool compact: naturalWidth(browser.breadcrumbs.slice(-3), browser.breadcrumbs.length > 3) > width
  readonly property real minimumWidth: naturalWidth(browser.breadcrumbs.slice(-1), browser.breadcrumbs.length > 1, 120 * Style.uiScaleRatio)
  readonly property var items: {
    var all = browser.breadcrumbs, limit = compact ? 1 : 3;
    return all.length > limit ? [{name: "...", path: "", kind: "ancestors"}].concat(all.slice(-limit).map(part => Object.assign({kind: "segment"}, part))) : all.map(part => Object.assign({kind: "segment"}, part));
  }
  signal editRequested()
  implicitHeight: Math.ceil(Style.baseWidgetSize * 1.1 * Style.uiScaleRatio)
  NText { id: typography; visible: false; pointSize: Style.fontSizeM }
  NText { id: leafMeasure; visible: false; text: root.browser.breadcrumbs.length ? root.browser.breadcrumbs[root.browser.breadcrumbs.length - 1].name : ""; pointSize: Style.fontSizeM }
  FontMetrics { id: metrics; font: typography.font }
  function naturalWidth(entries, overflow, labelLimit) {
    var labels = entries.map(e => e.name);
    if (overflow) labels.unshift("...");
    // The leaf's Text includes glyph overhang, unlike advanceWidth(). Include
    // the layout gap before the trailing edit slot as well as between crumbs.
    return labels.reduce((sum, name) => sum + Math.ceil(Math.min(name === leafMeasure.text ? leafMeasure.implicitWidth : metrics.advanceWidth(name), labelLimit === undefined ? Infinity : labelLimit)) + Style.margin2S + implicitHeight + Style.marginXS, 0) + labels.length * Style.marginXS + Style.marginM;
  }
  function dismissMenu() { folders.close(); }
  function geometry() {
    var result = [];
    for (var i = 0; i < items.length - 1; i++) {
      var part = parts.itemAt(i);
      var a = part.edges(), b = parts.itemAt(i + 1).edges();
      result.push({before: a.arrowLeft - a.right, after: b.left - a.arrowRight, clipped: a.clipped || b.clipped, labels: [a.label, b.label]});
    }
    return result;
  }
  function controls() {
    var result = [];
    for (var i = 0; i < items.length; i++) result = result.concat(parts.itemAt(i).controls());
    var p = emptySpace.mapToItem(root, 0, 0);
    result.push({x: p.x, y: p.y, width: emptySpace.width, height: emptySpace.height, name: emptySpace.Accessible.name, kind: "edit"});
    return result;
  }
  function showFolders(path, anchor) {
    childrenOf.basePath = path;
    childrenOf.active = true;
    childrenOf.schedule();
    folders.returnFocus = anchor;
    folders.parent = anchor;
    folders.y = anchor.height;
    folders.open();
  }
  FileCompletion { id: childrenOf; directoriesOnly: true; showHidden: root.browser.showHidden }
  ChooserMenu {
    id: folders
    title: I18n.tr("widgets.file-picker.folders")
    entries: childrenOf.active ? childrenOf.suggestions : root.browser.breadcrumbs
    onTriggered: entry => root.browser.navigate(entry.path)
  }
  RowLayout {
    id: line
    anchors.fill: parent
    spacing: Style.marginXS
    Repeater {
      id: parts
      // Keep focus-owning controls alive as the path or available width changes.
      // Replacing a repeater model during a focus handoff destroys its owner.
      model: 4
      RowLayout {
        id: part
        required property int index
        readonly property var modelData: root.items[index] || {name: "", path: "", kind: "unused"}
        visible: index < root.items.length
        Layout.minimumWidth: 0
        Layout.maximumWidth: implicitWidth
        Layout.fillWidth: modelData.kind === "segment"
        spacing: Style.marginXS
        function edges() {
          return {left: segment.mapToItem(root, 0, 0).x, right: segment.mapToItem(root, segment.width, 0).x,
            arrowLeft: childSlot.mapToItem(root, 0, 0).x, arrowRight: childSlot.mapToItem(root, childSlot.width, 0).x, clipped: label.truncated,
            label: {text: label.text, natural: label.implicitWidth, available: label.width, advance: metrics.advanceWidth(label.text)}};
        }
        function controls() {
          function rect(item) { var p = item.mapToItem(root, 0, 0); return {x: p.x, y: p.y, width: item.width, height: item.height, name: item.Accessible.name, path: part.modelData.path, iconOnly: item === childrenButton, kind: item === segment ? "segment" : "children"}; }
          return modelData.kind === "ancestors" ? [rect(segment)] : [rect(segment), rect(childrenButton)];
        }
        Item {
          id: segment
          Layout.fillWidth: true
          Layout.minimumWidth: Style.marginL
          implicitWidth: label.implicitWidth + Style.margin2S
          implicitHeight: root.implicitHeight
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: part.modelData.kind === "ancestors" ? I18n.tr("widgets.file-picker.ancestor-folders") : part.modelData.path
          Accessible.onPressAction: activate()
          NInputGuard { target: segment; focusOwner: root.focusOwner }
          function activate() {
            if (part.modelData.kind === "ancestors") {
              childrenOf.active = false;
              folders.parent = segment;
              folders.y = segment.height;
              folders.returnFocus = segment;
              folders.open();
            } else root.browser.navigate(part.modelData.path);
          }
          Keys.onReturnPressed: activate()
          Keys.onSpacePressed: activate()
          Keys.onDownPressed: if (part.modelData.path) root.showFolders(part.modelData.path, segment)
          Rectangle { anchors.fill: parent; color: pointer.containsMouse ? AtmoColor.mSurfaceVariant : "transparent"; radius: Style.iRadiusS; border.width: segment.activeFocus ? Style.borderM : 0; border.color: AtmoColor.mPrimary }
          NText { id: label; anchors.fill: parent; anchors.margins: Style.marginS; text: part.modelData.name; elide: Text.ElideMiddle; verticalAlignment: Text.AlignVCenter; pointSize: Style.fontSizeM }
          MouseArea { id: pointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: segment.activate() }
        }
        Item {
          id: childSlot
          Layout.preferredWidth: root.implicitHeight
          Layout.preferredHeight: root.implicitHeight
          ChooserButton {
            id: childrenButton
            anchors.fill: parent
            visible: part.modelData.kind === "segment"
            icon: Icon.chevronRight
            tooltipText: I18n.tr("widgets.file-picker.subfolders-of", {name: part.modelData.name})
            onClicked: root.showFolders(part.modelData.path, childrenButton)
          }
          AtmoIcon { anchors.centerIn: parent; visible: part.modelData.kind === "ancestors"; icon: Icon.chevronRight; pointSize: Style.fontSizeM; color: AtmoColor.mOnSurfaceVariant }
        }
      }
    }
    Item {
      id: emptySpace
      Layout.fillWidth: true
      Layout.minimumWidth: Style.marginM
      Layout.fillHeight: true
      activeFocusOnTab: true
      Accessible.role: Accessible.Button
      Accessible.name: I18n.tr("widgets.file-picker.edit-location")
      Accessible.onPressAction: root.editRequested()
      Keys.onReturnPressed: root.editRequested()
      Keys.onSpacePressed: root.editRequested()
      Rectangle { anchors.fill: parent; color: "transparent"; radius: Style.iRadiusS; border.width: emptySpace.activeFocus ? Style.borderM : 0; border.color: AtmoColor.mPrimary }
      MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: root.editRequested() }
    }
  }
}
