import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Files
import qs.Widgets

// Both location and filename entry share completion presentation and input
// handling. The service supplies suggestions; the consumer handles submission.
ChooserTextField {
  id: root
  property string basePath: ""
  property bool directoriesOnly: false
  property bool showHidden: false
  property var nameFilter: null
  readonly property var suggestions: completion.suggestions
  readonly property bool completionOpen: matches.visible
  property bool _offered: false
  property int _current: -1
  on_CurrentChanged: {
    if (_current >= 0 && suggestions[_current])
      inputItem.Accessible.announce(suggestions[_current].name);
  }
  onTextEdited: { _offered = true; _current = -1; }
  function dismissCompletion() { _offered = false; matches.close(); }
  function completionGeometry(relativeTo) {
    var result = [];
    if (matches.visible) {
      for (var i = 0; i < rows.count; i++) {
        var row = rows.itemAtIndex(i);
        if (!row) continue;
        var p = row.mapToItem(relativeTo, 0, 0);
        result.push({x: p.x, y: p.y, width: row.width, height: row.height, name: suggestions[i].name});
      }
    }
    return result;
  }
  function chooseCompletion(index) {
    var entry = suggestions[index];
    if (!entry) return;
    text = entry.text;
    inputItem.cursorPosition = text.length;
    textEdited();
    dismissCompletion();
    inputItem.forceActiveFocus();
  }
  FileCompletion {
    id: completion
    text: root.text
    basePath: root.basePath
    directoriesOnly: root.directoriesOnly
    showHidden: root.showHidden
    nameFilter: root.nameFilter
    active: root.visible && root.inputItem.activeFocus
    onSuggestionsChanged: {
      if (root._offered && suggestions.length && root.inputItem.activeFocus) matches.open();
      else matches.close();
    }
  }
  Connections {
    target: root.inputItem
    function onActiveFocusChanged() { if (!root.inputItem.activeFocus) root.dismissCompletion(); }
  }
  onKeyPressed: event => {
      if (event.key === Qt.Key_Down && root.suggestions.length) {
        root._offered = true;
        matches.open();
        root._current = Math.min(root.suggestions.length - 1, root._current + 1);
        event.accepted = true;
      } else if (event.key === Qt.Key_Up && matches.visible) {
        root._current = Math.max(0, root._current - 1);
        event.accepted = true;
      } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && matches.visible && (root._current >= 0 || event.key === Qt.Key_Tab)) {
        root.chooseCompletion(Math.max(0, root._current));
        event.accepted = true;
      } else event.accepted = false;
  }
  Popup {
    id: matches
    y: root.height
    width: root.width
    padding: Style.marginS
    focus: false
    implicitHeight: Math.min(rows.contentHeight, 240 * Style.uiScaleRatio) + Style.margin2S
    closePolicy: Popup.CloseOnPressOutside
    background: Rectangle { color: AtmoColor.mSurfaceVariant; radius: Style.iRadiusS; border.color: AtmoColor.mOutline; border.width: Style.borderS }
    contentItem: ListView {
      id: rows
      Accessible.role: Accessible.List
      Accessible.name: I18n.tr("widgets.file-picker.path-matches")
      clip: true
      model: root.suggestions
      currentIndex: root._current
      onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
      ScrollIndicator.vertical: ScrollIndicator {}
      delegate: ItemDelegate {
        id: completionRow
        required property var modelData
        required property int index
        width: rows.width
        focusPolicy: Qt.NoFocus
        highlighted: root._current === index
        Accessible.role: Accessible.ListItem
        Accessible.name: modelData.name
        Accessible.selected: root._current === index
        contentItem: NText { text: completionRow.modelData.name + (completionRow.modelData.directory ? "/" : ""); elide: Text.ElideMiddle; pointSize: Style.fontSizeM }
        background: Rectangle { radius: Style.iRadiusXS; color: completionRow.highlighted ? Qt.alpha(AtmoColor.mPrimary, 0.18) : "transparent" }
        onClicked: root.chooseCompletion(index)
      }
    }
  }
}
