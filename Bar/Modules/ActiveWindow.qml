import QtQuick
import Quickshell
import qs.Components
import qs.Settings
import Quickshell.Wayland
import Quickshell.Widgets

Item {
    id: activeWindowWrapper
    width: parent.width
    property int fullHeight: activeWindowTitleContainer.height
    property bool shouldShow: false
    
    Timer {
        id: visibilityTimer
        interval: 4000
        running: false
        onTriggered: {
            activeWindowWrapper.shouldShow = false
        }
    }
    
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            if (ToplevelManager.activeToplevel?.appId) {
                activeWindowWrapper.shouldShow = true
                visibilityTimer.restart()
            } else {
                activeWindowWrapper.shouldShow = false
                visibilityTimer.stop()
            }
        }
    }

    y: shouldShow ? barBackground.height : barBackground.height - fullHeight
    height: shouldShow ? fullHeight : 1
    opacity: shouldShow ? 1 : 0
    clip: true

    function getIcon() {
        var icon = Quickshell.iconPath(ToplevelManager.activeToplevel.appId.toLowerCase(), true);
        if (!icon) {
            icon = Quickshell.iconPath(ToplevelManager.activeToplevel.appId, true);
        }
        if (!icon) {
            icon = Quickshell.iconPath(ToplevelManager.activeToplevel.title, true);
        }
        if (!icon) {
            icon = Quickshell.iconPath(ToplevelManager.activeToplevel.title.toLowerCase(), "application-x-executable");
        }

        return icon;
    }

    Behavior on height {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutQuad
        }
    }
    Behavior on y {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutQuad
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 250
        }
    }

    Rectangle {
        id: activeWindowTitleContainer
        color: Theme.backgroundPrimary
        bottomLeftRadius: Math.max(0, width / 2)
        bottomRightRadius: Math.max(0, width / 2)

        width: Math.min(barBackground.width - 200, activeWindowTitle.implicitWidth + (Settings.showActiveWindowIcon ? 28 : 22))
        height: activeWindowTitle.implicitHeight + 12

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        IconImage {
            id: icon
            width: 12
            height: 12
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            source: ToplevelManager?.activeToplevel ? getIcon() : ""
            visible: Settings.showActiveWindowIcon
            anchors.verticalCenterOffset: -3
        }

        Text {
            id: activeWindowTitle
            text: ToplevelManager?.activeToplevel?.title && ToplevelManager?.activeToplevel?.title.length > 60 ? ToplevelManager?.activeToplevel?.title.substring(0, 60) + "..." : ToplevelManager?.activeToplevel?.title || ""
            font.pixelSize: 12
            color: Theme.textSecondary
            elide: Text.ElideRight
            anchors.left: icon.right
            anchors.leftMargin: Settings.showActiveWindowIcon ? 4 : 6
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -3
            horizontalAlignment: Settings.showActiveWindowIcon ? Text.AlignRight : Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            maximumLineCount: 1
        }
    }

    Corners {
        id: activeCornerRight
        position: "bottomleft"
        size: 1.1
        fillColor: Theme.backgroundPrimary
        offsetX: activeWindowTitleContainer.x + activeWindowTitleContainer.width - 34
        offsetY: -1
        anchors.top: activeWindowTitleContainer.top
    }

    Corners {
        id: activeCornerLeft
        position: "bottomright"
        size: 1.1
        fillColor: Theme.backgroundPrimary
        anchors.top: activeWindowTitleContainer.top
        x: activeWindowTitleContainer.x + 34 - width
        offsetY: -1
    }
}

