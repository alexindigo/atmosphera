import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

import "Helpers/LauncherSelection.js" as LauncherSelection
import qs.Commons
import qs.Widgets

NBox {
  id: entry

  // Keyed view row {key, row}; the delegate lives as long as its key does.
  required property var modelData
  required property int index
  required property var launcher
  // The launcher's result object for this row (refreshed in place by a keyed update).
  readonly property var row: modelData && modelData.row ? modelData.row : ({})

  readonly property bool isSelected: index === launcher.selectedIndex

  width: ListView.view.width
  implicitHeight: launcher.entryHeight
  clip: true
  color: entry.isSelected ? AtmoColor.mHover : AtmoColor.mSurfaceVariant
  forceOpaque: entry.isSelected

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

  Behavior on color {
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCirc
    }
  }

  ColumnLayout {
    id: contentLayout
    anchors.fill: parent
    anchors.margins: launcher.isCompactDensity ? Style.marginXS : Style.marginM
    spacing: launcher.isCompactDensity ? Style.marginXS : Style.marginM

    // Top row - Main entry content with action buttons
    RowLayout {
      Layout.fillWidth: true
      spacing: launcher.isCompactDensity ? Style.marginS : Style.marginM

      // Icon badge or Image preview or Emoji
      Item {
        id: badge
        visible: !row.hideIcon
        // Image parts exist only for image rows; their state is read from here.
        readonly property int imageStatus: imageLoader.item ? imageLoader.item.status : Image.Null
        readonly property bool imageShown: imageLoader.item ? imageLoader.item.visible : false
        Layout.preferredWidth: row.hideIcon ? 0 : launcher.badgeSize
        Layout.preferredHeight: row.hideIcon ? 0 : launcher.badgeSize

        // Icon background
        Rectangle {
          anchors.fill: parent
          radius: Style.radiusXS
          color: AtmoColor.mSurface
          visible: Settings.data.appLauncher.showIconBackground && !row.isImage
        }

        // Image preview - uses provider's getImageUrl if available
        Loader {
          id: imageLoader
          anchors.fill: parent
          active: !!row.isImage
          sourceComponent: NImageRounded {
          // A failed image falls back to the icon, declaratively: a kept delegate
          // follows its row instead of a state written once at creation.
          visible: !row.displayString && status !== Image.Error
          radius: Style.radiusXS
          borderColor: AtmoColor.mOnSurface
          borderWidth: Style.borderM
          imageFillMode: Image.PreserveAspectCrop

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

        // Color swatch - shown for clipboard color entries
        Rectangle {
          anchors.fill: parent
          radius: Style.radiusXS
          color: row.colorHex || "transparent"
          visible: !!row.colorHex
          border.color: AtmoColor.mOnSurface
          border.width: Style.borderM
        }

        Loader {
          id: iconLoader
          anchors.fill: parent
          anchors.margins: Style.marginXS

          visible: (!row.isImage && !row.displayString && !row.colorHex) || (!!row.isImage && badge.imageStatus === Image.Error)
          active: visible

          sourceComponent: Component {
            Loader {
              anchors.fill: parent
              sourceComponent: Settings.data.appLauncher.iconMode === "tabler" && row.isTablerIcon ? tablerIconComponent : systemIconComponent
            }
          }

          Component {
            id: tablerIconComponent
            AtmoIcon {
              icon: row.icon
              pointSize: Style.fontSizeXXXL
              visible: row.icon && !row.displayString
              color: (entry.isSelected && !Settings.data.appLauncher.showIconBackground) ? AtmoColor.mOnHover : AtmoColor.mOnSurface
            }
          }

          Component {
            id: systemIconComponent
            AtmoAppIcon {
              anchors.fill: parent
              name: row.icon || ""
              visible: row.icon && !row.displayString
            }
          }
        }

        // String display - takes precedence when displayString is present
        NText {
          id: stringDisplay
          anchors.centerIn: parent
          visible: !!row.displayString || (!badge.imageShown && !iconLoader.visible)
          text: row.displayString ? row.displayString : (row.name ? row.name.charAt(0).toUpperCase() : "?")
          pointSize: row.displayString ? (row.displayStringSize || Style.fontSizeXXXL) : Style.fontSizeXXL
          font.weight: Style.fontWeightBold
          color: row.displayString ? AtmoColor.mOnSurface : AtmoColor.mOnPrimary
        }

        // Image type indicator overlay
        Loader {
          active: !!row.isImage && badge.imageShown
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          anchors.margins: 2
          sourceComponent: Rectangle {
          width: formatLabel.width + Style.marginXS
          height: formatLabel.height + Style.marginXXS
          color: AtmoColor.mSurfaceVariant
          radius: Style.radiusXXS
          NText {
            id: formatLabel
            anchors.centerIn: parent
            text: {
              if (!row.isImage)
                return "";
              const desc = row.description || "";
              const parts = desc.split(" \u2022 ");
              return parts[0] || "IMG";
            }
            pointSize: Style.fontSizeXXS
            color: AtmoColor.mOnSurfaceVariant
          }
          }
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

      // Text content
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        NText {
          text: row.name || "Unknown"
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: entry.isSelected ? AtmoColor.mOnHover : AtmoColor.mOnSurface
          elide: Text.ElideRight
          maximumLineCount: 1
          wrapMode: Text.Wrap
          clip: true
          Layout.fillWidth: true
        }

        NText {
          text: row.description || ""
          pointSize: Style.fontSizeS
          color: entry.isSelected ? AtmoColor.mOnHover : AtmoColor.mOnSurfaceVariant
          elide: Text.ElideRight
          maximumLineCount: 1
          Layout.fillWidth: true
          visible: text !== "" && !launcher.isCompactDensity
        }
      }

      // Action buttons row - dynamically populated from provider
      RowLayout {
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        spacing: Style.marginXS
        visible: entry.isSelected && itemActions.length > 0

        property var itemActions: {
          if (!entry.isSelected)
            return [];
          var provider = row.provider || launcher.currentProvider;
          if (provider && provider.getItemActions) {
            return provider.getItemActions(row);
          }
          return [];
        }

        Repeater {
          model: parent.itemActions
          AtmoIconButton {
            required property var modelData
            icon: modelData.icon
            baseSize: Style.baseWidgetSize * 0.75
            tooltipText: modelData.tooltip
            z: 1
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
        launcher.selectedIndex = entry.index;
        launcher.activate();
        mouse.accepted = true;
      }
    }
    acceptedButtons: Qt.LeftButton
  }
}
