import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI


/**
 * SmartPanelWindow - Separate window for panel content
 *
 * This component runs in its own window, separate from MainScreen.
 * It follows the PanelPlaceholder for positioning and contains the actual panel content.
 */
PanelWindow {
  id: root

  // Required reference to placeholder
  required property PanelPlaceholder placeholder

  // Panel content component (set by SmartPanel wrapper)
  property Component panelContent: null

  // Reference to the SmartPanel wrapper (for keyboard handlers)
  property var panelWrapper: null

  // Keyboard focus
  property bool exclusiveKeyboard: true

  // Support close with escape
  property bool closeWithEscape: true

  // Track whether panel is open
  property bool isPanelOpen: false

  // Track actual visibility (delayed until content is loaded and sized)
  property bool isPanelVisible: false

  // Track size animation completion for sequential opacity animation
  property bool sizeAnimationComplete: false

  // Track close animation state
  property bool isClosing: false
  property bool opacityFadeComplete: false
  property bool closeFinalized: false

  // Safety: Watchdog timers
  property bool closeWatchdogActive: false
  property bool openWatchdogActive: false

  // Cached window size (only update when content size changes, not during animation)
  property real cachedWindowWidth: 0
  property real cachedWindowHeight: 0

  // Signals
  signal panelOpened
  signal panelClosed

  // Window configuration
  color: Color.transparent
  mask: null // No mask - content window is rectangular
  visible: isPanelOpen

  // Wayland layer shell configuration - content-sized window
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "noctalia-panel-content-" + placeholder.panelName + "-" + (placeholder.screen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore
  WlrLayershell.keyboardFocus: !root.isPanelOpen ? WlrKeyboardFocus.None : (exclusiveKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)

  // Dynamic anchoring based on panel position
  // For correct positioning with Wayland layer shell:
  // - Anchor the primary edge (top/bottom/left/right)
  // - Also anchor the opposite edge of the OTHER axis (both horizontal edges if panel is vertical, both vertical edges if panel is horizontal)
  // This prevents unwanted centering and allows margins to position the panel correctly
  readonly property bool isPrimaryVertical: placeholder.primaryAnchorEdge === "top" || placeholder.primaryAnchorEdge === "bottom"
  readonly property bool isPrimaryHorizontal: placeholder.primaryAnchorEdge === "left" || placeholder.primaryAnchorEdge === "right"

  anchors.top: placeholder.effectivePanelAnchorTop || placeholder.primaryAnchorEdge === "top" || isPrimaryHorizontal
  anchors.bottom: placeholder.effectivePanelAnchorBottom || placeholder.primaryAnchorEdge === "bottom" || isPrimaryHorizontal
  anchors.left: placeholder.effectivePanelAnchorLeft || placeholder.primaryAnchorEdge === "left" || isPrimaryVertical
  anchors.right: placeholder.effectivePanelAnchorRight || placeholder.primaryAnchorEdge === "right" || isPrimaryVertical

  // Size to content (cached to avoid resizing during animations)
  implicitWidth: cachedWindowWidth
  implicitHeight: cachedWindowHeight

  // Position via margins (calculated from target position, not animated position)
  readonly property var windowMargins: placeholder.getWindowMargins()
  margins.top: windowMargins.top
  margins.bottom: windowMargins.bottom
  margins.left: windowMargins.left
  margins.right: windowMargins.right

  // Debug logging for positioning
  Component.onCompleted: {
    Logger.d("SmartPanelWindow", "Panel positioning:", placeholder.panelName)
    Logger.d("SmartPanelWindow", "  primaryAnchorEdge:", placeholder.primaryAnchorEdge)
    Logger.d("SmartPanelWindow", "  isPrimaryVertical:", isPrimaryVertical, "isPrimaryHorizontal:", isPrimaryHorizontal)
    Logger.d("SmartPanelWindow", "  anchors:", anchors.top, anchors.bottom, anchors.left, anchors.right)
    Logger.d("SmartPanelWindow", "  margins (TLBR):", windowMargins.top, windowMargins.left, windowMargins.bottom, windowMargins.right)
    Logger.d("SmartPanelWindow", "  size:", cachedWindowWidth, "x", cachedWindowHeight)
  }

  // Sync state to placeholder
  onIsPanelVisibleChanged: {
    placeholder.isPanelVisible = isPanelVisible
  }
  onIsClosingChanged: {
    placeholder.isClosing = isClosing
  }
  onOpacityFadeCompleteChanged: {
    placeholder.opacityFadeComplete = opacityFadeComplete
  }

  // Update cached window size (only when target size changes)
  function updateWindowSize() {
    var targetWidth = placeholder.panelItem.targetWidth
    var targetHeight = placeholder.panelItem.targetHeight

    // Only update if size actually changed
    if (cachedWindowWidth !== targetWidth || cachedWindowHeight !== targetHeight) {
      cachedWindowWidth = targetWidth
      cachedWindowHeight = targetHeight
      Logger.d("SmartPanelWindow", "Window size updated:", targetWidth, "x", targetHeight, placeholder.panelName)
    }
  }

  // Panel control functions
  function toggle(buttonItem, buttonName) {
    if (!isPanelOpen) {
      open(buttonItem, buttonName)
    } else {
      close()
    }
  }

  function open(buttonItem, buttonName) {
    if (!buttonItem && buttonName) {
      buttonItem = BarService.lookupWidget(buttonName, placeholder.screen.name)
    }

    if (buttonItem) {
      placeholder.buttonItem = buttonItem
      // Map button position to screen coordinates
      var buttonPos = buttonItem.mapToItem(null, 0, 0)
      placeholder.buttonPosition = Qt.point(buttonPos.x, buttonPos.y)
      placeholder.buttonWidth = buttonItem.width
      placeholder.buttonHeight = buttonItem.height
      placeholder.useButtonPosition = true
    } else {
      // No button provided: reset button position mode
      placeholder.buttonItem = null
      placeholder.useButtonPosition = false
    }

    // Initialize cached window size
    updateWindowSize()

    // Set isPanelOpen to trigger content loading
    isPanelOpen = true

    // Notify PanelService
    PanelService.willOpenPanel(root)
  }

  function close() {
    // Start close sequence: fade opacity first
    isClosing = true
    sizeAnimationComplete = false
    closeFinalized = false

    // Stop the open animation timer if it's still running
    opacityTrigger.stop()
    openWatchdogActive = false
    openWatchdogTimer.stop()

    // Start close watchdog timer
    closeWatchdogActive = true
    closeWatchdogTimer.restart()

    // If opacity is already 0, skip directly to size animation
    if (contentWrapper.opacity === 0.0) {
      opacityFadeComplete = true
    } else {
      opacityFadeComplete = false
    }

    Logger.d("SmartPanelWindow", "Closing panel", placeholder.panelName)
  }

  function finalizeClose() {
    // Prevent double-finalization
    if (root.closeFinalized) {
      Logger.w("SmartPanelWindow", "finalizeClose called but already finalized - ignoring", placeholder.panelName)
      return
    }

    // Complete the close sequence after animations finish
    root.closeFinalized = true
    root.closeWatchdogActive = false
    closeWatchdogTimer.stop()

    root.isPanelVisible = false
    root.isPanelOpen = false
    root.isClosing = false
    root.opacityFadeComplete = false
    PanelService.closedPanel(root)
    panelClosed()

    Logger.d("SmartPanelWindow", "Panel close finalized", placeholder.panelName)
  }

  // Content wrapper with opacity animation (fills content-sized window)
  Item {
    id: contentWrapper
    anchors.fill: parent
    focus: true

    // Keyboard event handling
    Keys.onPressed: event => {
                      Logger.d("SmartPanelWindow", "Key pressed:", event.key, "for panel:", placeholder.panelName)
                      if (event.key === Qt.Key_Escape) {
                        panelWrapper.onEscapePressed()
                        if (closeWithEscape) {
                          root.close()
                          event.accepted = true
                        }
                      } else if (panelWrapper) {
                        if (event.key === Qt.Key_Up && panelWrapper.onUpPressed) {
                          panelWrapper.onUpPressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_Down && panelWrapper.onDownPressed) {
                          panelWrapper.onDownPressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_Left && panelWrapper.onLeftPressed) {
                          panelWrapper.onLeftPressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_Right && panelWrapper.onRightPressed) {
                          panelWrapper.onRightPressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_Tab && panelWrapper.onTabPressed) {
                          panelWrapper.onTabPressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_Backtab && panelWrapper.onBackTabPressed) {
                          panelWrapper.onBackTabPressed()
                          event.accepted = true
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && panelWrapper.onReturnPressed) {
                          panelWrapper.onReturnPressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_Home && panelWrapper.onHomePressed) {
                          panelWrapper.onHomePressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_End && panelWrapper.onEndPressed) {
                          panelWrapper.onEndPressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_PageUp && panelWrapper.onPageUpPressed) {
                          panelWrapper.onPageUpPressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_PageDown && panelWrapper.onPageDownPressed) {
                          panelWrapper.onPageDownPressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_J && (event.modifiers & Qt.ControlModifier) && panelWrapper.onCtrlJPressed) {
                          panelWrapper.onCtrlJPressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier) && panelWrapper.onCtrlKPressed) {
                          panelWrapper.onCtrlKPressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier) && panelWrapper.onCtrlNPressed) {
                          panelWrapper.onCtrlNPressed()
                          event.accepted = true
                        } else if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier) && panelWrapper.onCtrlPPressed) {
                          panelWrapper.onCtrlPPressed()
                          event.accepted = true
                        }
                      }
                    }

    // Opacity animation
    opacity: {
      if (isClosing)
        return 0.0
      if (isPanelVisible && sizeAnimationComplete)
        return 1.0
      return 0.0
    }

    Behavior on opacity {
      NumberAnimation {
        id: opacityAnimation
        duration: root.isClosing ? Style.animationFaster : Style.animationFast
        easing.type: Easing.OutQuad

        onRunningChanged: {
          // Safety: Zero-duration animation handling
          if (!running && duration === 0) {
            if (root.isClosing && contentWrapper.opacity === 0.0) {
              root.opacityFadeComplete = true
              var shouldFinalizeNow = placeholder.panelItem && !placeholder.panelItem.shouldAnimateWidth && !placeholder.panelItem.shouldAnimateHeight
              if (shouldFinalizeNow) {
                Logger.d("SmartPanelWindow", "Zero-duration opacity + no size animation - finalizing", placeholder.panelName)
                Qt.callLater(root.finalizeClose)
              }
            } else if (root.isPanelVisible && contentWrapper.opacity === 1.0) {
              root.openWatchdogActive = false
              openWatchdogTimer.stop()
            }
            return
          }

          // When opacity fade completes during close, trigger size animation
          if (!running && root.isClosing && contentWrapper.opacity === 0.0) {
            root.opacityFadeComplete = true
            var shouldFinalizeNow = placeholder.panelItem && !placeholder.panelItem.shouldAnimateWidth && !placeholder.panelItem.shouldAnimateHeight
            if (shouldFinalizeNow) {
              Logger.d("SmartPanelWindow", "No animation - finalizing immediately", placeholder.panelName)
              Qt.callLater(root.finalizeClose)
            } else {
              Logger.d("SmartPanelWindow", "Animation will run - waiting for size animation", placeholder.panelName)
            }
          } // When opacity fade completes during open, stop watchdog
          else if (!running && root.isPanelVisible && contentWrapper.opacity === 1.0) {
            root.openWatchdogActive = false
            openWatchdogTimer.stop()
          }
        }
      }
    }

    // Panel content loader
    Loader {
      id: contentLoader
      active: isPanelOpen
      anchors.fill: parent
      sourceComponent: root.panelContent

      // When content finishes loading, trigger positioning and visibility
      onLoaded: {
        // Capture initial content-driven size if available
        if (contentLoader.item) {
          var hasWidthProp = contentLoader.item.hasOwnProperty('contentPreferredWidth')
          var hasHeightProp = contentLoader.item.hasOwnProperty('contentPreferredHeight')

          if (hasWidthProp || hasHeightProp) {
            var initialWidth = hasWidthProp ? contentLoader.item.contentPreferredWidth : 0
            var initialHeight = hasHeightProp ? contentLoader.item.contentPreferredHeight : 0
            placeholder.updateContentSize(initialWidth, initialHeight)
            Logger.d("SmartPanelWindow", "Initial content size:", initialWidth, "x", initialHeight, placeholder.panelName)
          }
        }

        // Calculate position in placeholder
        placeholder.setPosition()

        // Make panel visible on the next frame
        Qt.callLater(function () {
          root.isPanelVisible = true
          opacityTrigger.start()

          // Start open watchdog timer
          root.openWatchdogActive = true
          openWatchdogTimer.start()

          panelOpened()
        })
      }
    }

    // MouseArea to prevent clicks on panel content from closing it
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: mouse => {
                   mouse.accepted = true // Eat the click to prevent propagation to background
                 }
      z: -1 // Behind content but above background click-to-close
    }

    // Watch for changes in content-driven sizes
    Connections {
      target: contentLoader.item
      ignoreUnknownSignals: true

      function onContentPreferredWidthChanged() {
        if (root.isPanelOpen && root.isPanelVisible && contentLoader.item) {
          placeholder.updateContentSize(contentLoader.item.contentPreferredWidth, placeholder.contentPreferredHeight)
        }
      }

      function onContentPreferredHeightChanged() {
        if (root.isPanelOpen && root.isPanelVisible && contentLoader.item) {
          placeholder.updateContentSize(placeholder.contentPreferredWidth, contentLoader.item.contentPreferredHeight)
        }
      }
    }
  }

  // Timer to trigger opacity fade at 50% of size animation
  Timer {
    id: opacityTrigger
    interval: Style.animationNormal * 0.5
    repeat: false
    onTriggered: {
      if (root.isPanelVisible) {
        root.sizeAnimationComplete = true
      }
    }
  }

  // Watchdog timer for open sequence
  Timer {
    id: openWatchdogTimer
    interval: Style.animationNormal * 3
    repeat: false
    onTriggered: {
      if (root.openWatchdogActive) {
        Logger.w("SmartPanelWindow", "Open watchdog timeout - forcing panel visible state", placeholder.panelName)
        root.openWatchdogActive = false
        if (root.isPanelOpen && !root.isPanelVisible) {
          root.isPanelVisible = true
          root.sizeAnimationComplete = true
        }
      }
    }
  }

  // Watchdog timer for close sequence
  Timer {
    id: closeWatchdogTimer
    interval: Style.animationFast * 3
    repeat: false
    onTriggered: {
      if (root.closeWatchdogActive && !root.closeFinalized) {
        Logger.w("SmartPanelWindow", "Close watchdog timeout - forcing panel close", placeholder.panelName)
        Qt.callLater(root.finalizeClose)
      }
    }
  }

  // Watch for placeholder size animation completion to finalize close
  Connections {
    target: placeholder.panelItem

    function onTargetWidthChanged() {
      // Update cached window size when target changes (not during animation)
      root.updateWindowSize()
    }

    function onTargetHeightChanged() {
      // Update cached window size when target changes (not during animation)
      root.updateWindowSize()
    }

    function onWidthChanged() {
      // When width shrinks to 0 during close and we're animating width, finalize
      if (root.isClosing && placeholder.panelItem.width === 0 && placeholder.panelItem.shouldAnimateWidth) {
        Qt.callLater(root.finalizeClose)
      }
    }

    function onHeightChanged() {
      // When height shrinks to 0 during close and we're animating height, finalize
      if (root.isClosing && placeholder.panelItem.height === 0 && placeholder.panelItem.shouldAnimateHeight) {
        Qt.callLater(root.finalizeClose)
      }
    }
  }
}
