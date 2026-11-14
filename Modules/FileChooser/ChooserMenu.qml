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
  signal triggered(var entry)
  width: 280 * Style.uiScaleRatio
  padding: Style.marginS
  focus: true
  implicitHeight: Math.min(body.implicitHeight + topPadding + bottomPadding, 320 * Style.uiScaleRatio)
  closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
  onOpened: {
    rows.currentIndex = 0;
    body.forceActiveFocus();
  }
  onClosed: if (returnFocus && returnFocus.visible && returnFocus.enabled)
              returnFocus.forceActiveFocus()
  function activate(index) {
    var entry = entries[index];
    if (entry) {
      close();
      triggered(entry);
    }
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
    Accessible.name: root.title
    spacing: Style.marginS
    Keys.onPressed: event => {
      if (event.key === Qt.Key_Down)
        rows.currentIndex = Math.min(root.entries.length - 1, rows.currentIndex + 1);
      else if (event.key === Qt.Key_Up)
        rows.currentIndex = Math.max(0, rows.currentIndex - 1);
      else if (event.key === Qt.Key_Home)
        rows.currentIndex = 0;
      else if (event.key === Qt.Key_End)
        rows.currentIndex = root.entries.length - 1;
      else if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key))
        root.activate(rows.currentIndex);
      else {
        event.accepted = false;
        return;
      }
      event.accepted = true;
    }
    NText {
      Layout.fillWidth: true
      Layout.margins: Style.marginS
      text: root.title
      pointSize: Style.fontSizeM
      elide: Text.ElideRight
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
      implicitHeight: Math.min(contentHeight, 240 * Style.uiScaleRatio)
      clip: true
      model: root.entries
      onCurrentIndexChanged: if (currentIndex >= 0)
                               positionViewAtIndex(currentIndex, ListView.Contain)
      ScrollIndicator.vertical: ScrollIndicator {}
      delegate: ItemDelegate {
        id: menuEntry
        required property var modelData
        required property int index
        width: rows.width
        highlighted: rows.currentIndex === index
        Accessible.role: Accessible.MenuItem
        Accessible.name: modelData.name
        contentItem: NText {
          text: menuEntry.modelData.name
          elide: Text.ElideMiddle
          pointSize: Style.fontSizeM
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
