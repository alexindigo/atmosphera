import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Files
import qs.Widgets

PanelWindow {
  id: root
  required property var request
  readonly property var operations: request.browser.operations
  readonly property bool deleteConfirmOpen: operations.pendingDelete.length > 0
  function operationState() {
    var focused = root.contentItem.Window.activeFocusItem;
    return {
      busy: operations.busy,
      renaming: operations.renaming,
      renamePath: operations.renamePath,
      renameName: operations.renameName,
      renameError: operations.renameError,
      renameSelection: operations.renaming && focused && focused.selectionStart !== undefined ? [focused.selectionStart, focused.selectionEnd] : [],
      error: operations.errorText,
      pendingDelete: operations.pendingDelete,
      deleteButtons: deleteOverlay.controlGeometry(root.contentItem),
      menu: listing.contextState(root.contentItem)
    };
  }
  property real preferredPanelWidth: request.viewSettings.dialogWidth * Style.uiScaleRatio
  property real preferredPanelHeight: request.viewSettings.dialogHeight * Style.uiScaleRatio
  function resizePanel(dx, dy) {
    var width = Math.max(minimumPanelSize.width, Math.min(panel.width + dx, root.width - Style.margin2XL));
    var height = Math.max(minimumPanelSize.height, Math.min(panel.height + dy, root.height - Style.margin2XL));
    request.viewSettings.setDialogSize(width / Style.uiScaleRatio, height / Style.uiScaleRatio);
    preferredPanelWidth = Qt.binding(() => request.viewSettings.dialogWidth * Style.uiScaleRatio);
    preferredPanelHeight = Qt.binding(() => request.viewSettings.dialogHeight * Style.uiScaleRatio);
  }
  function viewState() {
    var view = listing.viewState(panel), settings = request.viewSettings;
    var r = footer.resizeGeometry();
    var p = footer.mapToItem(panel, 0, 0);
    return Object.assign(view, {
                           dialogWidth: settings.dialogWidth,
                           dialogHeight: settings.dialogHeight,
                           preferences: settings.snapshot(),
                           resize: {
                             x: r.x + p.x,
                             y: r.y + p.y,
                             width: r.width,
                             height: r.height
                           },
                           controls: footer.viewControls().map(c => Object.assign({}, c, {
                                                                                    x: c.x + p.x,
                                                                                    y: c.y + p.y
                                                                                  }))
                         });
  }
  readonly property size minimumPanelSize: Qt.size(Math.ceil(contentLayout.Layout.minimumWidth), Math.ceil(contentLayout.Layout.minimumHeight))
  readonly property var bottomGeometry: ({
                                           width: panel.width,
                                           bandHeight: appOptions.visible ? appOptions.height : 0,
                                           footer: footer.controlGeometry()
                                         })
  readonly property var preview: filePreview
  readonly property bool quickLookOpen: quickLook.opened
  readonly property bool pathEditing: header.editing
  function pathEntryState() {
    return {
      location: header.pathState(),
      name: {
        text: nameField.text,
        suggestions: nameField.suggestions,
        completionOpen: nameField.completionOpen,
        completionRows: nameField.completionGeometry(root.contentItem)
      }
    };
  }
  readonly property bool textEntryFocused: nameField.inputItem.activeFocus || header.editingText || request.browser.creatingFolder || operations.renaming
  readonly property string announcementError: request.errorText || request.browser.errorText || request.browser.createFolderError || operations.renameError || operations.errorText
  onAnnouncementErrorChanged: if (visible && announcementError)
                                panel.Accessible.announce(announcementError, Accessible.Assertive)
  Timer {
    id: countAnnouncement
    interval: 300
    onTriggered: if (root.visible && root.request.browser.status === "ready")
                   panel.Accessible.announce(I18n.tr("widgets.file-picker.item-count", {
                                                       count: root.request.browser.count
                                                     }))
  }
  Connections {
    target: root.request.browser
    function onCountChanged() {
      countAnnouncement.restart();
    }
    function onStatusChanged() {
      if (root.request.browser.status === "loading")
        panel.Accessible.announce(I18n.tr("common.loading"));
      else
        countAnnouncement.restart();
    }
  }
  readonly property var breadcrumbText: header.breadcrumbItems.filter(part => part.kind === "segment").map(part => part.text)
  readonly property var previewRenderer: quickLook.renderer
  readonly property var playbackState: quickLook.playbackState
  function transportGeometry() {
    return quickLook.transportGeometry();
  }
  readonly property var columnGeometry: listing.columnGeometry
  readonly property var nameSelection: [nameField.inputItem.selectionStart, nameField.inputItem.selectionEnd]
  readonly property bool selectionCountVisible: footer.selectionCountVisible
  readonly property var previewMotion: ({
                                          duration: Style.animationNormal,
                                          running: quickLook.expanding,
                                          geometry: quickLook.geometry
                                        })
  readonly property string focusedControl: panel.Window.window && panel.Window.window.activeFocusItem ? (panel.Window.window.activeFocusItem.Accessible.name || panel.Window.window.activeFocusItem.objectName || "unnamed") : ""
  readonly property string focusArea: nameField.inputItem.activeFocus ? "name" : header.editing ? "path" : listing.navigationFocused ? "listing" : quickLook.activeFocus ? "preview" : "control"
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  visible: !request.settled
  color: Qt.rgba(0, 0, 0, 0.35)
  WlrLayershell.namespace: "atmosphera-filechooser"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  FilePreview {
    id: filePreview
    item: quickLook.opened ? listing.cursorItem : null
  }
  FileThumbnails {
    id: thumbnails
    enabled: !root.request.settled
  }

  function focusListing() {
    listing.focusNavigation();
  }
  function scrollState() {
    return listing.scrollState();
  }
  function folderEditorState() {
    return listing.folderEditorState();
  }
  function recentRows() {
    return rail.recentRows();
  }
  function iconState() {
    return listing.iconState();
  }
  function layoutGeometry() {
    function rect(item) {
      var r = item.mapToItem(panel, 0, 0, item.width, item.height);
      return {
        x: r.x,
        y: r.y,
        width: r.width,
        height: r.height
      };
    }
    function controls(item, entries) {
      var origin = item.mapToItem(panel, 0, 0);
      return entries.map(entry => ({
        x: entry.x + origin.x,
        y: entry.y + origin.y,
        width: entry.width,
        height: entry.height,
        iconOnly: entry.iconOnly === true,
        kind: entry.kind || "",
        path: entry.path || "",
        name: entry.name || ""
      }));
    }
      return {
      minimumWidth: minimumPanelSize.width,
      minimumHeight: minimumPanelSize.height,
      width: panel.width,
      height: panel.height,
      header: controls(header, header.controlGeometry()),
      listing: rect(listing),
      entries: listing.controlGeometry(),
      footer: controls(footer, footer.controlGeometry()),
      viewControls: controls(footer, footer.viewControls()),
      band: appOptions.visible ? controls(appOptions, appOptions.controlGeometry()) : [],
      rail: rect(rail)
    };
    }
      function choiceGeometry() {
      return appOptions.choiceGeometry();
    }
      function thumbnailState() {
      return listing.thumbnailState();
    }
      function choiceValuesFit() {
      return appOptions.choiceValuesFit();
    }
      function dropdownValuesFit() {
      return header.dropdownValuesFit && footer.dropdownValuesFit && (!appOptions.visible || appOptions.choiceValuesFit());
    }
      function breadcrumbGeometry() {
      return header.breadcrumbGeometry();
    }
      function dismissLayer() {
      if (listing.contextOpen) {
      listing.dismissContext();
    } else if (deleteConfirmOpen) {
      operations.declineDelete();
    } else if (operations.renaming) {
      operations.cancelRename();
      listing.focusNavigation();
    } else if (header.transientOpen || nameField.completionOpen) {
      header.dismissTransient();
      nameField.dismissCompletion();
    } else if (request.pendingReplace) {
      editAfterReplace();
    } else if (quickLook.opened) {
      quickLook.opened = false;
    } else if (header.editing)
      header.leavePathEditing();
      else if (request.browser.creatingFolder) {
      request.browser.cancelCreateFolder();
      listing.focusNavigation();
    } else if (request.browser.filtering)
      request.clearFilters();
      else
      request.cancel();
    }
      function editAfterReplace() {
      request.declineReplace();
      Qt.callLater(root.initialFocus);
    }
      function initialFocus() {
      if (!visible || request.settled)
      return;
      if (request.method === "save") {
      nameField.inputItem.forceActiveFocus();
      var dot = request.saveName.lastIndexOf(".");
      nameField.inputItem.select(0, dot > 0 ? dot : request.saveName.length);
    } else
      listing.focusNavigation();
    }
      Component.onCompleted: Qt.callLater(initialFocus)
      Connections {
      target: root.request
      function onPathNavigation() {
      header.leavePathEditing();
    }
    }
      Connections {
      target: root.request.browser
      function onStatusChanged() {
      if (root.request.browser.status === "ready" && !root.quickLookOpen && !root.pathEditing && root.focusArea === "name")
      root.initialFocus();
    }
    }
      NScopedShortcut {
      scope: root.contentItem
      sequence: "Escape"
      onActivated: root.dismissLayer()
    }
      NScopedShortcut {
      scope: root.contentItem
      sequence: "Ctrl+L"
      enabled: !root.quickLookOpen && !root.request.pendingReplace && !root.deleteConfirmOpen
      onActivated: header.editPath()
    }
      NScopedShortcut {
      scope: root.contentItem
      sequence: "Ctrl+F"
      enabled: !root.quickLookOpen && !root.request.pendingReplace && !root.deleteConfirmOpen
      onActivated: header.focusFilter()
    }
      NScopedShortcut {
      scope: root.contentItem
      sequence: "Ctrl+Shift+N"
      enabled: !root.quickLookOpen && !root.request.pendingReplace && !root.deleteConfirmOpen && !root.operations.busy
      onActivated: root.request.beginCreateFolder()
    }
      NScopedShortcut {
      scope: root.contentItem
      sequence: "Alt+Left"
      enabled: !root.quickLookOpen && !root.request.pendingReplace && !root.deleteConfirmOpen
      onActivated: root.request.browser.back()
    }
      NScopedShortcut {
      scope: root.contentItem
      sequence: "Alt+Right"
      enabled: !root.quickLookOpen && !root.request.pendingReplace && !root.deleteConfirmOpen
      onActivated: root.request.browser.forward()
    }
      NScopedShortcut {
      scope: root.contentItem
      sequence: "Alt+Up"
      enabled: !root.quickLookOpen && !root.request.pendingReplace && !root.deleteConfirmOpen
      onActivated: root.request.browser.up()
    }
      NScopedShortcut {
      scope: root.contentItem
      sequence: "F5"
      enabled: !root.quickLookOpen && !root.request.pendingReplace && !root.deleteConfirmOpen
      onActivated: root.request.browser.refresh()
    }
      NScopedShortcut {
      scope: root.contentItem
      sequence: "Ctrl++"
      enabled: !root.quickLookOpen && !root.request.pendingReplace && !root.deleteConfirmOpen
      onActivated: root.request.viewSettings.zoomBy(1)
    }
      NScopedShortcut {
      scope: root.contentItem
      sequence: "Ctrl+="
      enabled: !root.quickLookOpen && !root.request.pendingReplace && !root.deleteConfirmOpen
      onActivated: root.request.viewSettings.zoomBy(1)
    }
      NScopedShortcut {
      scope: root.contentItem
      sequence: "Ctrl+-"
      enabled: !root.quickLookOpen && !root.request.pendingReplace && !root.deleteConfirmOpen
      onActivated: root.request.viewSettings.zoomBy(-1)
    }
      NScopedShortcut {
      scope: root.contentItem
      sequence: "Ctrl+H"
      enabled: !root.quickLookOpen && !root.request.pendingReplace && !root.deleteConfirmOpen && !root.textEntryFocused
      onActivated: root.request.browser.showHidden = !root.request.browser.showHidden
    }

      Rectangle {
      id: panel
      Accessible.role: Accessible.Dialog
      Accessible.name: root.request.options.title || I18n.tr("widgets.file-picker.title")
      anchors.centerIn: parent
      width: Math.max(root.minimumPanelSize.width, Math.min(root.preferredPanelWidth, parent.width - Style.margin2XL))
      height: Math.max(root.minimumPanelSize.height, Math.min(root.preferredPanelHeight, parent.height - Style.margin2XL))
      color: AtmoColor.mSurface
      radius: Style.radiusL
      clip: true
      ColumnLayout {
      id: contentLayout
      anchors.fill: parent
      spacing: 0
      enabled: root.request.pendingReplace === "" && !root.deleteConfirmOpen
      ColumnLayout {
      Layout.fillWidth: true
      Layout.margins: Style.marginM
      spacing: Style.marginS
      RowLayout {
      Layout.fillWidth: true
      NText {
      Layout.minimumWidth: 0
      Layout.maximumWidth: 180 * Style.uiScaleRatio
      text: root.request.options.title || I18n.tr("widgets.file-picker.title")
      elide: Text.ElideRight
      pointSize: Style.fontSizeM
    }
      FileChooserHeader {
      id: header
      Layout.fillWidth: true
      request: root.request
      onListingFocusRequested: listing.focusNavigation()
    }
      ChooserButton {
      icon: Icon.close
      tooltipText: I18n.tr("common.close")
      onClicked: root.request.cancel()
    }
    }
      RowLayout {
      visible: root.request.method === "save" || root.request.method === "open"
      Layout.fillWidth: true
      ChooserPathField {
      id: nameField
      Layout.fillWidth: true
      label: I18n.tr("widgets.file-picker.file-name")
      text: root.request.method === "save" ? root.request.saveName : root.request.openDisplayName
      basePath: root.request.browser.currentPath
      nameFilter: root.request.currentFilter
      directoriesOnly: root.request.options.directory === true
      showHidden: root.request.browser.showHidden
      fontSize: Style.fontSizeL
      onTextEdited: root.request.method === "save" ? root.request.editSaveName(text) : root.request.editOpenName(text)
      onEditingStarted: root.request.beginNameEdit()
      onAccepted: {
      dismissCompletion();
      root.request.accept();
    }
    }
      ChooserButton {
      Layout.alignment: Qt.AlignBottom
      Layout.preferredWidth: nameField.inputItem.implicitHeight
      Layout.preferredHeight: nameField.inputItem.implicitHeight
      icon: Icon.filter
      visible: root.request.method === "save"
      tooltipText: I18n.tr("widgets.file-picker.filter-by-name")
      Accessible.checkable: true
      Accessible.checked: root.request.saveFilterEnabled
      textColor: root.request.saveFilterEnabled ? AtmoColor.mPrimary : AtmoColor.mOnSurface
      onClicked: root.request.saveFilterEnabled = !root.request.saveFilterEnabled
    }
    }
    }
      Rectangle {
      Layout.fillWidth: true
      implicitHeight: Style.borderS
      color: AtmoColor.mOutline
    }
      Item {
      id: browserArea
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumWidth: browserLayout.Layout.minimumWidth
      Layout.minimumHeight: browserLayout.Layout.minimumHeight
      RowLayout {
      id: browserLayout
      anchors.fill: parent
      spacing: 0
      FilePlacesRail {
      id: rail
      Layout.minimumWidth: implicitWidth
      Layout.maximumWidth: implicitWidth
      Layout.preferredWidth: implicitWidth
      Layout.fillHeight: true
      browser: root.request.browser
    }
      ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.margins: Style.marginM
      spacing: Style.marginM
      NText {
      Layout.fillWidth: true
      visible: text !== ""
      text: root.request.errorText || root.request.browser.errorText || root.operations.renameError || root.operations.errorText
      color: AtmoColor.mError
      wrapMode: Text.Wrap
      pointSize: Style.fontSizeS
    }
      FileListing {
      id: listing
      Layout.fillWidth: true
      Layout.fillHeight: true
      request: root.request
      thumbnails: thumbnails
      onEditPathRequested: initial => header.editPath(initial)
      onFilterRequested: initial => header.focusFilter(initial)
      onQuickLookRequested: tile => {
      var mapped = listing.mapToItem(browserArea, tile.x, tile.y, tile.width, tile.height);
      quickLook.openFrom(mapped);
    }
    }
    }
    }
      FileQuickLook {
      id: quickLook
      keyFocusOwner: listing
      anchors.fill: parent
      preview: filePreview
      onCloseRequested: root.dismissLayer()
      onMoveRequested: delta => root.request.selection.move(delta, false)
    }
    }
      Rectangle {
      Layout.fillWidth: true
      implicitHeight: Style.borderS
      color: AtmoColor.mOutline
    }
      FileAppOptions {
      id: appOptions
      Layout.fillWidth: true
      visible: root.request.choices.length > 0
      request: root.request
      enabled: !root.quickLookOpen && !root.request.pendingReplace
    }
      FileChooserFooter {
      id: footer
      Layout.fillWidth: true
      Layout.margins: Style.marginL
      request: root.request
      resizeAvailable: !root.quickLookOpen && !root.request.pendingReplace && !root.deleteConfirmOpen
      onResizeRequested: (dx, dy) => root.resizePanel(dx, dy)
      enabled: !root.quickLookOpen && !root.request.pendingReplace
    }
    }
      FileDeleteConfirmation {
      id: deleteOverlay
      anchors.fill: parent
      operations: root.operations
      returnFocus: listing
    }
      ChooserFocusScope {
      id: replaceOverlay
      anchors.fill: parent
      visible: root.request.pendingReplace !== ""
      Accessible.role: Accessible.Dialog
      Accessible.name: I18n.tr("widgets.file-picker.overwrite-title")
      Accessible.description: root.request.pendingReplace
      NInputGuard {
      target: replaceOverlay
      focusTarget: changeNameButton
      focusOwner: root.request.method === "save" ? nameField.inputItem : listing
      focusOnActivation: true
    }
      Rectangle {
      anchors.fill: parent
      radius: panel.radius
      color: Qt.alpha(AtmoColor.mSurface, 0.95)
    }
      MouseArea {
      anchors.fill: parent
    }
      ColumnLayout {
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.margin2XL, 480 * Style.uiScaleRatio)
      spacing: Style.marginL
      AtmoIcon {
      Layout.alignment: Qt.AlignHCenter
      icon: Icon.filepickerFile
      pointSize: Style.fontSizeXXXL * 2
      color: AtmoColor.mOnSurfaceVariant
    }
      NText {
      Layout.fillWidth: true
      text: I18n.tr("widgets.file-picker.overwrite-title")
      horizontalAlignment: Text.AlignHCenter
      pointSize: Style.fontSizeL
    }
      NText {
      Layout.fillWidth: true
      text: root.request.pendingReplace.slice(root.request.pendingReplace.lastIndexOf("/") + 1)
      horizontalAlignment: Text.AlignHCenter
      pointSize: Style.fontSizeL
    }
      NText {
      Layout.fillWidth: true
      text: I18n.tr("widgets.file-picker.overwrite-description")
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
    }
      RowLayout {
      Layout.alignment: Qt.AlignHCenter
      spacing: Style.marginM
      ChooserButton {
      id: changeNameButton
      focus: replaceOverlay.visible
      text: I18n.tr(root.request.method === "saveFiles" ? "widgets.file-picker.back" : "widgets.file-picker.change-name")
      primary: true
      onClicked: root.editAfterReplace()
    }
      ChooserButton {
      id: replaceButton
      text: I18n.tr("widgets.file-picker.replace")
      visible: !root.request.busy
      onClicked: root.request.confirmReplace()
    }
    }
    }
    }
    }
    }
