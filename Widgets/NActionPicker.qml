import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.Actions
import qs.Widgets

// One command string bound to ActionRegistry: an action field plus the
// argument rows of the matched action. The fields are NSearchableComboBox
// instances; this component only matches, composes and lays them out.
ColumnLayout {
  id: root

  property string command: ""
  property string fieldObjectName: ""
  property string popupTitle: I18n.tr("widgets.action-picker.popup-title")

  readonly property var matched: ActionRegistry.match(command)
  readonly property string actionKey: matched ? matched.action.key : ""
  // Keep argument delegates alive while only argument values change.
  readonly property var action: actionByKey(actionKey)
  readonly property bool customDirty: actionField.customDirty

  signal commandChosen(string command)

  spacing: Style.marginS
  Layout.fillWidth: true
  Layout.minimumWidth: 0

  function commitCustomEditor() {
    actionField.commitCustomEditor();
  }

  function actionByKey(key) {
    var actions = ActionRegistry.actions;
    for (var i = 0; i < actions.length; i++)
      if (actions[i].key === key)
        return actions[i];
    return null;
  }

  function chooseArgument(name, value) {
    if (!matched)
      return;
    var values = Object.assign({}, matched.values);
    values[name] = value;
    var composed = ActionRegistry.compose(action, values);
    if (composed !== "")
      root.commandChosen(composed);
  }

  ListModel {
    id: actionModel
  }
  function rebuildModel() {
    actionModel.clear();
    ActionRegistry.actions.forEach(function (action) {
      actionModel.append({
                           key: action.key,
                           name: action.label,
                           description: action.description,
                           icon: action.icon,
                           section: action.section,
                           group: action.group,
                           command: action.command
                         });
    });
  }
  Connections {
    target: ActionRegistry
    function onRevisionChanged() {
      root.rebuildModel();
    }
  }
  Component.onCompleted: rebuildModel()

  NSearchableComboBox {
    id: actionField
    objectName: root.fieldObjectName
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    stacked: true
    selectOnNavigation: false
    clearable: true
    customEntry: true
    popupHeight: 360
    model: actionModel
    currentKey: root.actionKey
    displayIcon: root.matched ? root.matched.action.icon : root.command !== "" ? "terminal" : "circle-dashed"
    displayText: root.matched ? ActionRegistry.displayLabel(root.matched.action, root.matched.values) : root.command !== "" ? I18n.tr("widgets.action-picker.custom-command") : ""
    displaySubtitle: root.command
    placeholder: I18n.tr("widgets.action-picker.placeholder")
    sectionRole: "section"
    groupRole: "group"
    searchRoles: ["name", "description", "command"]
    popupTitle: root.popupTitle
    searchPlaceholder: I18n.tr("widgets.action-picker.search-placeholder")
    noMatchLabel: I18n.tr("widgets.action-picker.no-match")
    runCommandLabel: I18n.tr("widgets.action-picker.run-command")
    runCommandDescription: I18n.tr("widgets.action-picker.run-command-description")
    customEntryLabel: I18n.tr("widgets.action-picker.custom-entry")
    customEditorTitle: I18n.tr("widgets.action-picker.custom-command")
    customEditorConfirmText: I18n.tr("widgets.action-picker.use-command")
    customEditorCancelText: I18n.tr("common.cancel")
    customText: root.command
    onSelected: key => {
      var action = root.actionByKey(key);
      if (action)
        root.commandChosen(ActionRegistry.compose(action, {}));
    }
    onCustomEntered: text => root.commandChosen(text)
    onCleared: root.commandChosen("")
  }

  Repeater {
    model: root.action ? root.action.arguments : []
    delegate: RowLayout {
      id: argumentRow
      required property var modelData
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      spacing: Style.marginM
      NText {
        text: argumentRow.modelData.label
        Layout.maximumWidth: root.width / 3
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
      }
      Loader {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        sourceComponent: argumentRow.modelData.type === "choice" ? choiceEditor : valueEditor
      }
      Component {
        id: choiceEditor
        NSearchableComboBox {
          objectName: root.fieldObjectName + "-" + argumentRow.modelData.name
          stacked: true
          searchable: false
          selectOnNavigation: false
          popupTitle: argumentRow.modelData.label
          currentKey: root.matched ? String(root.matched.values[argumentRow.modelData.name]) : ""
          model: ListModel {
            id: choices
          }
          Component.onCompleted: argumentRow.modelData.choices.forEach(function (choice) {
            choices.append({
                             key: choice.value,
                             name: choice.label
                           });
          })
          onSelected: key => root.chooseArgument(argumentRow.modelData.name, key)
        }
      }
      Component {
        id: valueEditor
        Rectangle {
          // The validation frame owns its outline; the input owns editing.
          objectName: root.fieldObjectName + "-" + argumentRow.modelData.name
          implicitHeight: valueInput.implicitHeight + Style.borderS * 2
          color: "transparent"
          radius: Style.iRadiusM
          border.width: Style.borderS
          border.color: valueInput.inputItem.acceptableInput ? "transparent" : AtmoColor.mError
          NTextInput {
            id: valueInput
            anchors.fill: parent
            anchors.margins: Style.borderS
            minimumInputWidth: 0
            text: root.matched ? String(root.matched.values[argumentRow.modelData.name]) : ""
            inputItem.validator: argumentRow.modelData.type === "number" ? numberValidator : null
            inputMethodHints: argumentRow.modelData.type === "number" ? Qt.ImhDigitsOnly : Qt.ImhNone
            onTextEdited: {
              if (inputItem.acceptableInput)
                root.chooseArgument(argumentRow.modelData.name, argumentRow.modelData.type === "number" ? Number(text) : text);
            }
            IntValidator {
              id: numberValidator
              bottom: argumentRow.modelData.min === undefined ? -2147483648 : argumentRow.modelData.min
              top: argumentRow.modelData.max === undefined ? 2147483647 : argumentRow.modelData.max
            }
          }
        }
      }
    }
  }
}
