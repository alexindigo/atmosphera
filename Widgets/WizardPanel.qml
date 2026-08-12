import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons

// Shared wizard chrome: breadcrumbs, model-driven step header, guaranteed
// scrollable step content, and Skip/Reset/Back/Continue footer.
//
// Steps are pure content components (ColumnLayout of controls) supplied via
// the steps model:
//   steps: [
//     { "icon": "device-desktop",          // breadcrumb + header icon
//       "label": "Dock",                   // breadcrumb + header title
//       "description": "...",              // optional header subtitle
//       "resetKey": "dock",                // optional — shows a reset button
//       "content": Component { ... } }     // the step's controls
//   ]
//
// Signals: finished() (primary button on the last step), skipped().
ColumnLayout {
  id: root

  property var steps: []
  property int currentStep: 0
  property bool showSkip: true

  signal finished()
  signal skipped()

  readonly property int totalSteps: steps.length
  readonly property var currentStepData: (currentStep >= 0 && currentStep < totalSteps) ? steps[currentStep] : ({})

  spacing: Style.marginL

  // -----------------------------------------------------
  // Breadcrumbs
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS
    visible: root.totalSteps > 1

    Repeater {
      model: root.steps

      delegate: RowLayout {
        spacing: Style.marginS

        Rectangle {
          width: 24
          height: 24
          radius: width / 2
          color: index <= root.currentStep ? Color.mPrimary : Color.mSurfaceVariant
          border.color: index === root.currentStep ? Color.mPrimary : "transparent"
          border.width: index === root.currentStep ? 2 : 0

          AtmoIcon {
            anchors.centerIn: parent
            icon: modelData.icon || ""
            pointSize: Style.fontSizeS
            color: index <= root.currentStep ? Color.mOnPrimary : Color.mOnSurfaceVariant
          }
        }

        NText {
          text: modelData.label || ""
          pointSize: Style.fontSizeS
          color: index <= root.currentStep ? Color.mPrimary : Color.mOnSurfaceVariant
          font.weight: index === root.currentStep ? Style.fontWeightBold : Style.fontWeightRegular
        }

        Rectangle {
          width: 40
          height: 2
          radius: 1
          color: index < root.currentStep ? Color.mPrimary : Color.mSurfaceVariant
          visible: index < root.totalSteps - 1
        }
      }
    }
  }

  // Divider
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 1
    color: Color.mOutline
    opacity: 0.2
    visible: root.totalSteps > 1
  }

  // -----------------------------------------------------
  // Step header (icon + title + description from the model)
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    visible: (root.currentStepData.label || "") !== ""

    Rectangle {
      width: 40
      height: 40
      radius: Style.radiusL
      color: Color.mSurfaceVariant
      opacity: 0.6
      visible: (root.currentStepData.icon || "") !== ""

      AtmoIcon {
        icon: root.currentStepData.icon || ""
        pointSize: Style.fontSizeL
        color: Color.mPrimary
        anchors.centerIn: parent
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: root.currentStepData.label || ""
        pointSize: Style.fontSizeXL
        font.weight: Style.fontWeightBold
        color: Color.mPrimary
      }

      NText {
        text: root.currentStepData.description || ""
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
        visible: (root.currentStepData.description || "") !== ""
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }
  }

  // -----------------------------------------------------
  // Step content — every step is scrollable by construction
  Item {
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: Math.round(200 * Style.uiScaleRatio)

    StackLayout {
      id: stepStack
      anchors.fill: parent
      currentIndex: root.currentStep

      Repeater {
        model: root.steps

        delegate: NScrollView {
          id: stepScrollView
          horizontalPolicy: ScrollBar.AlwaysOff
          verticalPolicy: ScrollBar.AsNeeded

          Loader {
            width: stepScrollView.availableWidth
            // At least viewport height: lets short steps center their content
            // within the visible area; tall steps scroll via implicitHeight.
            height: Math.max(implicitHeight, stepScrollView.availableHeight)
            sourceComponent: modelData.content
          }
        }
      }
    }
  }

  // Divider
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 1
    color: Color.mOutline
    opacity: 0.2
  }

  // -----------------------------------------------------
  // Footer controls
  RowLayout {
    Layout.fillWidth: true
    Layout.preferredHeight: 44

    NButton {
      text: I18n.tr("setup.skip-setup")
      outlined: true
      Layout.preferredHeight: 44
      visible: root.showSkip
      onClicked: root.skipped()
    }

    NButton {
      icon: "restore"
      tooltipText: I18n.tr("common.reset-to-default")
      outlined: true
      Layout.preferredHeight: 44
      visible: (root.currentStepData.resetKey || "") !== ""
      onClicked: Settings.resetSection(root.currentStepData.resetKey)
    }

    Item {
      Layout.fillWidth: true
    }

    NButton {
      text: "← " + I18n.tr("common.back")
      outlined: true
      visible: root.currentStep > 0
      Layout.preferredHeight: 44
      onClicked: {
        if (root.currentStep > 0) {
          root.currentStep--;
        }
      }
    }

    NButton {
      text: root.currentStep === root.totalSteps - 1 ? I18n.tr("setup.all-done") : I18n.tr("common.continue") + " →"
      Layout.preferredHeight: 44
      onClicked: {
        if (root.currentStep < root.totalSteps - 1) {
          root.currentStep++;
        } else {
          root.finished();
        }
      }
    }
  }
}
