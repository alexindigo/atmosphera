import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

import "Helpers/LauncherSelection.js" as LauncherSelection
import qs.Commons
import qs.Widgets

Item {
  id: gridEntryContainer

  // Keyed view row {key, row}; the delegate lives as long as its key does.
  required property var modelData
  required property int index
  required property var launcher
  // The launcher's result object for this row (refreshed in place by a keyed update).
  readonly property var row: modelData && modelData.row ? modelData.row : ({})

  width: GridView.view.cellWidth
  height: GridView.view.cellHeight

  readonly property bool isSelected: index === launcher.selectedIndex

  // Prepare each item once while it is shown (e.g., decode images). A kept
  // delegate prepares again only if its row now stands for another item.
  property var preparedRow: null
  function prepare() {
    if (preparedRow && LauncherSelection.sameIdentity(preparedRow, row))
      return;
    preparedRow = row;
    var provider = row.provider;
    if (provider && provider.prepareItem) {
      provider.prepareItem(row);
    }
  }
  Component.onCompleted: prepare()
  onRowChanged: prepare()

  NBox {
    id: gridEntry
    anchors.fill: parent
    anchors.margins: Style.marginXXS
    color: gridEntryContainer.isSelected ? AtmoColor.mHover : AtmoColor.mSurfaceVariant
    forceOpaque: gridEntryContainer.isSelected

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCirc
      }
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: launcher.isCompactDensity ? Style.marginXS : Style.marginS
      anchors.bottomMargin: launcher.isCompactDensity ? Style.marginXS : Style.marginS
      spacing: launcher.isCompactDensity ? 0 : Style.marginXXS

      // Icon badge or Image preview or Emoji
      Item {
        id: gridBadge
        // Size image at 65% of cell dimensions.
        Layout.preferredWidth: Math.round(gridEntry.width * 0.65)
        Layout.preferredHeight: Math.round(gridEntry.height * 0.65)
        Layout.alignment: Qt.AlignHCenter
        // Image parts exist only for image rows; their state is read from here.
        readonly property int imageStatus: gridImageLoader.item ? gridImageLoader.item.status : Image.Null
        readonly property bool imageShown: gridImageLoader.item ? gridImageLoader.item.visible : false

        // Icon background
        Rectangle {
          anchors.fill: parent
          radius: Style.radiusM
          color: AtmoColor.mSurface
          visible: Settings.data.appLauncher.showIconBackground && !row.isImage
        }

        // Image preview - uses provider's getImageUrl if available
        Loader {
          id: gridImageLoader
          anchors.fill: parent
          active: !!row.isImage
          sourceComponent: NImageRounded {
            // A failed image falls back to the icon, declaratively: a kept delegate
            // follows its row instead of a state written once at creation.
            visible: !row.displayString && status !== Image.Error
            radius: Style.radiusM

            // Use provider's image revision for reactive updates
            readonly property int _rev: row.provider && row.provider.imageRevision ? row.provider.imageRevision : 0

            // Passing the revision makes cache invalidation a binding input.
            imagePath: imageUrlForRevision(_rev)

            function imageUrlForRevision(revision) {
              var provider = row.provider;
              if (provider && provider.getImageUrl) {
                return provider.getImageUrl(row);
              }
              return "";
            }

            Rectangle {
              anchors.fill: parent
              visible: parent.status === Image.Loading
              color: AtmoColor.mSurfaceVariant

              BusyIndicator {
                anchors.centerIn: parent
                running: true
                width: Style.baseWidgetSize * 0.5
                height: width
              }
            }
          }
        }

        Loader {
          id: gridIconLoader
          anchors.fill: parent
          anchors.margins: Style.marginXS

          visible: (!row.isImage && !row.displayString) || (!!row.isImage && gridBadge.imageStatus === Image.Error)
          active: visible

          sourceComponent: Settings.data.appLauncher.iconMode === "tabler" && row.isTablerIcon ? gridTablerIconComponent : gridSystemIconComponent

          Component {
            id: gridTablerIconComponent
            AtmoIcon {
              icon: row.icon
              pointSize: Style.fontSizeXXXL
              visible: row.icon && !row.displayString
              color: (gridEntryContainer.isSelected && !Settings.data.appLauncher.showIconBackground) ? AtmoColor.mOnHover : AtmoColor.mOnSurface
            }
          }

          Component {
            id: gridSystemIconComponent
            AtmoAppIcon {
              anchors.fill: parent
              name: row.icon || ""
              visible: row.icon && !row.displayString
            }
          }
        }

        // String display
        NText {
          id: gridStringDisplay
          anchors.centerIn: parent
          visible: !!row.displayString || (!gridBadge.imageShown && !gridIconLoader.visible)
          text: row.displayString ? row.displayString : (row.name ? row.name.charAt(0).toUpperCase() : "?")
          pointSize: {
            if (row.displayString) {
              // Use custom size if provided, otherwise default scaling
              if (row.displayStringSize) {
                return row.displayStringSize * Style.uiScaleRatio;
              }
              if (launcher.providerHasDisplayString) {
                // Scale with cell width but cap at reasonable maximum
                const cellBasedSize = gridEntry.width * 0.4;
                const maxSize = Style.fontSizeXXXL * Style.uiScaleRatio;
                return Math.min(cellBasedSize, maxSize);
              }
              return Style.fontSizeXXL * 2 * Style.uiScaleRatio;
            }
            // Scale font size relative to cell width for low res, but cap at maximum
            const cellBasedSize = gridEntry.width * 0.25;
            const baseSize = Style.fontSizeXL * Style.uiScaleRatio;
            const maxSize = Style.fontSizeXXL * Style.uiScaleRatio;
            return Math.min(Math.max(cellBasedSize, baseSize), maxSize);
          }
          font.weight: Style.fontWeightBold
          color: row.displayString ? AtmoColor.mOnSurface : AtmoColor.mOnPrimary
        }

        // Badge icon overlay (generic indicator for any provider)
        Loader {
          active: !!row.badgeIcon
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          anchors.margins: 2
          sourceComponent: Rectangle {
            width: height
            height: Style.fontSizeM + Style.marginXS
            color: AtmoColor.mSurfaceVariant
            radius: Style.radiusXXS
            AtmoIcon {
              anchors.centerIn: parent
              icon: row.badgeIcon || ""
              pointSize: Style.fontSizeS
              color: AtmoColor.mOnSurfaceVariant
            }
          }
        }
      }

      // Text content (hidden when hideLabel is true)
      NText {
        visible: !row.hideLabel
        text: row.name || "Unknown"
        pointSize: {
          if (launcher.providerHasDisplayString && row.displayString) {
            return Style.fontSizeS * Style.uiScaleRatio;
          }
          // Scale font size relative to cell width for low res, but cap at maximum
          const cellBasedSize = gridEntry.width * 0.1;
          const baseSize = Style.fontSizeXS * Style.uiScaleRatio;
          const maxSize = Style.fontSizeS * Style.uiScaleRatio;
          return Math.min(Math.max(cellBasedSize, baseSize), maxSize);
        }
        font.weight: Style.fontWeightSemiBold
        color: gridEntryContainer.isSelected ? AtmoColor.mOnHover : AtmoColor.mOnSurface
        elide: Text.ElideRight
        Layout.fillWidth: true
        Layout.maximumWidth: gridEntry.width - 8
        Layout.leftMargin: (launcher.providerHasDisplayString && row.displayString) ? Style.marginS : 0
        Layout.rightMargin: (launcher.providerHasDisplayString && row.displayString) ? Style.marginS : 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.NoWrap
        maximumLineCount: 1
      }
    }

    // Action buttons (overlay in top-right corner) - dynamically populated from provider
    Row {
      visible: gridEntryContainer.isSelected && gridItemActions.length > 0
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.marginXS
      z: 10
      spacing: Style.marginXXS

      property var gridItemActions: {
        if (!gridEntryContainer.isSelected)
          return [];
        var provider = row.provider || launcher.currentProvider;
        if (provider && provider.getItemActions) {
          return provider.getItemActions(row);
        }
        return [];
      }

      Repeater {
        model: parent.gridItemActions
        AtmoIconButton {
          required property var modelData
          icon: modelData.icon
          baseSize: Style.baseWidgetSize * 0.75
          tooltipText: modelData.tooltip
          z: 11
          handleWheel: true
          onClicked: {
            if (modelData.action) {
              modelData.action();
            }
          }
        }
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    z: -1
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    enabled: !Settings.data.appLauncher.ignoreMouseInput

    onClicked: mouse => {
      if (mouse.button === Qt.LeftButton) {
        launcher.selectedIndex = gridEntryContainer.index;
        launcher.activate();
        mouse.accepted = true;
      }
    }
    acceptedButtons: Qt.LeftButton
  }
}
