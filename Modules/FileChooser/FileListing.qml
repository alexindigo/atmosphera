import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Files
import qs.Widgets

FocusScope {
  id: root
  NInputGuard {
    target: root
  }
  required property var request
  readonly property var settings: request.viewSettings
  readonly property bool compact: request.viewMode === "compact"
  readonly property real iconSize: settings.iconSize * Style.uiScaleRatio
  readonly property real tileSize: (settings.iconSize + 74) * Style.uiScaleRatio
  readonly property real tileWidth: (settings.iconSize + 104) * Style.uiScaleRatio
  readonly property real rowHeight: Math.max(48 * Style.uiScaleRatio, iconSize + Style.margin2M)
  readonly property int compactRows: Math.max(1, Math.floor(grid.height / rowHeight))
  Layout.minimumWidth: frame.Layout.minimumWidth + Style.margin2XS
  Layout.minimumHeight: frame.Layout.minimumHeight + Style.margin2XS
  readonly property bool navigationFocused: viewportScope.activeFocus && !request.browser.operations.renaming
  readonly property bool contextOpen: contextMenu.visible
  function contextState(target) {
    return contextMenu.state(target);
  }
  function dismissContext() {
    contextMenu.backOrClose();
  }
  function openContext(index, position) {
    request.browser.operations.context(index);
    contextMenu.backgroundMenu = index < 0;
    contextMenu.anchorPosition = position;
    contextMenu.open();
  }
  FileActionsMenu {
    id: contextMenu
    parent: root
    request: root.request
    returnFocus: viewportScope
  }
  readonly property int columns: Math.max(1, Math.floor(grid.width / tileWidth))
  property int _preferredLane: -1
  onColumnsChanged: _preferredLane = -1
  onCompactRowsChanged: _preferredLane = -1
  property bool _movingCursor: false
  readonly property var activeView: request.viewMode === "list" ? list : grid
  readonly property int pageStep: compact ? compactRows * Math.max(1, Math.floor(grid.width / grid.cellWidth)) : Math.max(1, Math.floor((request.viewMode === "list" ? list.height : grid.height) / (request.viewMode === "list" ? rowHeight : tileSize))) * (request.viewMode === "list" ? 1 : columns)
  readonly property var cursorItem: {
    void request.browser.count;
    return request.browser.entry(request.selection.cursor);
  }
  readonly property var columnGeometry: {
    // itemAtIndex() is not notifying: a null lookup can stay cached after the
    // asynchronous delegate appears. Read the notifying children and row
    // properties instead, including pool transitions, without a timer/counter.
    var row = Array.from(list.contentItem.children).find(item => typeof item.index === "number" && !item.inPool);
    return {
      header: listHeaders.geometry,
      row: row ? row.columnGeometry : []
    };
  }
  function viewState(target) {
    function rect(item) {
      var r = item.mapToItem(target, 0, 0, item.width, item.height);
      return {
        x: r.x,
        y: r.y,
        width: r.width,
        height: r.height
      };
    }
    return {
      mode: request.viewMode,
      zoom: settings.zoom,
      zooms: settings.zooms,
      iconSize: settings.iconSize,
      thumbnails: settings.thumbnails,
      columnShares: settings.columnShares,
      rows: compactRows,
      flow: compact ? "columns" : request.viewMode,
      x: activeView.contentX,
      originX: activeView.originX,
      originY: activeView.originY,
      cells: listHeaders.cellBounds.map(cell => ({
        x: listHeaders.mapToItem(target, cell.x, 0).x,
        width: cell.width
      })),
    handles: request.viewMode === "list" ? [rect(nameResize), rect(sizeResize)] : []
  };
  }
    signal quickLookRequested(rect tile)
    signal editPathRequested(string initial)
    signal filterRequested(string initial)
    function activeEntries(view) {
    // Reuse pools retain native items whose visible property can still be true.
    // Only the view's indexed items belong to its current presentation.
    return Array.from(view.contentItem.children).filter(item => typeof item.index === "number" && view.itemAtIndex(item.index) === item).sort((a, b) => a.index - b.index);
  }
    function thumbnailState() {
    return {
    tiles: activeEntries(activeView).filter(item => item.thumbnailActive).map(item => item.thumbnailState),
    entries: activeEntries(activeView).map(item => item.thumbnailState)
  };
  }

    function scrollState() {
    var view = request.viewMode === "list" ? list : grid;
    var hiddenView = request.viewMode === "list" ? grid : list;
    return {
    y: view.contentY,
    height: view.height,
    contentHeight: view.contentHeight,
    moving: view.moving,
    flicking: view.flicking,
    reused: view.reuseItems,
    delegates: view.contentItem.children.length,
    hiddenCount: hiddenView.count,
    wheelStep: wheelTypography.implicitHeight * Qt.styleHints.wheelScrollLines,
    pageStep: pageStep,
    bandActive: listingInput.dragging
  };
  }
    NText {
    id: wheelTypography
    visible: false
    pointSize: Style.fontSizeM
  }
    function folderEditorState() {
    function center(item) {
    return item.mapToItem(root, 0, item.height / 2).y;
  }
    return {
    name: newFolderField.text,
    selection: [newFolderField.inputItem.selectionStart, newFolderField.inputItem.selectionEnd],
    centers: [center(newFolderIcon), center(newFolderField), center(createFolderButton)]
  };
  }
    function focusNavigation() {
    newFolderField.inputItem.focus = false;
    viewportScope.forceActiveFocus();
    Qt.callLater(focusCurrent);
  }
    function focusCurrent() {
    if (!navigationFocused)
    return;
    var item = activeView.itemAtIndex(request.selection.cursor);
    if (item)
    item.focusEntry();
    else {
    // FocusScope.forceActiveFocus restores its last child. Retiring the
    // cursor must release each native view's subfocus before focusing Files.
    grid.focus = false;
    list.focus = false;
    viewportScope.forceActiveFocus();
  }
  }
    onNavigationFocusedChanged: if (navigationFocused)
    Qt.callLater(focusCurrent)
    Connections {
    target: root.settings
    function onZoomChanged() {
    root._preferredLane = -1;
    Qt.callLater(root.revealCursor);
    Qt.callLater(root.focusCurrent);
  }
    function onModeChanged() {
    root._preferredLane = -1;
    Qt.callLater(root.revealCursor);
    Qt.callLater(root.focusCurrent);
  }
  }
    Connections {
    target: root.request.browser
    function onHistoryLeaving() {
    root.request.browser.rememberHistory("viewport", {
    mode: root.request.viewMode,
    x: root.activeView.contentX - root.activeView.originX,
    y: root.activeView.contentY - root.activeView.originY
  });
  }
    function onHistoryRestored(state) {
    var saved = state.viewport;
    if (!saved)
    return;
    root.request.viewMode = saved.mode;
    Qt.callLater(function () {
    root.activeView.forceLayout();
    root.activeView.contentX = root.activeView.originX + saved.x;
    root.activeView.contentY = root.activeView.originY + saved.y;
    root.focusCurrent();
  });
  }
    function onCreatingFolderChanged() {
    if (root.request.browser.creatingFolder)
    Qt.callLater(function () {
    newFolderField.inputItem.forceActiveFocus();
    newFolderField.inputItem.selectAll();
  });
  }
    function onFolderCreated(path) {
    root.focusNavigation();
    root.revealCursor();
  }
  }
    Connections {
    target: root.request.browser.operations
    function onCompleted() {
    root.focusNavigation();
    root.revealCursor();
  }
    function onRenamingChanged() {
    if (!root.request.browser.operations.renaming)
    Qt.callLater(root.focusNavigation);
  }
  }

    function controlGeometry() {
    var view = request.viewMode === "list" ? list : grid;
    var bounds = view.mapToItem(root, 0, 0, view.width, view.height);
    var tiles = activeEntries(view).filter(item => item.visible).map(item => {
    var rect = item.mapToItem(root, 0, 0, item.width, item.height);
    return {
    x: rect.x,
    y: rect.y,
    width: rect.width,
    height: rect.height,
    path: item.path,
    index: item.index
  };
  }).filter(rect => rect.x < bounds.x + bounds.width && rect.x + rect.width > bounds.x && rect.y < bounds.y + bounds.height && rect.y + rect.height > bounds.y);
    return {
    viewport: {
    x: bounds.x,
    y: bounds.y,
    width: bounds.width,
    height: bounds.height
  },
    tiles: tiles,
    cursor: tileRect()
  };
  }
    function iconState() {
    var view = request.viewMode === "list" ? list : grid;
    return activeEntries(view).filter(item => item.visible).map(item => item.iconState()).filter(item => item !== null);
  }

    function tileRect() {
    var view = request.viewMode === "list" ? list : grid;
    var tile = view.itemAtIndex(request.selection.cursor);
    return tile ? tile.mapToItem(root, 0, 0, tile.width, tile.height) : Qt.rect(0, 0, root.width, root.height);
  }
    function revealCursor() {
    if (request.selection.cursor < 0)
    return;
    if (request.viewMode === "list")
    list.positionViewAtIndex(request.selection.cursor, ListView.Contain);
    else
    grid.positionViewAtIndex(request.selection.cursor, GridView.Contain);
  }
    function sort(key) {
    request.browser.sortDescending = request.browser.sortKey === key ? !request.browser.sortDescending : false;
    request.browser.sortKey = key;
  }
    function intersectingIndices(rect) {
    var cellWidth = request.viewMode === "list" ? list.width : grid.cellWidth;
    var cellHeight = request.viewMode === "list" ? rowHeight : grid.cellHeight;
    var count = request.viewMode === "list" ? 1 : columns;
    var indices = [];
    for (var i = 0; i < request.browser.count; i++) {
    var x = compact ? activeView.originX + Math.floor(i / compactRows) * cellWidth : i % count * cellWidth;
    var y = activeView.originY + (compact ? i % compactRows : Math.floor(i / count)) * cellHeight;
    var inset = request.viewMode === "list" ? 0 : Style.marginXS;
    if (x < rect.x + rect.width && x + cellWidth - inset > rect.x && y < rect.y + rect.height && y + cellHeight - inset > rect.y)
    indices.push(i);
  }
    return indices;
  }
    function moveCursor(delta, extend, focusOnly, vertical) {
    _movingCursor = true;
    var current = request.selection.cursor;
    var lanes = compact ? compactRows : columns;
    var crossing = compact ? !vertical || Math.abs(delta) >= compactRows : vertical && request.viewMode === "grid";
    if (crossing && current >= 0) {
    if (_preferredLane < 0)
    _preferredLane = current % lanes;
    var group = Math.max(0, Math.min(Math.floor((request.browser.count - 1) / lanes), Math.floor(current / lanes) + delta / lanes));
    request.selection.moveTo(Math.min(request.browser.count - 1, group * lanes + _preferredLane), extend, focusOnly);
  } else {
    request.selection.move(delta, extend, focusOnly);
    _preferredLane = -1;
  }
    _movingCursor = false;
  }
    Connections {
    target: root.request.selection
    function onCursorChanged() {
    if (!root._movingCursor)
    root._preferredLane = -1;
    Qt.callLater(root.focusCurrent);
  }
  }
    Keys.onPressed: event => {
    if (!navigationFocused) {
    event.accepted = false;
    return;
  }
    var shift = !!(event.modifiers & Qt.ShiftModifier);
    var alt = !!(event.modifiers & Qt.AltModifier);
    var ctrl = !!(event.modifiers & Qt.ControlModifier);
    event.accepted = true;
    var focusOnly = ctrl && !shift;
    if (event.key === Qt.Key_Backspace)
    request.browser.back();
    else if (event.key === Qt.Key_F2)
    request.browser.operations.beginRename();
    else if (event.key === Qt.Key_Delete) {
    if (shift)
    request.browser.operations.requestDelete();
    else
    request.browser.operations.trash();
  } else if (event.key === Qt.Key_Menu || (shift && event.key === Qt.Key_F10)) {
    var tile = tileRect();
    openContext(request.selection.cursor, Qt.point(tile.x, tile.y + tile.height));
  } else if (ctrl && event.key === Qt.Key_A)
    request.selection.selectAll();
    else if (event.key === Qt.Key_Left)
    moveCursor(compact ? -compactRows : -1, shift, focusOnly, false);
    else if (event.key === Qt.Key_Right)
    moveCursor(compact ? compactRows : 1, shift, focusOnly, false);
    else if (event.key === Qt.Key_Up)
    moveCursor(request.viewMode === "grid" ? -columns : -1, shift, focusOnly, true);
    else if (event.key === Qt.Key_Down)
    moveCursor(request.viewMode === "grid" ? columns : 1, shift, focusOnly, true);
    else if (event.key === Qt.Key_PageUp)
    moveCursor(-pageStep, shift, focusOnly, true);
    else if (event.key === Qt.Key_PageDown)
    moveCursor(pageStep, shift, focusOnly, true);
    else if (event.key === Qt.Key_Home)
    request.selection.moveTo(0, shift, focusOnly);
    else if (event.key === Qt.Key_End)
    request.selection.moveTo(request.browser.count - 1, shift, focusOnly);
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
    if (event.modifiers === Qt.NoModifier) {
    if (request.selection.cursor >= 0)
    request.activate(request.selection.cursor);
    else
    request.accept();
  }
  } else if (ctrl && event.key === Qt.Key_Space)
    request.selection.toggleCurrent();
    else if (event.key === Qt.Key_Space && cursorItem)
    quickLookRequested(tileRect());
    else if (event.text === "/" || event.text === "~")
    editPathRequested(event.text);
    else if (!ctrl && !alt && event.text.length && event.text >= " ")
    filterRequested(event.text);
    else
    event.accepted = false;
    if ([Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down, Qt.Key_Home, Qt.Key_End, Qt.Key_PageUp, Qt.Key_PageDown].includes(event.key))
    revealCursor();
  }

    Rectangle {
    anchors.fill: parent
    color: "transparent"
    border.width: root.navigationFocused ? Style.borderS : 0
    border.color: AtmoColor.mOutline
    radius: Style.iRadiusS
  }
    ColumnLayout {
    id: frame
    anchors.fill: parent
    anchors.margins: Style.marginXS
    spacing: Style.marginXS
    GridLayout {
    visible: root.request.browser.creatingFolder
    Layout.fillWidth: true
    columns: 3
    columnSpacing: Style.marginM
    rowSpacing: Style.marginXS
    AtmoIcon {
    id: newFolderIcon
    Layout.row: 0
    Layout.column: 0
    icon: Icon.filepickerFolder
    pointSize: Style.fontSizeXXL
  }
    ChooserTextField {
    id: newFolderField
    Layout.row: 0
    Layout.column: 1
    Layout.fillWidth: true
    accessibleName: I18n.tr("widgets.file-picker.folder-name")
    text: root.request.browser.newFolderName
    readOnly: root.request.browser.createFolderBusy
    onTextEdited: root.request.browser.newFolderName = text
    onAccepted: root.request.browser.createFolder(text)
  }
    ChooserButton {
    id: createFolderButton
    Layout.row: 0
    Layout.column: 2
    visible: !root.request.browser.createFolderBusy
    text: I18n.tr("widgets.file-picker.create-folder")
    onClicked: root.request.browser.createFolder(newFolderField.text)
  }
    BusyIndicator {
    Layout.row: 0
    Layout.column: 2
    visible: root.request.browser.createFolderBusy
    running: visible
  }
    NText {
    Layout.row: 1
    Layout.column: 1
    Layout.columnSpan: 2
    visible: text !== ""
    Layout.fillWidth: true
    text: root.request.browser.createFolderError
    color: AtmoColor.mError
    pointSize: Style.fontSizeS
    wrapMode: Text.Wrap
  }
  }
    FileListColumns {
    id: listHeaders
    visible: root.request.viewMode === "list"
    Layout.fillWidth: true
    Layout.rightMargin: Style.marginL
    Layout.preferredHeight: 54 * Style.uiScaleRatio
    leadingWidth: root.iconSize + Style.marginXS
    widths: root.settings.widths(availableColumns / Style.uiScaleRatio).map(w => w * Style.uiScaleRatio)
    nameCell: Component {
    FileColumnHeader {
    keyFocusOwner: root
    text: I18n.tr("widgets.file-picker.name") + (root.request.browser.sortKey === "name" ? (root.request.browser.sortDescending ? " ↓" : " ↑") : "")
    onClicked: root.sort("name")
  }
  }
    sizeCell: Component {
    FileColumnHeader {
    keyFocusOwner: root
    alignment: Text.AlignRight
    text: I18n.tr("widgets.file-picker.size") + (root.request.browser.sortKey === "size" ? (root.request.browser.sortDescending ? " ↓" : " ↑") : "")
    onClicked: root.sort("size")
  }
  }
    modifiedCell: Component {
    FileColumnHeader {
    keyFocusOwner: root
    text: I18n.tr("widgets.file-picker.modified") + (root.request.browser.sortKey === "modified" ? (root.request.browser.sortDescending ? " ↓" : " ↑") : "")
    onClicked: root.sort("modified")
  }
  }
    FileColumnResizer {
    id: nameResize
    x: listHeaders.boundaries[0] - width / 2
    height: parent.height
    label: I18n.tr("widgets.file-picker.name-column-width")
    onResizeRequested: delta => root.settings.resizeColumn(0, delta / Style.uiScaleRatio, listHeaders.availableColumns / Style.uiScaleRatio)
  }
    FileColumnResizer {
    id: sizeResize
    x: listHeaders.boundaries[1] - width / 2
    height: parent.height
    label: I18n.tr("widgets.file-picker.size-column-width")
    onResizeRequested: delta => root.settings.resizeColumn(1, delta / Style.uiScaleRatio, listHeaders.availableColumns / Style.uiScaleRatio)
  }
  }
    FocusScope {
    id: viewportScope
    activeFocusOnTab: true
    Accessible.role: Accessible.List
    Accessible.name: I18n.tr("widgets.file-picker.files")
    Accessible.description: root.request.browser.currentPath
    Accessible.focusable: true
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumWidth: Math.max(root.tileSize + Style.marginL, emptyState.visible && !root.request.browser.filtering ? emptyState.implicitWidth : 0)
    Layout.minimumHeight: Math.max(root.tileSize, emptyState.visible ? emptyState.implicitHeight : 0)
    GridView {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: Style.marginL
    visible: root.request.viewMode !== "list"
    clip: true
    model: visible ? root.request.browser.model : null
    reuseItems: true
    cacheBuffer: root.compact ? cellWidth : cellHeight
    flow: root.compact ? GridView.FlowTopToBottom : GridView.FlowLeftToRight
    cellWidth: root.compact ? (240 * Style.uiScaleRatio + root.iconSize) : width / root.columns
    cellHeight: root.compact ? height / root.compactRows : root.tileSize
    currentIndex: root.request.selection.cursor
    keyNavigationEnabled: false
    interactive: !listingInput.dragging
    highlightMoveDuration: 0
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
    onCurrentItemChanged: Qt.callLater(root.focusCurrent)
    ScrollBar.vertical: ScrollBar {
    Accessible.name: I18n.tr("widgets.file-picker.scroll-files")
  }
    ScrollBar.horizontal: ScrollBar {
    Accessible.name: I18n.tr("widgets.file-picker.scroll-files")
  }
    ChooserScrollHandler {
    viewport: grid
    lineHeight: wheelTypography.implicitHeight
    horizontal: root.compact
  }
    delegate: FileEntry {
    property bool inPool: false
    GridView.onPooled: inPool = true
    GridView.onReused: inPool = false
    required property int index
    required property string fileName
    required property string filePath
    required property bool fileIsDir
    required property double fileSize
    required property var fileModified
    width: grid.cellWidth - Style.marginXS
    height: grid.cellHeight - Style.marginXS
    name: fileName
    path: filePath
    directory: fileIsDir
    bytes: fileSize
    modified: fileModified
    selected: root.request.selection.selectedPaths.includes(filePath)
    selectable: directory === (root.request.selection.selectable === "folders")
    cursor: root.request.selection.cursor === index
    listingFocused: root.navigationFocused
    compactMode: root.compact
    iconSize: root.iconSize
    operations: root.request.browser.operations
    thumbnailActive: !root.request.settled && root.settings.thumbnails && !inPool && visible && grid.visible && x + width > grid.contentX && x < grid.contentX + grid.width && y + height > grid.contentY && y < grid.contentY + grid.height
    onPressed: modifiers => {
    root.focusNavigation();
    root.request.selection.click(index, modifiers);
  }
    onActivated: root.request.activate(index)
  }
  }
    ListView {
    id: list
    anchors.fill: parent
    anchors.rightMargin: Style.marginL
    visible: root.request.viewMode === "list"
    clip: true
    model: visible ? root.request.browser.model : null
    reuseItems: true
    cacheBuffer: root.rowHeight
    currentIndex: root.request.selection.cursor
    keyNavigationEnabled: false
    interactive: !listingInput.dragging
    highlightMoveDuration: 0
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
    onCurrentItemChanged: Qt.callLater(root.focusCurrent)
    ScrollBar.vertical: ScrollBar {
    Accessible.name: I18n.tr("widgets.file-picker.scroll-files")
  }
    ChooserScrollHandler {
    viewport: list
    lineHeight: wheelTypography.implicitHeight
  }
    delegate: FileEntry {
    property bool inPool: false
    ListView.onPooled: inPool = true
    ListView.onReused: inPool = false
    required property int index
    required property string fileName
    required property string filePath
    required property bool fileIsDir
    required property double fileSize
    required property var fileModified
    width: list.width
    height: root.rowHeight
    name: fileName
    path: filePath
    directory: fileIsDir
    bytes: fileSize
    modified: fileModified
    listMode: true
    iconSize: root.iconSize
    columnWidths: listHeaders.widths
    thumbnailActive: !root.request.settled && root.settings.thumbnails && !inPool && visible && list.visible && y + height > list.contentY && y < list.contentY + list.height
    operations: root.request.browser.operations
    selected: root.request.selection.selectedPaths.includes(filePath)
    selectable: directory === (root.request.selection.selectable === "folders")
    cursor: root.request.selection.cursor === index
    listingFocused: root.navigationFocused
    onPressed: modifiers => {
    root.focusNavigation();
    root.request.selection.click(index, modifiers);
  }
    onActivated: root.request.activate(index)
  }
  }
    FileListingInput {
    id: listingInput
    anchors.fill: parent
    anchors.rightMargin: Style.marginL
    viewport: root.request.viewMode === "list" ? list : grid
    selection: root.request.selection
    enabled: !root.request.browser.operations.renaming
    indexAt: point => root.activeView.indexAt(point.x + root.activeView.contentX, point.y + root.activeView.contentY)
    intersectingIndices: rect => root.intersectingIndices(rect)
    horizontal: root.compact
    onFocusRequested: root.focusNavigation()
    onActivated: index => root.request.activate(index)
    onContextRequested: (index, position) => {
    root.focusNavigation();
    var p = listingInput.mapToItem(root, position.x, position.y);
    root.openContext(index, p);
  }
  }
    WheelHandler {
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    acceptedModifiers: Qt.ControlModifier
    onWheel: event => {
    var pixels = event.phase !== Qt.NoScrollPhase && event.pixelDelta.y !== 0;
    root.settings.wheelZoom(pixels ? event.pixelDelta.y : event.angleDelta.y, pixels);
    event.accepted = true;
  }
  }
    ColumnLayout {
    id: emptyState
    anchors.centerIn: parent
    width: Math.max(0, parent.width - Style.margin2XL)
    visible: root.request.browser.count === 0 && root.request.browser.status !== "loading"
    spacing: Style.marginL
    AtmoIcon {
    Layout.alignment: Qt.AlignHCenter
    icon: Icon.filepickerFolder
    pointSize: Style.fontSizeXXXL * 2
    color: AtmoColor.mOnSurfaceVariant
  }
    NText {
    Layout.alignment: Qt.AlignHCenter
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    text: root.request.browser.filtering ? I18n.tr("widgets.file-picker.no-matches", {
    text: [root.request.browser.filterText, root.request.browser.saveFilterText].filter(value => value !== "").join(" / ")
  }) : I18n.tr("widgets.file-picker.empty-folder")
    pointSize: Style.fontSizeL
  }
    ChooserButton {
    Layout.alignment: Qt.AlignHCenter
    visible: !root.request.browser.filtering && root.request.browser.hasHidden && !root.request.browser.showHidden
    text: I18n.tr("widgets.file-picker.show-hidden")
    onClicked: root.request.browser.showHidden = true
  }
  }
    BusyIndicator {
    anchors.centerIn: parent
    visible: root.request.browser.status === "loading"
    running: visible
  }
  }
  }
  }
