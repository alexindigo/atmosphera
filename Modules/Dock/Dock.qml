import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Widgets

Variants {
  model: Quickshell.screens

  delegate: Item {
    id: root

    required property ShellScreen modelData
    property real scaling: ScalingService.getScreenScale(modelData)
    property bool barIsReady: modelData ? BarService.isBarReady(modelData.name) : false

    Connections {
      target: BarService
      function onBarReadyChanged(screenName) {
        if (screenName === modelData.name) {
          barIsReady = true
        }
      }
    }

    Connections {
      target: ScalingService
      function onScaleChanged(screenName, scale) {
        if (screenName === modelData.name) {
          scaling = scale
        }
      }
    }

    // Update dock apps when toplevels change
    Connections {
      target: ToplevelManager ? ToplevelManager.toplevels : null
      function onValuesChanged() {
        updateDockApps()
      }
    }

    // Update dock apps when pinned apps change
    Connections {
      target: Settings.data.dock
      function onPinnedAppsChanged() {
        updateDockApps()
      }
      function onOnlySameOutputChanged() {
        updateDockApps()
      }
    }

    // Initial update when component is ready
    Component.onCompleted: {
      if (ToplevelManager) {
        updateDockApps()
      }
    }

    // Shared properties between peek and dock windows
    readonly property bool autoHide: Settings.data.dock.autoHide
    readonly property int hideDelay: 500
    readonly property int showDelay: 100
    readonly property int hideAnimationDuration: Style.animationFast
    readonly property int showAnimationDuration: Style.animationFast
    readonly property int peekHeight: 1 // no scaling for peek
    readonly property int iconSize: 36 * scaling
    readonly property int floatingMargin: Settings.data.dock.floatingRatio * Style.marginL * scaling

    // Bar detection and positioning properties
    readonly property bool hasBar: modelData && modelData.name ? (Settings.data.bar.monitors.includes(modelData.name) || (Settings.data.bar.monitors.length === 0)) : false
    readonly property bool barAtBottom: hasBar && Settings.data.bar.position === "bottom"
    readonly property bool barAtTop: hasBar && Settings.data.bar.position === "top"
    readonly property bool barAtLeft: hasBar && Settings.data.bar.position === "left"
    readonly property bool barAtRight: hasBar && Settings.data.bar.position === "right"
    readonly property int barHeight: Style.barHeight * scaling

    // Dock positioning properties
    readonly property string dockPosition: Settings.data.dock.position || "bottom"
    readonly property bool dockAtBottom: dockPosition === "bottom"
    readonly property bool dockAtTop: dockPosition === "top"
    readonly property bool dockAtLeft: dockPosition === "left"
    readonly property bool dockAtRight: dockPosition === "right"
    readonly property bool dockHorizontal: dockAtLeft || dockAtRight
    readonly property bool dockVertical: dockAtTop || dockAtBottom

    // Shared state between windows
    property bool dockHovered: false
    property bool anyAppHovered: false
    property bool menuHovered: false
    property bool hidden: autoHide
    property bool peekHovered: false

    // Separate property to control Loader - stays true during animations
    property bool dockLoaded: !autoHide // Start loaded if autoHide is off

    // Track the currently open context menu
    property var currentContextMenu: null

    // Combined model of running apps and pinned apps
    property var dockApps: []

    // Function to close any open context menu
    function closeAllContextMenus() {
      if (currentContextMenu && currentContextMenu.visible) {
        currentContextMenu.hide()
      }
    }

    // Helper functions for margin calculations
    function getBottomMargin() {
      switch (Settings.data.bar.position) {
      case "bottom":
        return (Style.barHeight + Style.marginM) * scaling + (Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL * scaling + floatingMargin : floatingMargin)
      default:
        return floatingMargin
      }
    }

    function getTopMargin() {
      switch (Settings.data.bar.position) {
      case "top":
        return (Style.barHeight + Style.marginM) * scaling + (Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL * scaling + floatingMargin : floatingMargin)
      default:
        return floatingMargin
      }
    }

    function getLeftMargin() {
      switch (Settings.data.bar.position) {
      case "left":
        return (Style.barHeight + Style.marginM) * scaling + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * Style.marginXL * scaling + floatingMargin : floatingMargin)
      default:
        return floatingMargin
      }
    }

    function getRightMargin() {
      switch (Settings.data.bar.position) {
      case "right":
        return (Style.barHeight + Style.marginM) * scaling + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * Style.marginXL * scaling + floatingMargin : floatingMargin)
      default:
        return floatingMargin
      }
    }

    // Function to update the combined dock apps model
    function updateDockApps() {
      const runningApps = ToplevelManager ? (ToplevelManager.toplevels.values || []) : []
      const pinnedApps = Settings.data.dock.pinnedApps || []
      const combined = []
      const processedAppIds = new Set()

      // Strategy: Maintain app positions as much as possible
      // 1. First pass: Add all running apps (both pinned and non-pinned) in their current order
      runningApps.forEach(toplevel => {
                            if (toplevel && toplevel.appId && !(Settings.data.dock.onlySameOutput && toplevel.screens && !toplevel.screens.includes(modelData))) {
                              const isPinned = pinnedApps.includes(toplevel.appId)
                              const appType = isPinned ? "pinned-running" : "running"

                              combined.push({
                                              "type": appType,
                                              "toplevel": toplevel,
                                              "appId": toplevel.appId,
                                              "title": toplevel.title
                                            })
                              processedAppIds.add(toplevel.appId)
                            }
                          })

      // 2. Second pass: Add non-running pinned apps at the end
      pinnedApps.forEach(pinnedAppId => {
                           if (!processedAppIds.has(pinnedAppId)) {
                             // Pinned app that is not running
                             combined.push({
                                             "type": "pinned",
                                             "toplevel": null,
                                             "appId": pinnedAppId,
                                             "title": pinnedAppId
                                           })
                           }
                         })

      dockApps = combined
    }

    // Timer to unload dock after hide animation completes
    Timer {
      id: unloadTimer
      interval: hideAnimationDuration + 50 // Add small buffer
      onTriggered: {
        if (hidden && autoHide) {
          dockLoaded = false
        }
      }
    }

    // Timer for auto-hide delay
    Timer {
      id: hideTimer
      interval: hideDelay
      onTriggered: {
        if (autoHide && !dockHovered && !anyAppHovered && !peekHovered && !menuHovered) {
          hidden = true
          unloadTimer.restart() // Start unload timer when hiding
        }
      }
    }

    // Timer for show delay
    Timer {
      id: showTimer
      interval: showDelay
      onTriggered: {
        if (autoHide) {
          dockLoaded = true // Load dock immediately
          hidden = false // Then trigger show animation
          unloadTimer.stop() // Cancel any pending unload
        }
      }
    }

    // Watch for autoHide setting changes
    onAutoHideChanged: {
      if (!autoHide) {
        hidden = false
        dockLoaded = true
        hideTimer.stop()
        showTimer.stop()
        unloadTimer.stop()
      } else {
        hidden = true
        unloadTimer.restart() // Schedule unload after animation
      }
    }

    // PEEK WINDOW - Always visible when auto-hide is enabled
    Loader {
      active: (barIsReady || !hasBar) && modelData && Settings.data.dock.monitors.includes(modelData.name) && autoHide

      sourceComponent: PanelWindow {
        id: peekWindow

        screen: modelData
        anchors.bottom: dockAtBottom
        anchors.top: dockAtTop
        anchors.left: dockAtLeft
        anchors.right: dockAtRight
        focusable: false
        color: Color.transparent

        WlrLayershell.namespace: "noctalia-dock-peek"
        WlrLayershell.exclusionMode: ExclusionMode.Auto // Always exclusive

        implicitHeight: dockVertical ? peekHeight : undefined
        implicitWidth: dockHorizontal ? peekHeight : undefined

        Rectangle {
          anchors.fill: parent
          color: (barAtBottom && dockAtBottom) || (barAtTop && dockAtTop) || (barAtLeft && dockAtLeft) || (barAtRight && dockAtRight) ? Qt.alpha(Color.mSurface, Settings.data.bar.backgroundOpacity) : Color.transparent
        }

        MouseArea {
          id: peekArea
          anchors.fill: parent
          hoverEnabled: true

          onEntered: {
            peekHovered = true
            if (hidden) {
              showTimer.start()
            }
          }

          onExited: {
            peekHovered = false
            if (!hidden && !dockHovered && !anyAppHovered && !menuHovered) {
              hideTimer.restart()
            }
          }
        }
      }
    }

    // DOCK WINDOW
    Loader {
      active: (barIsReady || !hasBar) && modelData && Settings.data.dock.monitors.includes(modelData.name) && dockLoaded && ToplevelManager && (dockApps.length > 0)

      sourceComponent: PanelWindow {
        id: dockWindow

        screen: modelData

        focusable: false
        color: Color.transparent

        WlrLayershell.namespace: "noctalia-dock-main"
        WlrLayershell.exclusionMode: Settings.data.dock.exclusive ? ExclusionMode.Auto : ExclusionMode.Ignore

        // Size to fit the dock container exactly
        implicitWidth: dockContainerWrapper.width
        implicitHeight: dockContainerWrapper.height

        // Position dock based on settings
        anchors.bottom: dockAtBottom
        anchors.top: dockAtTop
        anchors.left: dockAtLeft
        anchors.right: dockAtRight

        margins.bottom: dockAtBottom ? getBottomMargin() : 0
        margins.top: dockAtTop ? getTopMargin() : 0
        margins.left: dockAtLeft ? getLeftMargin() : 0
        margins.right: dockAtRight ? getRightMargin() : 0

        // Rectangle {
        //   anchors.fill: parent
        //   color: "#000FF0"
        //   z: -1
        // }

        // Wrapper item for scale/opacity animations
        Item {
          id: dockContainerWrapper
          width: dockContainer.width
          height: dockContainer.height
          anchors.horizontalCenter: dockVertical ? parent.horizontalCenter : undefined
          anchors.verticalCenter: dockHorizontal ? parent.verticalCenter : undefined
          anchors.bottom: dockAtBottom ? parent.bottom : undefined
          anchors.top: dockAtTop ? parent.top : undefined
          anchors.left: dockAtLeft ? parent.left : undefined
          anchors.right: dockAtRight ? parent.right : undefined

          // Apply animations to this wrapper
          opacity: hidden ? 0 : 1
          scale: hidden ? 0.85 : 1

          Behavior on opacity {
            NumberAnimation {
              duration: hidden ? hideAnimationDuration : showAnimationDuration
              easing.type: Easing.InOutQuad
            }
          }

          Behavior on scale {
            NumberAnimation {
              duration: hidden ? hideAnimationDuration : showAnimationDuration
              easing.type: hidden ? Easing.InQuad : Easing.OutBack
              easing.overshoot: hidden ? 0 : 1.05
            }
          }

          Rectangle {
            id: dockContainer
            width: dockVertical ? dockLayout.implicitWidth + Style.marginM * scaling * 2 : dockLayoutHorizontal.implicitWidth + Style.marginM * scaling * 2
            height: dockVertical ? dockLayout.implicitHeight + Style.marginM * scaling * 2 : dockLayoutHorizontal.implicitHeight + Style.marginM * scaling * 2
            color: Qt.alpha(Color.mSurface, Settings.data.dock.backgroundOpacity)
            anchors.centerIn: parent
            radius: Style.radiusL * scaling
            border.width: Math.max(1, Style.borderS * scaling)
            border.color: Qt.alpha(Color.mOutline, Settings.data.dock.backgroundOpacity)

            MouseArea {
              id: dockMouseArea
              anchors.fill: parent
              hoverEnabled: true

              onEntered: {
                dockHovered = true
                if (autoHide) {
                  showTimer.stop()
                  hideTimer.stop()
                  unloadTimer.stop() // Cancel unload if hovering
                }
              }

              onExited: {
                dockHovered = false
                if (autoHide && !anyAppHovered && !peekHovered && !menuHovered) {
                  hideTimer.restart()
                }
              }

              onClicked: {
                // Close any open context menu when clicking on the dock background
                closeAllContextMenus()
              }
            }

            Item {
              id: dock
              width: dockVertical ? dockLayout.implicitWidth : dockLayoutHorizontal.implicitWidth
              height: dockVertical ? dockLayout.implicitHeight : dockLayoutHorizontal.implicitHeight
              anchors.centerIn: parent

              function getAppIcon(appData): string {
                if (!appData || !appData.appId)
                  return ""
                return ThemeIcons.iconForAppId(appData.appId?.toLowerCase())
              }

              RowLayout {
                id: dockLayout
                spacing: Style.marginM * scaling
                anchors.centerIn: parent
                visible: dockVertical
                Layout.fillHeight: false
                Layout.fillWidth: false

                Repeater {
                  model: dockApps

                  delegate: Item {
                    id: appButton
                    Layout.preferredWidth: iconSize
                    Layout.preferredHeight: iconSize
                    Layout.alignment: Qt.AlignCenter

                    property bool isActive: modelData.toplevel && ToplevelManager.activeToplevel && ToplevelManager.activeToplevel === modelData.toplevel
                    property bool hovered: appMouseArea.containsMouse
                    property string appId: modelData ? modelData.appId : ""
                    property string appTitle: modelData ? (modelData.title || modelData.appId) : ""
                    property bool isRunning: modelData && (modelData.type === "running" || modelData.type === "pinned-running")

                    // Listen for the toplevel being closed
                    Connections {
                      target: modelData?.toplevel
                      function onClosed() {
                        Qt.callLater(root.updateDockApps)
                      }
                    }

                    Image {
                      id: appIcon
                      width: iconSize
                      height: iconSize
                      anchors.centerIn: parent
                      source: dock.getAppIcon(modelData)
                      visible: source.toString() !== ""
                      sourceSize.width: iconSize * 2
                      sourceSize.height: iconSize * 2
                      smooth: true
                      mipmap: true
                      antialiasing: true
                      fillMode: Image.PreserveAspectFit
                      cache: true

                      // Dim pinned apps that aren't running
                      opacity: appButton.isRunning ? 1.0 : 0.6

                      scale: appButton.hovered ? 1.15 : 1.0

                      Behavior on scale {
                        NumberAnimation {
                          duration: Style.animationNormal
                          easing.type: Easing.OutBack
                          easing.overshoot: 1.2
                        }
                      }

                      Behavior on opacity {
                        NumberAnimation {
                          duration: Style.animationFast
                          easing.type: Easing.OutQuad
                        }
                      }
                    }

                    // Fall back if no icon
                    NIcon {
                      anchors.centerIn: parent
                      visible: !appIcon.visible
                      icon: "question-mark"
                      pointSize: iconSize * 0.7
                      color: appButton.isActive ? Color.mPrimary : Color.mOnSurfaceVariant
                      opacity: appButton.isRunning ? 1.0 : 0.6
                      scale: appButton.hovered ? 1.15 : 1.0

                      Behavior on scale {
                        NumberAnimation {
                          duration: Style.animationFast
                          easing.type: Easing.OutBack
                          easing.overshoot: 1.2
                        }
                      }

                      Behavior on opacity {
                        NumberAnimation {
                          duration: Style.animationFast
                          easing.type: Easing.OutQuad
                        }
                      }
                    }

                    // Context menu popup
                    DockMenu {
                      id: contextMenu
                      scaling: root.scaling
                      dockPosition: root.dockPosition
                      onHoveredChanged: menuHovered = hovered
                      onRequestClose: {
                        contextMenu.hide()
                        // Restart hide timer after menu action if auto-hide is enabled
                        if (autoHide && !dockHovered && !anyAppHovered && !peekHovered) {
                          hideTimer.restart()
                        }
                      }
                      onAppClosed: root.updateDockApps // Force immediate dock update when app is closed
                      onVisibleChanged: {
                        if (visible) {
                          root.currentContextMenu = contextMenu
                        } else if (root.currentContextMenu === contextMenu) {
                          root.currentContextMenu = null
                          // Reset menu hover state when menu becomes invisible
                          menuHovered = false
                          // Restart hide timer if conditions are met
                          if (autoHide && !dockHovered && !anyAppHovered && !peekHovered) {
                            hideTimer.restart()
                          }
                        }
                      }
                    }

                    MouseArea {
                      id: appMouseArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                      onEntered: {
                        anyAppHovered = true
                        const appName = appButton.appTitle || appButton.appId || "Unknown"
                        const tooltipText = appName.length > 40 ? appName.substring(0, 37) + "..." : appName
                        TooltipService.show(Screen, appButton, tooltipText, "top")
                        if (autoHide) {
                          showTimer.stop()
                          hideTimer.stop()
                          unloadTimer.stop() // Cancel unload if hovering app
                        }
                      }

                      onExited: {
                        anyAppHovered = false
                        TooltipService.hide()
                        if (autoHide && !dockHovered && !peekHovered && !menuHovered) {
                          hideTimer.restart()
                        }
                      }

                      onClicked: function (mouse) {
                        if (mouse.button === Qt.RightButton) {
                          // If right-clicking on the same app with an open context menu, close it
                          if (root.currentContextMenu === contextMenu && contextMenu.visible) {
                            root.closeAllContextMenus()
                            return
                          }
                          // Close any other existing context menu first
                          root.closeAllContextMenus()
                          // Hide tooltip when showing context menu
                          TooltipService.hide()
                          contextMenu.show(appButton, modelData.toplevel || modelData)
                          return
                        }

                        // Close any existing context menu for non-right-click actions
                        root.closeAllContextMenus()

                        // Check if toplevel is still valid (not a stale reference)
                        const isValidToplevel = modelData?.toplevel && ToplevelManager && ToplevelManager.toplevels.values.includes(modelData.toplevel)

                        if (mouse.button === Qt.MiddleButton && isValidToplevel && modelData.toplevel.close) {
                          modelData.toplevel.close()
                          Qt.callLater(root.updateDockApps) // Force immediate dock update
                        } else if (mouse.button === Qt.LeftButton) {
                          if (isValidToplevel && modelData.toplevel.activate) {
                            // Running app - activate it
                            modelData.toplevel.activate()
                          } else if (modelData?.appId) {
                            // Pinned app not running - launch it
                            Quickshell.execDetached(["gtk-launch", modelData.appId])
                          }
                        }
                      }
                    }

                    // Active indicator
                    Rectangle {
                      visible: isActive
                      width: iconSize * 0.2
                      height: iconSize * 0.1
                      color: Color.mPrimary
                      radius: Style.radiusXS * scaling
                      anchors.top: parent.bottom
                      anchors.horizontalCenter: parent.horizontalCenter

                      // Pulse animation for active indicator
                      SequentialAnimation on opacity {
                        running: isActive
                        loops: Animation.Infinite
                        NumberAnimation {
                          to: 0.6
                          duration: Style.animationSlowest
                          easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                          to: 1.0
                          duration: Style.animationSlowest
                          easing.type: Easing.InOutQuad
                        }
                      }
                    }
                  }
                }
              }

              ColumnLayout {
                id: dockLayoutHorizontal
                spacing: Style.marginM * scaling
                anchors.centerIn: parent
                visible: dockHorizontal
                Layout.fillHeight: false
                Layout.fillWidth: false

                Repeater {
                  model: dockApps

                  delegate: Item {
                    id: appButtonHorizontal
                    Layout.preferredWidth: iconSize
                    Layout.preferredHeight: iconSize
                    Layout.alignment: Qt.AlignCenter

                    property bool isActive: modelData.toplevel && ToplevelManager.activeToplevel && ToplevelManager.activeToplevel === modelData.toplevel
                    property bool hovered: appMouseAreaHorizontal.containsMouse
                    property string appId: modelData ? modelData.appId : ""
                    property string appTitle: modelData ? (modelData.title || modelData.appId) : ""
                    property bool isRunning: modelData && (modelData.type === "running" || modelData.type === "pinned-running")

                    // Listen for the toplevel being closed
                    Connections {
                      target: modelData?.toplevel
                      function onClosed() {
                        Qt.callLater(root.updateDockApps)
                      }
                    }

                    Image {
                      id: appIconHorizontal
                      width: iconSize
                      height: iconSize
                      anchors.centerIn: parent
                      source: dock.getAppIcon(modelData)
                      visible: source.toString() !== ""
                      sourceSize.width: iconSize * 2
                      sourceSize.height: iconSize * 2
                      smooth: true
                      mipmap: true
                      antialiasing: true
                      fillMode: Image.PreserveAspectFit
                      cache: true

                      // Dim pinned apps that aren't running
                      opacity: appButtonHorizontal.isRunning ? 1.0 : 0.6

                      scale: appButtonHorizontal.hovered ? 1.15 : 1.0

                      Behavior on scale {
                        NumberAnimation {
                          duration: Style.animationNormal
                          easing.type: Easing.OutBack
                          easing.overshoot: 1.2
                        }
                      }

                      Behavior on opacity {
                        NumberAnimation {
                          duration: Style.animationFast
                          easing.type: Easing.OutQuad
                        }
                      }
                    }

                    // Fall back if no icon
                    NIcon {
                      anchors.centerIn: parent
                      visible: !appIconHorizontal.visible
                      icon: "question-mark"
                      pointSize: iconSize * 0.7
                      color: appButtonHorizontal.isActive ? Color.mPrimary : Color.mOnSurfaceVariant
                      opacity: appButtonHorizontal.isRunning ? 1.0 : 0.6
                      scale: appButtonHorizontal.hovered ? 1.15 : 1.0

                      Behavior on scale {
                        NumberAnimation {
                          duration: Style.animationFast
                          easing.type: Easing.OutBack
                          easing.overshoot: 1.2
                        }
                      }

                      Behavior on opacity {
                        NumberAnimation {
                          duration: Style.animationFast
                          easing.type: Easing.OutQuad
                        }
                      }
                    }

                    // Context menu popup
                    DockMenu {
                      id: contextMenuHorizontal
                      scaling: root.scaling
                      dockPosition: root.dockPosition
                      onHoveredChanged: menuHovered = hovered
                      onRequestClose: {
                        contextMenuHorizontal.hide()
                        // Restart hide timer after menu action if auto-hide is enabled
                        if (autoHide && !dockHovered && !anyAppHovered && !peekHovered) {
                          hideTimer.restart()
                        }
                      }
                      onAppClosed: root.updateDockApps // Force immediate dock update when app is closed
                      onVisibleChanged: {
                        if (visible) {
                          root.currentContextMenu = contextMenuHorizontal
                        } else if (root.currentContextMenu === contextMenuHorizontal) {
                          root.currentContextMenu = null
                          // Reset menu hover state when menu becomes invisible
                          menuHovered = false
                          // Restart hide timer if conditions are met
                          if (autoHide && !dockHovered && !anyAppHovered && !peekHovered) {
                            hideTimer.restart()
                          }
                        }
                      }
                    }

                    MouseArea {
                      id: appMouseAreaHorizontal
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                      onEntered: {
                        anyAppHovered = true
                        const appName = appButtonHorizontal.appTitle || appButtonHorizontal.appId || "Unknown"
                        const tooltipText = appName.length > 40 ? appName.substring(0, 37) + "..." : appName
                        TooltipService.show(Screen, appButtonHorizontal, tooltipText, "top")
                        if (autoHide) {
                          showTimer.stop()
                          hideTimer.stop()
                          unloadTimer.stop() // Cancel unload if hovering app
                        }
                      }

                      onExited: {
                        anyAppHovered = false
                        TooltipService.hide()
                        if (autoHide && !dockHovered && !peekHovered && !menuHovered) {
                          hideTimer.restart()
                        }
                      }

                      onClicked: function (mouse) {
                        if (mouse.button === Qt.RightButton) {
                          // If right-clicking on the same app with an open context menu, close it
                          if (root.currentContextMenu === contextMenuHorizontal && contextMenuHorizontal.visible) {
                            root.closeAllContextMenus()
                            return
                          }
                          // Close any other existing context menu first
                          root.closeAllContextMenus()
                          // Hide tooltip when showing context menu
                          TooltipService.hide()
                          contextMenuHorizontal.show(appButtonHorizontal, modelData.toplevel || modelData)
                          return
                        }

                        // Close any existing context menu for non-right-click actions
                        root.closeAllContextMenus()

                        // Check if toplevel is still valid (not a stale reference)
                        const isValidToplevel = modelData?.toplevel && ToplevelManager && ToplevelManager.toplevels.values.includes(modelData.toplevel)

                        if (mouse.button === Qt.MiddleButton && isValidToplevel && modelData.toplevel.close) {
                          modelData.toplevel.close()
                          Qt.callLater(root.updateDockApps) // Force immediate dock update
                        } else if (mouse.button === Qt.LeftButton) {
                          if (isValidToplevel && modelData.toplevel.activate) {
                            // Running app - activate it
                            modelData.toplevel.activate()
                          } else if (modelData?.appId) {
                            // Pinned app not running - launch it
                            Quickshell.execDetached(["gtk-launch", modelData.appId])
                          }
                        }
                      }
                    }

                    // Active indicator
                    Rectangle {
                      visible: isActive
                      width: iconSize * 0.1
                      height: iconSize * 0.2
                      color: Color.mPrimary
                      radius: Style.radiusXS * scaling
                      anchors.left: parent.right
                      anchors.verticalCenter: parent.verticalCenter

                      // Pulse animation for active indicator
                      SequentialAnimation on opacity {
                        running: isActive
                        loops: Animation.Infinite
                        NumberAnimation {
                          to: 0.6
                          duration: Style.animationSlowest
                          easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                          to: 1.0
                          duration: Style.animationSlowest
                          easing.type: Easing.InOutQuad
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
