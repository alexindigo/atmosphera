import QtQuick
import Quickshell
import qs.Commons
import qs.Services


/**
 * NPanel for use within NFullScreenWindow
 */
Item {
  id: root

  // Screen property provided by NFullScreenWindow
  property ShellScreen screen: null

  readonly property real opacityThreshold: 0.33
  property bool forceDetached: false // Force panel to be detached regardless of settings
  property bool attachedToBar: (Settings.data.ui.panelsAttachedToBar && Settings.data.bar.backgroundOpacity > opacityThreshold && !forceDetached)

  // Keyboard focus documentation (not currently used for focus mode)
  // Just for documentation: true for panels with text input
  // NFullScreenWindow always uses Exclusive focus when any panel is open
  property bool panelKeyboardFocus: false

  property Component panelContent: null

  // Panel size properties
  property real preferredWidth: 700
  property real preferredHeight: 900
  property real preferredWidthRatio
  property real preferredHeightRatio
  property color panelBackgroundColor: Color.mSurface
  property color panelBorderColor: Color.mOutline
  property var buttonItem: null

  // Anchoring properties
  property bool panelAnchorHorizontalCenter: false
  property bool panelAnchorVerticalCenter: false
  property bool panelAnchorTop: false
  property bool panelAnchorBottom: false
  property bool panelAnchorLeft: false
  property bool panelAnchorRight: false

  // Button position properties
  property bool useButtonPosition: false
  property point buttonPosition: Qt.point(0, 0)
  property int buttonWidth: 0
  property int buttonHeight: 0

  // Track whether panel is open
  property bool isPanelOpen: false

  // Animation properties
  property real animationProgress: 0
  property bool isClosing: false

  // Keyboard event handlers - override these in specific panels to handle shortcuts
  // These are called from NFullScreenWindow's centralized shortcuts
  function onEscapePressed() {
    close()
  }
  function onTabPressed() {}
  function onShiftTabPressed() {}
  function onUpPressed() {}
  function onDownPressed() {}
  function onLeftPressed() {}
  function onRightPressed() {}
  function onReturnPressed() {}
  function onHomePressed() {}
  function onEndPressed() {}
  function onPageUpPressed() {}
  function onPageDownPressed() {}
  function onCtrlJPressed() {}
  function onCtrlKPressed() {}

  Behavior on animationProgress {
    NumberAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
      onRunningChanged: {
        // When close animation finishes, actually hide the panel
        if (!running && root.isClosing) {
          root.isClosing = false
          root.isPanelOpen = false
        }
      }
    }
  }

  // Expose panel region for click-through mask (only when open)
  readonly property var panelRegion: panelContentContainer.item?.maskRegion || null

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  readonly property bool barFloating: Settings.data.bar.floating || false
  readonly property real barMarginH: barFloating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0
  readonly property real barMarginV: barFloating ? Settings.data.bar.marginVertical * Style.marginXL : 0

  // Helper to detect if any anchor is explicitly set
  readonly property bool hasExplicitHorizontalAnchor: panelAnchorHorizontalCenter || panelAnchorLeft || panelAnchorRight
  readonly property bool hasExplicitVerticalAnchor: panelAnchorVerticalCenter || panelAnchorTop || panelAnchorBottom

  // Effective anchor properties
  // These are true when:
  // 1. Explicitly anchored, OR
  // 2. Using button position and bar is on that edge, OR
  // 3. Attached to bar with no explicit anchors (default centering behavior)
  readonly property bool effectivePanelAnchorTop: panelAnchorTop || (useButtonPosition && barPosition === "top") || (attachedToBar && !hasExplicitVerticalAnchor && barPosition === "top" && !barIsVertical)
  readonly property bool effectivePanelAnchorBottom: panelAnchorBottom || (useButtonPosition && barPosition === "bottom") || (attachedToBar && !hasExplicitVerticalAnchor && barPosition === "bottom" && !barIsVertical)
  readonly property bool effectivePanelAnchorLeft: panelAnchorLeft || (useButtonPosition && barPosition === "left") || (attachedToBar && !hasExplicitHorizontalAnchor && barPosition === "left" && barIsVertical)
  readonly property bool effectivePanelAnchorRight: panelAnchorRight || (useButtonPosition && barPosition === "right") || (attachedToBar && !hasExplicitHorizontalAnchor && barPosition === "right" && barIsVertical)

  signal opened
  signal closed

  // Panel visibility and sizing
  // Keep visible during close animation
  visible: isPanelOpen || isClosing
  width: parent ? parent.width : 0
  height: parent ? parent.height : 0

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
      buttonItem = BarService.lookupWidget(buttonName, screen.name)
    }

    if (buttonItem) {
      root.buttonItem = buttonItem
      // Map button position to screen coordinates
      var buttonPos = buttonItem.mapToItem(null, 0, 0)
      root.buttonPosition = Qt.point(buttonPos.x, buttonPos.y)
      root.buttonWidth = buttonItem.width
      root.buttonHeight = buttonItem.height
      root.useButtonPosition = true
    } else {
      // No button provided: reset button position mode
      root.buttonItem = null
      root.useButtonPosition = false
    }

    setPosition()
    isPanelOpen = true
    animationProgress = 1

    // Notify PanelService
    PanelService.willOpenPanel(root)

    // Delay the opened signal to ensure content is fully loaded
    // This ensures Component.onCompleted of the loaded content runs first
    Qt.callLater(() => {
                   opened()
                 })

    Logger.d("NPanel", "Opened panel", objectName)
    Logger.d("NPanel", "  Root size:", width, "x", height)
  }

  function close() {
    // Start close animation
    isClosing = true
    animationProgress = 0

    // Notify PanelService immediately
    PanelService.closedPanel(root)

    // Emit closed signal
    closed()

    Logger.d("NPanel", "Closing panel with animation", objectName)
    // isPanelOpen will be set to false when animation completes
  }

  function setPosition() {// Position calculation will be handled here
    // For now, panels will be positioned based on anchors
  }

  // Loader for panel content
  Loader {
    id: panelContentContainer
    anchors.fill: parent
    // Keep active during close animation
    active: root.isPanelOpen || root.isClosing
    asynchronous: false

    sourceComponent: Item {
      anchors.fill: parent

      // Expose panelBackground for mask region
      property alias maskRegion: panelBackground

      // The actual panel background and content
      Item {
        anchors.fill: parent

        NShapedRectangle {
          id: panelBackground

          backgroundColor: root.attachedToBar ? Qt.alpha(root.panelBackgroundColor, Settings.data.bar.backgroundOpacity) : root.panelBackgroundColor

          // Animation properties
          opacity: root.animationProgress
          scale: root.attachedToBar ? 1 : (0.95 + root.animationProgress * 0.05)

          // Transform origin for scale animation
          transformOrigin: {
            // For detached panels, scale from center
            if (!root.attachedToBar) {
              return Item.Center
            }

            // For bar-attached panels, scale from the edge touching the bar
            if (root.barPosition === "top")
              return Item.Top
            if (root.barPosition === "bottom")
              return Item.Bottom
            if (root.barPosition === "left")
              return Item.Left
            if (root.barPosition === "right")
              return Item.Right
            return Item.Center
          }

          topLeftRadius: Style.radiusL
          topRightRadius: Style.radiusL
          bottomLeftRadius: Style.radiusL
          bottomRightRadius: Style.radiusL

          // Inverted corners based on bar attachment
          // When attached to bar AND effectively anchored to it, the corner(s) touching the bar should be inverted
          topLeftInverted: root.attachedToBar && ((root.barPosition === "top" && !root.barIsVertical && root.effectivePanelAnchorTop) || (root.barPosition === "left" && root.barIsVertical && root.effectivePanelAnchorLeft))
          topRightInverted: root.attachedToBar && ((root.barPosition === "top" && !root.barIsVertical && root.effectivePanelAnchorTop) || (root.barPosition === "right" && root.barIsVertical && root.effectivePanelAnchorRight))
          bottomLeftInverted: root.attachedToBar && ((root.barPosition === "bottom" && !root.barIsVertical && root.effectivePanelAnchorBottom) || (root.barPosition === "left" && root.barIsVertical && root.effectivePanelAnchorLeft))
          bottomRightInverted: root.attachedToBar && ((root.barPosition === "bottom" && !root.barIsVertical && root.effectivePanelAnchorBottom) || (root.barPosition === "right" && root.barIsVertical && root.effectivePanelAnchorRight))

          // Set inverted corner direction based on which edge touches the bar
          // For horizontal bars (top/bottom): left/right edges touch bar → horizontal curves
          // For vertical bars (left/right): top/bottom edges touch bar → vertical curves
          topLeftInvertedDirection: root.barIsVertical ? "vertical" : "horizontal"
          topRightInvertedDirection: root.barIsVertical ? "vertical" : "horizontal"
          bottomLeftInvertedDirection: root.barIsVertical ? "vertical" : "horizontal"
          bottomRightInvertedDirection: root.barIsVertical ? "vertical" : "horizontal"
          width: {
            var w
            // Priority 1: Content-driven size (dynamic)
            if (contentLoader.item && contentLoader.item.contentPreferredWidth !== undefined) {
              w = contentLoader.item.contentPreferredWidth
            } // Priority 2: Ratio-based size
            else if (root.preferredWidthRatio !== undefined) {
              w = Math.round(Math.max((parent.width || 1920) * root.preferredWidthRatio, root.preferredWidth))
            } // Priority 3: Static preferred width
            else {
              w = root.preferredWidth
            }
            return Math.min(w, (parent.width || 1920) - Style.marginL * 2)
          }

          height: {
            var h
            // Priority 1: Content-driven size (dynamic)
            if (contentLoader.item && contentLoader.item.contentPreferredHeight !== undefined) {
              h = contentLoader.item.contentPreferredHeight
            } // Priority 2: Ratio-based size
            else if (root.preferredHeightRatio !== undefined) {
              h = Math.round(Math.max((parent.height || 1080) * root.preferredHeightRatio, root.preferredHeight))
            } // Priority 3: Static preferred height
            else {
              h = root.preferredHeight
            }
            return Math.min(h, (parent.height || 1080) - Style.barHeight - Style.marginL * 2)
          }

          // Animation offset for slide effect on bar-attached panels
          readonly property real slideOffset: root.attachedToBar ? (1 - root.animationProgress) * 40 : 0

          // Position the panel using explicit x/y coordinates (no anchors)
          // This makes coordinates clearer for the click-through mask system
          x: {
            // If useButtonPosition is enabled, align panel X with button
            // Note: We check useButtonPosition, not buttonItem, because buttonItem may become invalid
            // after the source panel (e.g., ControlCenter) closes, but we still have valid position data
            if (root.useButtonPosition && parent.width > 0 && width > 0) {
              if (root.barIsVertical) {
                // For vertical bars
                if (root.attachedToBar) {
                  // Attached panels: align with bar edge (left or right side)
                  if (root.barPosition === "left") {
                    // Panel to the right of left bar
                    var leftBarEdge = root.barMarginH + Style.barHeight
                    // Panel sits right at bar edge (inverted corners curve up/down)
                    // Slide from the bar when opening
                    // Shift left by 1px to eliminate any gap between bar and panel
                    return leftBarEdge - slideOffset - 1
                  } else {
                    // right
                    // Panel to the left of right bar
                    var rightBarEdge = parent.width - root.barMarginH - Style.barHeight
                    // Panel sits right at bar edge (inverted corners curve up/down)
                    // Slide from the bar when opening
                    // Shift right by 1px to eliminate any gap between bar and panel
                    return rightBarEdge - width + slideOffset + 1
                  }
                } else {
                  // Detached panels: center on button X position
                  var panelX = root.buttonPosition.x + root.buttonWidth / 2 - width / 2
                  // Clamp to screen bounds with margins
                  panelX = Math.max(Style.marginL, Math.min(panelX, parent.width - width - Style.marginL))
                  return panelX
                }
              } else {
                // For horizontal bars, center panel on button X position
                var panelX = root.buttonPosition.x + root.buttonWidth / 2 - width / 2
                // Clamp to bar bounds (account for floating bar margins)
                // When attached, panel should not extend beyond bar edges
                if (root.attachedToBar) {
                  // Inverted corners with horizontal direction extend left/right by radiusL
                  // When bar is floating, it also has rounded corners, so we need extra inset
                  var cornerInset = Style.radiusL + (root.barFloating ? Style.radiusL : 0)
                  var barLeftEdge = root.barMarginH + cornerInset
                  var barRightEdge = parent.width - root.barMarginH - cornerInset
                  panelX = Math.max(barLeftEdge, Math.min(panelX, barRightEdge - width))
                } else {
                  panelX = Math.max(Style.marginL, Math.min(panelX, parent.width - width - Style.marginL))
                }
                return panelX
              }
            }

            // Standard anchor positioning
            Logger.d("NPanel", "Fallback to standard anchor positioning")

            if (root.panelAnchorHorizontalCenter) {
              Logger.d("NPanel", "  -> Horizontal center")
              return (parent.width - width) / 2
            } else if (root.effectivePanelAnchorRight) {
              Logger.d("NPanel", "  -> Right anchor")
              return parent.width - width - Style.marginL
            } else if (root.effectivePanelAnchorLeft) {
              Logger.d("NPanel", "  -> Left anchor")
              return Style.marginL
            } else {
              // No explicit anchor: default to centering on bar
              Logger.d("NPanel", "  -> Default to center (no explicit anchor)")

              // For horizontal bars: center horizontally
              // For vertical bars: center horizontally in available space
              if (root.barIsVertical) {
                // Center in the space not occupied by the bar
                if (root.barPosition === "left") {
                  var availableStart = root.barMarginH + Style.barHeight
                  var availableWidth = parent.width - availableStart - Style.marginL
                  return availableStart + (availableWidth - width) / 2
                } else {
                  // right
                  var availableWidth = parent.width - root.barMarginH - Style.barHeight - Style.marginL
                  return Style.marginL + (availableWidth - width) / 2
                }
              } else {
                // For horizontal bars: center horizontally, respect bar margins if attached
                if (root.attachedToBar) {
                  // When attached, respect bar bounds (like button position does)
                  var cornerInset = Style.radiusL + (root.barFloating ? Style.radiusL : 0)
                  var barLeftEdge = root.barMarginH + cornerInset
                  var barRightEdge = parent.width - root.barMarginH - cornerInset
                  var centeredX = (parent.width - width) / 2
                  return Math.max(barLeftEdge, Math.min(centeredX, barRightEdge - width))
                } else {
                  return (parent.width - width) / 2
                }
              }
            }
          }

          y: {
            // If useButtonPosition is enabled, position panel relative to bar
            // Note: We check useButtonPosition, not buttonItem, because buttonItem may become invalid
            // after the source panel (e.g., ControlCenter) closes, but we still have valid position data
            if (root.useButtonPosition && parent.height > 0 && height > 0) {
              if (root.barPosition === "top") {
                // Panel below top bar
                var topBarEdge = root.barMarginV + Style.barHeight
                if (root.attachedToBar) {
                  // Panel sits right at bar edge (inverted corners curve to the sides)
                  // Slide from the bar when opening
                  // Shift up by 1px to eliminate any gap between bar and panel
                  return topBarEdge - slideOffset - 1
                } else {
                  return topBarEdge + Style.marginM
                }
              } else if (root.barPosition === "bottom") {
                // Panel above bottom bar
                var bottomBarEdge = parent.height - root.barMarginV - Style.barHeight
                if (root.attachedToBar) {
                  // Panel sits right at bar edge (inverted corners curve to the sides)
                  // Slide from the bar when opening
                  // Shift down by 1px to eliminate any gap between bar and panel
                  return bottomBarEdge - height + slideOffset + 1
                } else {
                  return bottomBarEdge - height - Style.marginM
                }
              } else if (root.barIsVertical) {
                // For vertical bars, center panel on button Y position
                var panelY = root.buttonPosition.y + root.buttonHeight / 2 - height / 2
                // Clamp to bar bounds (account for floating bar margins and inverted corners)
                var extraPadding = root.attachedToBar ? Style.radiusL : 0
                if (root.attachedToBar) {
                  // When attached, panel should not extend beyond bar edges (accounting for floating margins)
                  // Inverted corners with vertical direction extend up/down by radiusL
                  // When bar is floating, it also has rounded corners, so we need extra inset
                  var cornerInset = extraPadding + (root.barFloating ? Style.radiusL : 0)
                  var barTopEdge = root.barMarginV + cornerInset
                  var barBottomEdge = parent.height - root.barMarginV - cornerInset
                  panelY = Math.max(barTopEdge, Math.min(panelY, barBottomEdge - height))
                } else {
                  panelY = Math.max(Style.marginL + extraPadding, Math.min(panelY, parent.height - height - Style.marginL - extraPadding))
                }
                return panelY
              }
            }

            // Standard anchor positioning
            // Calculate bar offset for detached panels - they should never overlap the bar
            var barOffset = 0
            if (!root.attachedToBar) {
              // For detached panels, always account for bar position
              if (root.barPosition === "top") {
                barOffset = root.barMarginV + Style.barHeight + Style.marginM
              } else if (root.barPosition === "bottom") {
                barOffset = root.barMarginV + Style.barHeight + Style.marginM
              }
            } else {
              // For attached panels with explicit anchors
              if (root.effectivePanelAnchorTop && root.barPosition === "top") {
                // When attached to top bar: position right at bar edge (like useButtonPosition does)
                // Shift up by 1px to eliminate gap between bar and panel
                return root.barMarginV + Style.barHeight - slideOffset - 1
              } else if (root.effectivePanelAnchorBottom && root.barPosition === "bottom") {
                // When attached to bottom bar: position right at bar edge
                // Shift down by 1px to eliminate gap between bar and panel
                return parent.height - root.barMarginV - Style.barHeight - height + slideOffset + 1
              } else if (!root.hasExplicitVerticalAnchor) {
                // No explicit vertical anchor AND attached: default to attaching to bar edge
                if (root.barPosition === "top") {
                  // Attach to top bar
                  return root.barMarginV + Style.barHeight - slideOffset - 1
                } else if (root.barPosition === "bottom") {
                  // Attach to bottom bar
                  return parent.height - root.barMarginV - Style.barHeight - height + slideOffset + 1
                }
                // For vertical bars with no explicit anchor: center vertically on bar
                // This is handled in the else block below
              }
            }

            if (root.panelAnchorVerticalCenter) {
              return (parent.height - height) / 2
            } else if (root.effectivePanelAnchorTop) {
              return barOffset + Style.marginL
            } else if (root.effectivePanelAnchorBottom) {
              return parent.height - height - barOffset - Style.marginL
            } else {
              // No explicit vertical anchor
              if (root.barIsVertical) {
                // For vertical bars: center vertically on bar
                if (root.attachedToBar) {
                  // When attached, respect bar bounds
                  var cornerInset = Style.radiusL + (root.barFloating ? Style.radiusL : 0)
                  var barTopEdge = root.barMarginV + cornerInset
                  var barBottomEdge = parent.height - root.barMarginV - cornerInset
                  var centeredY = (parent.height - height) / 2
                  return Math.max(barTopEdge, Math.min(centeredY, barBottomEdge - height))
                } else {
                  return (parent.height - height) / 2
                }
              } else {
                // For horizontal bars: attach to bar edge by default
                if (root.attachedToBar) {
                  if (root.barPosition === "top") {
                    return root.barMarginV + Style.barHeight - slideOffset - 1
                  } else if (root.barPosition === "bottom") {
                    return parent.height - root.barMarginV - Style.barHeight - height + slideOffset + 1
                  }
                }
                // Detached or no bar position: use default positioning
                if (root.barPosition === "top") {
                  return barOffset + Style.marginL
                } else if (root.barPosition === "bottom") {
                  return Style.marginL
                } else {
                  return Style.marginL
                }
              }
            }
          }

          // MouseArea to catch clicks on the panel and prevent them from reaching the background
          // This prevents closing the panel when clicking inside it
          MouseArea {
            anchors.fill: parent
            z: -1 // Behind content, but on the panel background
            onClicked: {

              // Accept and ignore - prevents propagation to background
            }
          }

          // Panel content loader
          Loader {
            id: contentLoader
            anchors.fill: parent
            sourceComponent: root.panelContent
          }
        }
      }
    }
  }
}
