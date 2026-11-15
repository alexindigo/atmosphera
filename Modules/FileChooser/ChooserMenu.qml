import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// A local, keyboard-owned menu. Entries and callbacks come from its consumer;
// the menu knows nothing about breadcrumbs or filesystem operations.
Popup {
  id: root
  property string title: ""
  property var entries: []
  property Item returnFocus: null
  property real maximumHeight: 320 * Style.uiScaleRatio
  property var _pages: []
  readonly property var currentEntries: _pages.length ? _pages[_pages.length - 1].children : entries
  readonly property string currentTitle: _pages.length ? _pages[_pages.length - 1].name : title
  readonly property int depth: _pages.length
  signal triggered(var entry)
  width: 280 * Style.uiScaleRatio
  padding: Style.marginS
  focus: true
  implicitHeight: Math.min(body.implicitHeight + topPadding + bottomPadding, maximumHeight)
  // Escape belongs to the menu hierarchy, not Popup's unconditional close.
  // The containing chooser's Escape intent also calls backOrClose().
  closePolicy: Popup.CloseOnPressOutside
  onOpened: {
    _pages = [];
    rows.currentIndex = 0;
    focusCurrent();
  }
  function focusCurrent() {
    if (!visible)
      return;
    if (rows.currentItem)
      rows.currentItem.forceActiveFocus();
    else
      body.forceActiveFocus();
  }
  onClosed: if (returnFocus && returnFocus.visible && returnFocus.enabled)
              returnFocus.forceActiveFocus()
  function activate(index) {
    var entry = currentEntries[index];
    if (entry) {
      if (entry.children) {
        _pages = _pages.concat([entry]);
        rows.currentIndex = 0;
        Qt.callLater(focusCurrent);
        return;
      }
      close();
      triggered(entry);
    }
  }
  function backOrClose() {
    if (!_pages.length) {
      close();
      return;
    }
    _pages = _pages.slice(0, -1);
    rows.currentIndex = 0;
    Qt.callLater(focusCurrent);
  }
  function state(target) {
    var frame = contentItem.mapToItem(target, -leftPadding, -topPadding, width, height);
    return {
      open: visible,
      frame: {
        x: frame.x,
        y: frame.y,
        width: frame.width,
        height: frame.height
      },
      title: currentTitle,
      depth: depth,
      entries: currentEntries.map(entry => ({
        key: entry.key || "",
        name: entry.name,
        checked: entry.checked,
        submenu: !!entry.children
      })),
    rows: Array.from(rows.contentItem.children).filter(item => typeof item.index === "number" && rows.itemAtIndex(item.index) === item).map(item => {
    var r = item.mapToItem(target, 0, 0, item.width, item.height);
    return {
    key: item.modelData.key || "",
    x: r.x,
    y: r.y,
    width: r.width,
    height: r.height
  };
  })
  };
  }
    function geometry() {
    var row = rows.itemAtIndex(rows.currentIndex);
    var p = row ? row.mapToItem(body, 0, 0) : Qt.point(0, 0);
    return {
    contentHeight: body.height,
    top: p.y,
    bottom: row ? p.y + row.height : 0,
    rowHeight: row ? row.height : 0
  };
  }
    background: Rectangle {
    color: AtmoColor.mSurfaceVariant
    radius: Style.iRadiusS
    border.width: Style.borderS
    border.color: AtmoColor.mOutline
  }
    contentItem: ColumnLayout {
    id: body
    Accessible.role: Accessible.PopupMenu
    Accessible.name: root.currentTitle
    spacing: Style.marginS
    Keys.onPressed: event => {
    if (event.key === Qt.Key_Escape)
    root.backOrClose();
    else if (event.key === Qt.Key_Down)
    rows.currentIndex = Math.min(root.currentEntries.length - 1, rows.currentIndex + 1);
    else if (event.key === Qt.Key_Up)
    rows.currentIndex = Math.max(0, rows.currentIndex - 1);
    else if (event.key === Qt.Key_Home)
    rows.currentIndex = 0;
    else if (event.key === Qt.Key_End)
    rows.currentIndex = root.currentEntries.length - 1;
    else if (event.key === Qt.Key_Left)
    root.backOrClose();
    else if (event.key === Qt.Key_Right && root.currentEntries[rows.currentIndex] && root.currentEntries[rows.currentIndex].children)
    root.activate(rows.currentIndex);
    else if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key))
    root.activate(rows.currentIndex);
    else {
    event.accepted = false;
    return;
  }
    event.accepted = true;
  }
    RowLayout {
    Layout.fillWidth: true
    Layout.margins: Style.marginS
    ChooserButton {
    visible: root.depth > 0
    icon: Icon.chevronLeft
    tooltipText: I18n.tr("widgets.file-picker.back")
    onClicked: root.backOrClose()
  }
    NText {
    Layout.fillWidth: true
    text: root.currentTitle
    pointSize: Style.fontSizeM
    elide: Text.ElideRight
  }
  }
    Rectangle {
    Layout.fillWidth: true
    implicitHeight: Style.borderS
    color: AtmoColor.mOutline
  }
    ListView {
    id: rows
    Layout.fillWidth: true
    Layout.fillHeight: true
    implicitHeight: contentHeight
    clip: true
    model: root.currentEntries
    onCurrentIndexChanged: {
    if (currentIndex >= 0)
    positionViewAtIndex(currentIndex, ListView.Contain);
    Qt.callLater(root.focusCurrent);
  }
    onCurrentItemChanged: Qt.callLater(root.focusCurrent)
    ScrollIndicator.vertical: ScrollIndicator {}
    delegate: ItemDelegate {
    id: menuEntry
    required property var modelData
    required property int index
    width: rows.width
    highlighted: rows.currentIndex === index
    activeFocusOnTab: false
    Accessible.role: Accessible.MenuItem
    Accessible.name: modelData.name
    checkable: modelData.checked !== undefined
    checked: modelData.checked === true
    contentItem: RowLayout {
    NText {
    Layout.fillWidth: true
    text: menuEntry.modelData.name
    elide: Text.ElideMiddle
    pointSize: Style.fontSizeM
  }
    AtmoIcon {
    visible: menuEntry.checked || !!menuEntry.modelData.children
    icon: menuEntry.modelData.children ? Icon.chevronRight : Icon.check
    pointSize: Style.fontSizeM
  }
  }
    background: Rectangle {
    radius: Style.iRadiusXS
    color: menuEntry.highlighted ? Qt.alpha(AtmoColor.mPrimary, 0.18) : "transparent"
  }
    onClicked: root.activate(index)
  }
  }
  }
  }
