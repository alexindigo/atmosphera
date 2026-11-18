import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

GridLayout {
  id: root

  property real minimumWidth: 280
  property real popupHeight: 180

  property bool selectOnNavigation: true
  property string label: ""
  property string description: ""
  property bool stacked: false
  property ListModel model: ListModel {}
  property string currentKey: ""
  property string placeholder: ""
  property string searchPlaceholder: I18n.tr("placeholders.search")
  property Component delegate: null
  property var defaultValue: undefined
  property string settingsPath: ""

  property string displayIcon: ""
  property string displayText: ""
  property string displaySubtitle: ""
  property bool clearable: false
  property string popupTitle: ""
  property bool searchable: true
  property string sectionRole: ""
  property string groupRole: ""
  property var searchRoles: ["name"]
  property bool customEntry: false
  property string noMatchLabel: ""
  property string runCommandLabel: "Run command: %1"
  property string runCommandDescription: "Use exactly this text as a shell command."
  property string customEntryLabel: "Custom command..."
  property string customEditorTitle: "Custom command"
  property string customEditorConfirmText: "Use command"
  property string customEditorCancelText: "Cancel"
  property string customText: ""
  readonly property bool hasValue: currentKey !== "" || displayText !== ""
  readonly property bool customEditing: customEditor.visible
  readonly property bool customDirty: customEditing && customInput.text.trim() !== customText.trim()
  readonly property int _sourceIndex: findIndexByKey(currentKey)
  readonly property var _sourceRow: model && _sourceIndex >= 0 ? model.get(_sourceIndex) : null
  readonly property string _closedText: displayText || (_sourceRow ? _sourceRow.name : placeholder)
  readonly property string _closedIcon: displayIcon || (_sourceRow && _sourceRow.icon ? _sourceRow.icon : "")
  readonly property bool _runEntry: customEntry && searchText.trim() !== "" && (!activeModel || activeModel.count === 0)
  readonly property int _choiceCount: _runEntry ? 1 : (activeModel ? activeModel.count : 0)
  property int _highlight: 0
  // The index is presentation only. Preserve the choice's identity across
  // source mutation, never whatever happens to occupy its previous index.
  property var _highlightChoice: null
  property bool _filterPending: false
  property Timer _filterTurn: Timer {
    interval: 0
    onTriggered: root.filterModel()
  }

  readonly property real preferredHeight: Math.round(Style.baseWidgetSize * 1.1)

  signal selected(string key)
  signal cleared
  signal customEntered(string text)

  // A choice supersedes the editor's draft in every consumer. Apply may only
  // commit a draft which has not since been replaced by selection or Clear.
  onSelected: {
    if (customEditing)
      cancelCustomEditor();
  }
  onCleared: {
    if (customEditing)
      cancelCustomEditor();
  }
  onCustomEntered: {
    if (customEditing)
      cancelCustomEditor();
  }

  component SectionBand: Rectangle {
    required property string section
    implicitHeight: sectionText.implicitHeight + Style.marginS * 2
    color: AtmoColor.mSurface
    radius: Style.iRadiusS
    NText {
      id: sectionText
      anchors.fill: parent
      anchors.margins: Style.marginS
      text: parent.section
      color: AtmoColor.mPrimary
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
    }
  }

  component ChoiceCopy: RowLayout {
    id: copy
    property string iconName: ""
    property string primaryText: ""
    property string secondaryText: ""
    property color foreground: AtmoColor.mOnSurface
    spacing: Style.marginM
    AtmoIcon {
      visible: copy.iconName !== ""
      icon: copy.iconName
      color: copy.foreground
    }
    ColumnLayout {
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      spacing: Style.marginXXS
      NText {
        text: copy.primaryText
        pointSize: Style.fontSizeM
        color: copy.foreground
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        Layout.fillWidth: true
        wrapMode: Text.NoWrap
      }
      NText {
        visible: copy.secondaryText !== ""
        text: copy.secondaryText
        pointSize: Style.fontSizeS
        color: copy.foreground
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
        Layout.fillWidth: true
      }
    }
  }

  function openCustomEditor() {
    combo.popup.close();
    customInput.text = root.customText;
    customEditor.visible = true;
    Qt.callLater(function () {
      if (customEditor.visible)
        customInput.inputItem.forceActiveFocus();
    });
  }

  function commitCustomEditor() {
    if (!customEditor.visible)
      return;
    var text = customInput.text.trim();
    customEditor.visible = false;
    root.customEntered(text);
    combo.forceActiveFocus();
  }

  function cancelCustomEditor() {
    customEditor.visible = false;
    combo.forceActiveFocus();
  }

  function selectSearchCommand() {
    if (_filterPending || !_runEntry)
      return;
    root.customEntered(searchText.trim());
    combo.popup.close();
  }

  function selectHighlighted() {
    if (_filterPending)
      return;
    if (customEntry && _highlight === _choiceCount) {
      openCustomEditor();
    } else if (_runEntry && _highlight === 0) {
      selectSearchCommand();
    } else if (activeModel && _highlight >= 0 && _highlight < activeModel.count) {
      selectChoice(_highlight);
    }
  }

  function selectChoice(index) {
    if (_filterPending || !activeModel || index < 0 || index >= activeModel.count)
      return;
    root.selected(activeModel.get(index).key);
    combo.popup.close();
  }

  function navigate(delta) {
    if (_filterPending)
      return;
    var last = _choiceCount - 1 + (customEntry ? 1 : 0);
    var previous = _highlight;
    _highlight = last < 0 ? -1 : Math.max(0, Math.min(last, _highlight + delta));
    if (_highlight !== previous && selectOnNavigation && !_runEntry && _highlight >= 0 && _highlight < _choiceCount)
      root.selected(activeModel.get(_highlight).key);
  }

  function handlePopupKey(event) {
    if (Keybinds.checkKey(event, 'enter', Settings))
      selectHighlighted();
    else if (Keybinds.checkKey(event, 'escape', Settings))
      combo.popup.close();
    else if (Keybinds.checkKey(event, 'up', Settings))
      navigate(-1);
    else if (Keybinds.checkKey(event, 'down', Settings))
      navigate(1);
    else
      return;
    event.accepted = true;
  }

  on_HighlightChanged: {
    rememberHighlight();
    listView.currentIndex = _highlight < (activeModel ? activeModel.count : 0) ? _highlight : -1;
  }

  function rememberHighlight() {
    if (customEntry && _highlight === _choiceCount)
      _highlightChoice = {kind: "footer"};
    else if (_runEntry && _highlight === 0)
      _highlightChoice = {kind: "command", text: searchText.trim()};
    else if (activeModel && _highlight >= 0 && _highlight < activeModel.count)
      _highlightChoice = {kind: "row", key: activeModel.get(_highlight).key};
    else
      _highlightChoice = null;
  }

  function scheduleFilter() {
    _filterPending = true;
    _filterTurn.restart();
  }

  columns: root.stacked ? 1 : 2
  flow: root.stacked ? GridLayout.TopToBottom : GridLayout.LeftToRight
  columnSpacing: root.stacked ? 0 : Style.marginL
  rowSpacing: root.stacked ? Style.marginM : 0
  Layout.fillWidth: true

  readonly property bool isValueChanged: (defaultValue !== undefined) && (currentKey !== defaultValue)
  readonly property string indicatorTooltip: {
    if (defaultValue === undefined)
      return "";
    var displayValue = "";
    if (defaultValue === "") {
      // Try to find the display name for empty key in the model
      if (model && model.count > 0) {
        for (var i = 0; i < model.count; i++) {
          var item = model.get(i);
          if (item && item.key === "") {
            displayValue = item.name || I18n.tr("panels.indicator.system-default");
            break;
          }
        }
        // If not found in model, show "System Default" instead of "(empty)"
        if (displayValue === "") {
          displayValue = I18n.tr("panels.indicator.system-default");
        }
      } else {
        displayValue = I18n.tr("panels.indicator.system-default");
      }
    } else {
      // Try to find the display name for the default key in the model
      if (model && model.count > 0) {
        for (var i = 0; i < model.count; i++) {
          var item = model.get(i);
          if (item && item.key === defaultValue) {
            displayValue = item.name || String(defaultValue);
            break;
          }
        }
        if (displayValue === "") {
          displayValue = String(defaultValue);
        }
      } else {
        displayValue = String(defaultValue);
      }
    }
    return I18n.tr("panels.indicator.default-value", {
                     "value": displayValue
                   });
  }

  // Filtered model for search results
  property ListModel filteredModel: ListModel {}
  property string searchText: ""

  function findIndexByKey(key) {
    if (!root.model)
      return -1;
    for (var i = 0; i < root.model.count; i++) {
      if (root.model.get(i).key === key) {
        return i;
      }
    }
    return -1;
  }

  // The active model used for the popup list (source model or filtered results)
  readonly property var activeModel: isFiltered ? filteredModel : root.model

  function findIndexInActiveModel(key) {
    if (!activeModel || activeModel.count === undefined)
      return -1;
    for (var i = 0; i < activeModel.count; i++) {
      if (activeModel.get(i).key === key) {
        return i;
      }
    }
    return -1;
  }

  // Whether we're using filtered results or the source model directly
  property bool isFiltered: false

  function filterModel() {
    var choice = _highlightChoice;
    _filterTurn.stop();
    rebuildFilteredModel();
    if (choice && choice.kind === "footer" && customEntry)
      _highlight = _choiceCount;
    else if (choice && choice.kind === "command" && _runEntry && choice.text === searchText.trim())
      _highlight = 0;
    else if (choice && choice.kind === "row" && !_runEntry)
      _highlight = findIndexInActiveModel(choice.key);
    else
      _highlight = -1;
    rememberHighlight();
    listView.currentIndex = !_runEntry && _highlight >= 0 && _highlight < _choiceCount ? _highlight : -1;
    _filterPending = false;
  }

  function rebuildFilteredModel() {
    // Check if model exists and has items
    if (!root.model || root.model.count === undefined || root.model.count === 0) {
      filteredModel.clear();
      isFiltered = false;
      return;
    }

    var query = searchText.trim();
    if (query === "") {
      // No search text - use source model directly, don't copy
      filteredModel.clear();
      isFiltered = false;
      return;
    }

    // We have search text - need to filter
    isFiltered = true;
    filteredModel.clear();

    // Convert ListModel to array for fuzzy search
    var items = [];
    for (var i = 0; i < root.model.count; i++) {
      items.push(root.model.get(i));
    }

    // Sectioned lists preserve source order and group ownership while searching.
    if (root.sectionRole !== "") {
      var terms = query.toLowerCase().split(/\s+/);
      items.forEach(function (item) {
        var haystack = root.searchRoles.map(function (role) {
          return String(item[role] || "").toLowerCase();
        }).join(" ");
        if (terms.every(function (term) {
          return haystack.indexOf(term) >= 0;
        }))
          root.filteredModel.append(item);
      });
    } else if (typeof FuzzySort !== 'undefined') {
      var fuzzyResults = FuzzySort.go(query, items, {
                                        "key": "name",
                                        "limit": 50
                                      });

      // Add results in order of relevance
      for (var j = 0; j < fuzzyResults.length; j++) {
        filteredModel.append(fuzzyResults[j].obj);
      }
    } else {
      // Fallback to simple search
      var searchLower = query.toLowerCase();
      for (var i = 0; i < items.length; i++) {
        var item = items[i];
        if (item.name.toLowerCase().includes(searchLower)) {
          filteredModel.append(item);
        }
      }
    }
  }

  onSearchTextChanged: {
    filterModel();
    _highlight = (_choiceCount > 0 || customEntry) ? 0 : -1;
    rememberHighlight();
  }

  onModelChanged: scheduleFilter()

  Connections {
    target: root.model
    function onCountChanged() {
      root.scheduleFilter();
    }
    function onDataChanged() {
      root.scheduleFilter();
    }
    function onRowsMoved() {
      root.scheduleFilter();
    }
    function onModelReset() {
      root.scheduleFilter();
    }
  }

  NLabel {
    Layout.fillWidth: true
    label: root.label
    description: root.description
    showIndicator: root.isValueChanged
    indicatorTooltip: root.indicatorTooltip
  }

  ComboBox {
    id: combo

    opacity: enabled ? 1.0 : 0.6
    Layout.fillWidth: root.stacked
    Layout.margins: root.stacked ? 0 : Style.borderS
    Layout.minimumWidth: root.stacked ? 0 : Math.round(root.minimumWidth * Style.uiScaleRatio)
    implicitWidth: Layout.minimumWidth
    Layout.alignment: root.stacked ? (Qt.AlignLeft | Qt.AlignTop) : Qt.AlignRight
    model: root.activeModel
    textRole: "name"
    currentIndex: findIndexInActiveModel(currentKey)
    wheelEnabled: false
    padding: 0
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
      if (!root.selectOnNavigation && !combo.popup.visible && (event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
        combo.popup.open();
        event.accepted = true;
      }
    }
    Keys.onReleased: event => {
      if (!root.selectOnNavigation && event.key === Qt.Key_Space)
        event.accepted = true;
    }
    onActivated: {
      root.selectChoice(combo.currentIndex);
    }

    background: Rectangle {
      implicitWidth: Math.round(Style.baseWidgetSize * 3.75 * Style.uiScaleRatio)
      implicitHeight: Math.round(root.preferredHeight * Style.uiScaleRatio)
      color: AtmoColor.mSurface
      border.color: combo.activeFocus ? AtmoColor.mSecondary : AtmoColor.mOutline
      border.width: Style.borderS
      radius: Style.iRadiusM

      Behavior on border.color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }
    }

    Layout.preferredHeight: Math.max(Math.round(root.preferredHeight * Style.uiScaleRatio), root.displaySubtitle !== "" ? closedCopy.implicitHeight + Style.marginM * 2 : 0)

    contentItem: RowLayout {
      spacing: 0
      Item {
        visible: root._closedIcon !== ""
        Layout.leftMargin: Style.marginL
        Layout.rightMargin: Style.marginM
        Layout.preferredWidth: leadingIcon.implicitWidth
        Layout.fillHeight: true
        AtmoIcon {
          id: leadingIcon
          anchors.centerIn: parent
          icon: root._closedIcon
          pointSize: Style.fontSizeL
          color: root.hasValue ? AtmoColor.mOnSurface : AtmoColor.mOnSurfaceVariant
        }
      }
      ColumnLayout {
        id: closedCopy
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.leftMargin: root._closedIcon === "" ? Style.marginL : 0
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.marginXXS
        NText {
          objectName: "combo-label"
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          text: root._closedText
          pointSize: Style.fontSizeM
          elide: Text.ElideRight
          wrapMode: Text.NoWrap
          color: root.hasValue || root._sourceRow ? AtmoColor.mOnSurface : AtmoColor.mOnSurfaceVariant
        }
        NText {
          objectName: "combo-subtitle"
          visible: root.displaySubtitle !== ""
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          text: root.displaySubtitle
          family: Settings.data.ui.fontFixed
          pointSize: Style.fontSizeXS
          elide: Text.ElideRight
          wrapMode: Text.NoWrap
          color: AtmoColor.mOnSurface
        }
      }
      Item {
        objectName: "combo-clear-slot"
        visible: root.clearable && root.hasValue
        Layout.preferredWidth: combo.height
        Layout.preferredHeight: combo.height
        AtmoIconButton {
          anchors.centerIn: parent
          icon: Icon.close
          tooltipText: I18n.tr("common.clear")
          colorBg: "transparent"
          colorFg: AtmoColor.mOnSurface
          border.width: 0
          onClicked: root.cleared()
        }
      }
      Item {
        objectName: "combo-chevron-slot"
        Layout.preferredWidth: combo.height
        Layout.preferredHeight: combo.height
        AtmoIcon {
          anchors.centerIn: parent
          icon: Icon.caretDown
          pointSize: Style.fontSizeL
        }
      }
    }

    indicator: Item {}

    popup: Popup {
      y: combo.height + Style.marginS
      width: combo.width
      height: Math.round((root.popupHeight + 60) * Style.uiScaleRatio) + (titleBand.visible ? titleBand.implicitHeight : 0) + (customFooter.visible ? customFooter.implicitHeight : 0)
      padding: Style.marginM

      onOpened: {
        listView.forceLayout();
        listView.currentIndex = root._highlight;
        // Keep sectioned choices clear of the sticky section band.
        listView.positionViewAtIndex(listView.currentIndex, root.sectionRole !== "" ? ListView.Center : ListView.Beginning);
      }

      contentItem: ColumnLayout {
        spacing: Style.marginS
        Keys.onPressed: event => root.handlePopupKey(event)

        NText {
          id: titleBand
          objectName: "combo-popup-title"
          visible: root.popupTitle !== ""
          Layout.fillWidth: true
          Layout.bottomMargin: Style.marginS
          text: root.popupTitle
          pointSize: Style.fontSizeM
          font.weight: Style.fontWeightSemiBold
          wrapMode: Text.NoWrap
          elide: Text.ElideRight
        }

        // Search input
        NTextInput {
          id: searchInput
          visible: root.searchable
          NInputGuard {
            target: searchInput
            active: combo.popup.visible
            focusOwner: combo
            focusTarget: searchInput.inputItem
            focusOnActivation: true
          }
          inputIconName: "search"
          Layout.fillWidth: true
          placeholderText: root.searchPlaceholder
          text: root.searchText
          onTextChanged: root.searchText = text
          fontSize: Style.fontSizeS

          Keys.onPressed: event => {
            root.handlePopupKey(event);
          }
        }

        SectionBand {
          visible: root._runEntry
          Layout.fillWidth: true
          section: root.noMatchLabel
        }
        ItemDelegate {
          id: runCommandRow
          visible: root._runEntry
          Layout.fillWidth: true
          text: root.runCommandLabel.replace("%1", function () { return root.searchText.trim(); })
          highlighted: root._highlight === 0
          leftPadding: Style.marginM
          rightPadding: Style.marginM
          topPadding: Style.marginS
          bottomPadding: Style.marginS
          hoverEnabled: true
          onHoveredChanged: if (hovered)
                              root._highlight = 0
          onClicked: root.selectSearchCommand()
          contentItem: ChoiceCopy {
            iconName: "terminal"
            primaryText: runCommandRow.text
            secondaryText: root.runCommandDescription
            foreground: runCommandRow.highlighted ? AtmoColor.mOnHover : AtmoColor.mOnSurface
          }
          background: Rectangle {
            color: runCommandRow.highlighted ? AtmoColor.mHover : "transparent"
            radius: Style.iRadiusS
          }
        }

        Item {
          visible: root._runEntry
          Layout.fillHeight: true
        }

        NListView {
          id: listView
          visible: !root._runEntry
          Layout.fillWidth: true
          Layout.fillHeight: true
          // Use activeModel (source model when not filtering, filtered results when searching)
          model: combo.popup.visible ? root.activeModel : null
          horizontalPolicy: ScrollBar.AlwaysOff
          verticalPolicy: ScrollBar.AsNeeded
          section.property: root.sectionRole
          section.criteria: ViewSection.FullString
          section.labelPositioning: ViewSection.InlineLabels | ViewSection.CurrentLabelAtStart
          section.delegate: root.sectionRole !== "" ? sectionDelegate : null

          Component {
            id: sectionDelegate
            SectionBand {
              width: listView.availableWidth
            }
          }

          onCurrentIndexChanged: {
            if (combo.popup.opened && currentIndex >= 0)
              positionViewAtIndex(currentIndex, ListView.Contain);
          }

          delegate: root.delegate ? root.delegate : defaultDelegate

          Component {
            id: defaultDelegate
            Column {
              id: rowRoot
              required property int index
              required property var model
              readonly property var rowData: model
              readonly property var previousRow: index > 0 && index <= root.activeModel.count ? root.activeModel.get(index - 1) : null
              readonly property bool startsGroup: root.groupRole !== "" && (!previousRow || rowData[root.groupRole] !== previousRow[root.groupRole] || (root.sectionRole !== "" && rowData[root.sectionRole] !== previousRow[root.sectionRole]))
              width: listView.availableWidth
              NText {
                visible: rowRoot.startsGroup
                width: parent.width
                topPadding: Style.marginS
                bottomPadding: Style.marginS
                leftPadding: Style.marginM
                text: root.groupRole !== "" ? rowRoot.rowData[root.groupRole] : ""
                font.weight: Style.fontWeightSemiBold
                pointSize: Style.fontSizeS
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
              }
              ItemDelegate {
                id: delegateRoot
                width: listView.availableWidth
                leftPadding: Style.marginM
                rightPadding: Style.marginM
                topPadding: Style.marginS
                bottomPadding: Style.marginS
                hoverEnabled: true
                highlighted: root._highlight === rowRoot.index

                onHoveredChanged: {
                  if (hovered) {
                    root._highlight = rowRoot.index;
                  }
                }

                onClicked: {
                  root.selectChoice(rowRoot.index);
                }

                contentItem: RowLayout {
                  width: delegateRoot.width - delegateRoot.leftPadding - delegateRoot.rightPadding
                  spacing: Style.marginM

                  ChoiceCopy {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    iconName: rowRoot.rowData.icon || ""
                    primaryText: rowRoot.rowData.name
                    secondaryText: rowRoot.rowData.description || ""
                    foreground: delegateRoot.highlighted ? AtmoColor.mOnHover : AtmoColor.mOnSurface
                  }

                  AtmoIcon {
                    visible: root.currentKey === rowRoot.rowData.key
                    icon: Icon.check
                    color: delegateRoot.highlighted ? AtmoColor.mOnHover : AtmoColor.mOnSurface
                  }

                  RowLayout {
                    spacing: Style.marginXXS
                    Layout.alignment: Qt.AlignRight

                    // Generic badge renderer
                    Repeater {
                      model: {
                        var badges = rowRoot.rowData.badges;
                        if (badges === undefined || badges === null)
                          return 0;
                        // Handle both arrays and ListModels
                        if (typeof badges.length !== 'undefined')
                          return badges.length;
                        if (typeof badges.count !== 'undefined')
                          return badges.count;
                        return 0;
                      }

                      delegate: AtmoIcon {
                        required property int index
                        readonly property var badgeData: {
                          var badges = rowRoot.rowData.badges;
                          if (badges === undefined || badges === null)
                            return null;
                          // Handle both arrays and ListModels
                          if (typeof badges.length !== 'undefined')
                            return badges[index];
                          if (typeof badges.get !== 'undefined')
                            return badges.get(index);
                          return null;
                        }

                        icon: badgeData && badgeData.icon ? badgeData.icon : ""
                        pointSize: {
                          if (!badgeData || !badgeData.size)
                            return Style.fontSizeXS;
                          if (badgeData.size === "xsmall")
                            return Style.fontSizeXXS;
                          else if (badgeData.size === "medium")
                            return Style.fontSizeM;
                          else
                            return Style.fontSizeXS;
                        }
                        color: delegateRoot.highlighted ? AtmoColor.mOnHover : (badgeData && badgeData.color ? badgeData.color : AtmoColor.mOnSurface)
                        Layout.preferredWidth: Math.round(Style.baseWidgetSize * 0.6)
                        Layout.preferredHeight: Math.round(Style.baseWidgetSize * 0.6)
                        visible: badgeData && badgeData.icon !== undefined && badgeData.icon !== ""
                      }
                    }
                  }
                }
                background: Rectangle {
                  anchors.fill: parent
                  color: delegateRoot.highlighted ? AtmoColor.mHover : "transparent"
                  radius: Style.iRadiusS
                }
              }
            }
          }
        }

        ItemDelegate {
          id: customFooter
          objectName: "combo-custom-footer"
          visible: root.customEntry
          Layout.fillWidth: true
          highlighted: root._highlight === root._choiceCount
          hoverEnabled: true
          onHoveredChanged: if (hovered)
                              root._highlight = root._choiceCount
          onClicked: root.openCustomEditor()
          contentItem: RowLayout {
            AtmoIcon {
              icon: "terminal"
            }
            NText {
              text: root.customEntryLabel
              Layout.fillWidth: true
              wrapMode: Text.NoWrap
              elide: Text.ElideRight
            }
          }
          background: Rectangle {
            color: customFooter.highlighted ? AtmoColor.mHover : "transparent"
            radius: Style.iRadiusS
          }
        }
      }

      background: Rectangle {
        color: AtmoColor.mSurfaceVariant
        border.color: AtmoColor.mOutline
        border.width: Style.borderS
        radius: Style.iRadiusM
      }
    }

    // Update the currentIndex if the currentKey is changed externally
    Connections {
      target: root
      function onCurrentKeyChanged() {
        combo.currentIndex = root.findIndexInActiveModel(root.currentKey);
      }
    }

    // Focus search input when popup opens and ensure model is filtered
    Connections {
      target: combo.popup
      function onVisibleChanged() {
        if (combo.popup.visible) {
          // Ensure the model is filtered when popup opens
          filterModel();
          root._highlight = Math.max(0, root.findIndexInActiveModel(root.currentKey));
          root.rememberHighlight();
          listView.currentIndex = root._highlight;
          // Small delay to ensure the popup is fully rendered
          Qt.callLater(() => {
            if (root.searchable && searchInput && searchInput.inputItem) {
              searchInput.inputItem.forceActiveFocus();
            } else if (combo.popup.visible) {
              combo.popup.contentItem.forceActiveFocus();
            }
          });
        } else {
          root.searchText = "";
        }
      }
    }
  }

  Rectangle {
    id: customEditor
    objectName: "combo-custom-editor"
    visible: false
    Layout.columnSpan: root.columns
    Layout.fillWidth: true
    implicitHeight: editorColumn.implicitHeight + Style.marginM * 2
    color: AtmoColor.mSurfaceVariant
    radius: Style.iRadiusM
    border.color: AtmoColor.mOutline
    border.width: Style.borderS
    ColumnLayout {
      id: editorColumn
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM
      NText {
        text: root.customEditorTitle
        Layout.fillWidth: true
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
        font.weight: Style.fontWeightSemiBold
      }
      NTextInput {
        id: customInput
        Layout.fillWidth: true
        fontFamily: Settings.data.ui.fontFixed
        onAccepted: root.commitCustomEditor()
        Keys.onEscapePressed: event => {
          root.cancelCustomEditor();
          event.accepted = true;
        }
      }
      RowLayout {
        Layout.alignment: Qt.AlignRight
        NButton {
          text: root.customEditorCancelText
          outlined: true
          onClicked: root.cancelCustomEditor()
        }
        NButton {
          text: root.customEditorConfirmText
          onClicked: root.commitCustomEditor()
        }
      }
    }
  }
}
