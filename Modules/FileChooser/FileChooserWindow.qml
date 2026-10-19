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
  property real preferredPanelWidth: 1100 * Style.uiScaleRatio
  property real preferredPanelHeight: 740 * Style.uiScaleRatio
  readonly property size minimumPanelSize: Qt.size(Math.ceil(contentLayout.Layout.minimumWidth), Math.ceil(contentLayout.Layout.minimumHeight))
  readonly property var preview: filePreview
  readonly property bool quickLookOpen: quickLook.opened
  readonly property bool pathEditing: header.editing
  readonly property var previewRenderer: quickLook.renderer
  readonly property var columnGeometry: listing.columnGeometry
  readonly property var nameSelection: [nameField.inputItem.selectionStart, nameField.inputItem.selectionEnd]
  readonly property bool selectionCountVisible: footer.selectionCountVisible
  readonly property var previewMotion: ({duration: Style.animationNormal, running: quickLook.expanding, geometry: quickLook.geometry})
  readonly property string focusedControl: panel.Window.window && panel.Window.window.activeFocusItem ? (panel.Window.window.activeFocusItem.Accessible.name || panel.Window.window.activeFocusItem.objectName || "unnamed") : ""
  readonly property string focusArea: nameField.inputItem.activeFocus ? "name" : header.editing ? "path" : listing.navigationFocused ? "listing" : quickLook.activeFocus ? "preview" : "control"
  anchors { top: true; bottom: true; left: true; right: true }
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

  function focusListing() { listing.forceActiveFocus(); }
  function layoutGeometry() {
    function rect(item) {
      var r = item.mapToItem(panel, 0, 0, item.width, item.height);
      return {x: r.x, y: r.y, width: r.width, height: r.height};
    }
    function controls(item, entries) {
      var origin = item.mapToItem(panel, 0, 0);
      return entries.map(entry => ({x: entry.x + origin.x, y: entry.y + origin.y, width: entry.width, height: entry.height}));
    }
    return {minimumWidth: minimumPanelSize.width, minimumHeight: minimumPanelSize.height, width: panel.width, height: panel.height, header: controls(header, header.controlGeometry()), listing: rect(listing), entries: listing.controlGeometry(), footer: controls(footer, footer.controlGeometry()), rail: rect(rail)};
  }
  function choiceGeometry() { return footer.choiceGeometry(); }
  function breadcrumbGeometry() { return header.breadcrumbGeometry(); }
  function dismissLayer() {
    if (quickLook.opened) {
      quickLook.opened = false;
      listing.forceActiveFocus();
    } else if (header.editing)
      header.leavePathEditing();
    else
      request.cancel();
  }
  function initialFocus() {
    if (request.method === "save") {
      nameField.inputItem.forceActiveFocus();
      var dot = request.saveName.lastIndexOf(".");
      nameField.inputItem.select(0, dot > 0 ? dot : request.saveName.length);
    } else
      listing.forceActiveFocus();
  }
  Component.onCompleted: Qt.callLater(initialFocus)
  Connections {
    target: root.request.browser
    function onStatusChanged() {
      if (root.request.browser.status === "ready" && !root.quickLookOpen && !root.pathEditing && root.focusArea === "name")
        root.initialFocus();
    }
  }
  Shortcut { sequence: "Escape"; onActivated: root.dismissLayer() }
  Shortcut { sequence: "Ctrl+L"; enabled: !root.quickLookOpen; onActivated: header.editPath() }

  Rectangle {
    id: panel
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
      enabled: root.request.pendingReplace === ""
      ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: Style.marginL
        spacing: Style.marginM
        RowLayout {
          Layout.fillWidth: true
          NText { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.request.options.title || I18n.tr("widgets.file-picker.title"); elide: Text.ElideRight; pointSize: Style.fontSizeL }
          ChooserButton { icon: Icon.close; tooltipText: I18n.tr("common.close"); onClicked: root.request.cancel() }
        }
        ChooserTextField {
          id: nameField
          visible: root.request.method === "save"
          Layout.fillWidth: true
          label: I18n.tr("widgets.file-picker.file-name")
          text: root.request.saveName
          fontSize: Style.fontSizeL
          onTextEdited: root.request.saveName = text
          onAccepted: root.request.accept()
        }
      }
      Rectangle { Layout.fillWidth: true; implicitHeight: Style.borderS; color: AtmoColor.mOutline }
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
          FilePlacesRail { id: rail; Layout.minimumWidth: implicitWidth; Layout.maximumWidth: implicitWidth; Layout.preferredWidth: implicitWidth; Layout.fillHeight: true; browser: root.request.browser }
          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Style.marginM
            spacing: Style.marginM
            FileChooserHeader { id: header; Layout.fillWidth: true; request: root.request; onListingFocusRequested: listing.forceActiveFocus() }
            NText {
              Layout.fillWidth: true
              visible: text !== ""
              text: root.request.errorText || root.request.browser.errorText
              color: AtmoColor.mError
              wrapMode: Text.Wrap
              pointSize: Style.fontSizeS
            }
            FileListing {
              id: listing
              Layout.fillWidth: true
              Layout.fillHeight: true
              request: root.request
              onEditPathRequested: initial => header.editPath(initial)
              onQuickLookRequested: tile => {
                var mapped = listing.mapToItem(browserArea, tile.x, tile.y, tile.width, tile.height);
                quickLook.openFrom(mapped);
              }
            }
          }
        }
        FileQuickLook {
          id: quickLook
          anchors.fill: parent
          preview: filePreview
          onCloseRequested: root.dismissLayer()
          onMoveRequested: delta => root.request.selection.move(delta, false)
        }
      }
      Rectangle { Layout.fillWidth: true; implicitHeight: Style.borderS; color: AtmoColor.mOutline }
      FileChooserFooter { id: footer; Layout.fillWidth: true; Layout.margins: Style.marginL; request: root.request; enabled: !root.quickLookOpen && !root.request.pendingReplace }
    }
    Rectangle {
      anchors.fill: parent
      visible: root.request.pendingReplace !== ""
      radius: panel.radius
      onVisibleChanged: if (visible) Qt.callLater(() => replaceButton.forceActiveFocus())
      color: Qt.alpha(AtmoColor.mSurface, 0.95)
      MouseArea { anchors.fill: parent }
      ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.margin2XL, 480 * Style.uiScaleRatio)
        spacing: Style.marginL
        AtmoIcon { Layout.alignment: Qt.AlignHCenter; icon: Icon.filepickerFile; pointSize: Style.fontSizeXXXL * 2; color: AtmoColor.mOnSurfaceVariant }
        NText { Layout.fillWidth: true; text: root.request.pendingReplace.slice(root.request.pendingReplace.lastIndexOf("/") + 1); horizontalAlignment: Text.AlignHCenter; pointSize: Style.fontSizeL }
        NText { Layout.fillWidth: true; text: I18n.tr("widgets.file-picker.overwrite-description"); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter }
        RowLayout {
          Layout.alignment: Qt.AlignHCenter
          spacing: Style.marginM
          ChooserButton { text: I18n.tr("common.cancel"); onClicked: root.request.cancel() }
          ChooserButton { id: replaceButton; text: I18n.tr("widgets.file-picker.replace"); primary: true; enabled: !root.request.busy; onClicked: root.request.confirmReplace() }
        }
      }
    }
  }
}
