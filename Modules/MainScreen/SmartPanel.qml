import QtQuick
import Quickshell
import qs.Commons
import qs.Services


/**
 * SmartPanel for use within MainScreen
 */
Item {
  id: root

  // Screen property provided by MainScreen
  property ShellScreen screen: null

  // Panel content: Text, icons, etc...
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

  // Edge snapping: if panel is within this distance (in pixels) from a screen edge, snap
  property real edgeSnapDistance: 50

  // Track whether panel is open
  property bool isPanelOpen: false

  // Track actual visibility (delayed until content is loaded and sized)
  property bool isPanelVisible: false

  // Track size animation completion for sequential opacity animation
  property bool sizeAnimationComplete: false

  // Track close animation state: fade opacity first, then shrink size
  property bool isClosing: false
  property bool opacityFadeComplete: false

  // Keyboard event handlers - override these in specific panels to handle shortcuts
  // These are called from MainScreen's centralized shortcuts
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

  // Expose panel region for click-through mask
  readonly property var panelRegion: panelContent.maskRegion

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  readonly property bool barFloating: Settings.data.bar.floating
  readonly property real barMarginH: barFloating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0
  readonly property real barMarginV: barFloating ? Settings.data.bar.marginVertical * Style.marginXL : 0

  // Helper to detect if any anchor is explicitly set
  readonly property bool hasExplicitHorizontalAnchor: panelAnchorHorizontalCenter || panelAnchorLeft || panelAnchorRight
  readonly property bool hasExplicitVerticalAnchor: panelAnchorVerticalCenter || panelAnchorTop || panelAnchorBottom

  // Effective anchor properties (depend on couldAttach)
  // These are true when:
  // 1. Explicitly anchored, OR
  // 2. Using button position and bar is on that edge, OR
  // 3. Attached to bar with no explicit anchors (default centering behavior)
  readonly property bool effectivePanelAnchorTop: panelAnchorTop || (useButtonPosition && barPosition === "top") || (panelContent.couldAttach && !hasExplicitVerticalAnchor && barPosition === "top" && !barIsVertical)
  readonly property bool effectivePanelAnchorBottom: panelAnchorBottom || (useButtonPosition && barPosition === "bottom") || (panelContent.couldAttach && !hasExplicitVerticalAnchor && barPosition === "bottom" && !barIsVertical)
  readonly property bool effectivePanelAnchorLeft: panelAnchorLeft || (useButtonPosition && barPosition === "left") || (panelContent.couldAttach && !hasExplicitHorizontalAnchor && barPosition === "left" && barIsVertical)
  readonly property bool effectivePanelAnchorRight: panelAnchorRight || (useButtonPosition && barPosition === "right") || (panelContent.couldAttach && !hasExplicitHorizontalAnchor && barPosition === "right" && barIsVertical)

  signal opened
  signal closed

  // Panel visibility and sizing
  visible: isPanelVisible
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

    // Set isPanelOpen to trigger content loading, but don't show yet
    isPanelOpen = true

    // Notify PanelService
    PanelService.willOpenPanel(root)

    // Position and visibility will be set by Loader.onLoaded
    // This ensures no flicker from default size to content size
  }

  function close() {
    // Start close sequence: fade opacity first
    isClosing = true
    sizeAnimationComplete = false

    // Stop the open animation timer if it's still running
    opacityTrigger.stop()

    // If opacity is already 0 (closed during open animation before fade-in),
    // skip directly to size animation
    if (root.opacity === 0.0) {
      opacityFadeComplete = true
    } else {
      opacityFadeComplete = false
    }

    // Opacity will fade out, then size will shrink, then finalizeClose() will complete
    Logger.d("SmartPanel", "Closing panel", objectName)
  }

  function finalizeClose() {
    // Complete the close sequence after animations finish
    isPanelVisible = false
    isPanelOpen = false
    isClosing = false
    opacityFadeComplete = false
    PanelService.closedPanel(root)
    closed()

    Logger.d("SmartPanel", "Panel close finalized", objectName)
  }

  function setPosition() {
    // Calculate panel dimensions first (needed for positioning)
    var w
    // Priority 1: Content-driven size (dynamic)
    if (contentLoader.item && contentLoader.item.contentPreferredWidth !== undefined) {
      w = contentLoader.item.contentPreferredWidth
    } // Priority 2: Ratio-based size
    else if (root.preferredWidthRatio !== undefined) {
      w = Math.round(Math.max((root.width || 1920) * root.preferredWidthRatio, root.preferredWidth))
    } // Priority 3: Static preferred width
    else {
      w = root.preferredWidth
    }
    var panelWidth = Math.min(w, (root.width || 1920) - Style.marginL * 2)

    var h
    // Priority 1: Content-driven size (dynamic)
    if (contentLoader.item && contentLoader.item.contentPreferredHeight !== undefined) {
      h = contentLoader.item.contentPreferredHeight
    } // Priority 2: Ratio-based size
    else if (root.preferredHeightRatio !== undefined) {
      h = Math.round(Math.max((root.height || 1080) * root.preferredHeightRatio, root.preferredHeight))
    } // Priority 3: Static preferred height
    else {
      h = root.preferredHeight
    }
    var panelHeight = Math.min(h, (root.height || 1080) - Style.barHeight - Style.marginL * 2)

    // Update panelBackground target size (will be animated)
    panelBackground.targetWidth = panelWidth
    panelBackground.targetHeight = panelHeight

    // Calculate position
    var calculatedX
    var calculatedY

    // ===== X POSITIONING =====
    if (root.useButtonPosition && root.width > 0 && panelWidth > 0) {
      if (root.barIsVertical) {
        // For vertical bars
        if (panelContent.couldAttach) {
          // Attached panels: align with bar edge (left or right side)
          if (root.barPosition === "left") {
            var leftBarEdge = root.barMarginH + Style.barHeight
            calculatedX = leftBarEdge
          } else {
            // right
            var rightBarEdge = root.width - root.barMarginH - Style.barHeight
            calculatedX = rightBarEdge - panelWidth
          }
        } else {
          // Detached panels: center on button X position
          var panelX = root.buttonPosition.x + root.buttonWidth / 2 - panelWidth / 2
          var minX = Style.marginL
          var maxX = root.width - panelWidth - Style.marginL

          // Account for vertical bar taking up space
          if (root.barPosition === "left") {
            minX = root.barMarginH + Style.barHeight + Style.marginL
          } else if (root.barPosition === "right") {
            maxX = root.width - root.barMarginH - Style.barHeight - panelWidth - Style.marginL
          }

          panelX = Math.max(minX, Math.min(panelX, maxX))
          calculatedX = panelX
        }
      } else {
        // For horizontal bars, center panel on button X position
        var panelX = root.buttonPosition.x + root.buttonWidth / 2 - panelWidth / 2
        if (panelContent.couldAttach) {
          var cornerInset = root.barFloating ? Style.radiusL * 2 : 0
          var barLeftEdge = root.barMarginH + cornerInset
          var barRightEdge = root.width - root.barMarginH - cornerInset
          panelX = Math.max(barLeftEdge, Math.min(panelX, barRightEdge - panelWidth))
        } else {
          panelX = Math.max(Style.marginL, Math.min(panelX, root.width - panelWidth - Style.marginL))
        }
        calculatedX = panelX
      }
    } else {
      // Standard anchor positioning
      if (root.panelAnchorHorizontalCenter) {
        if (root.barIsVertical) {
          if (root.barPosition === "left") {
            var availableStart = root.barMarginH + Style.barHeight
            var availableWidth = root.width - availableStart
            calculatedX = availableStart + (availableWidth - panelWidth) / 2
          } else if (root.barPosition === "right") {
            var availableWidth = root.width - root.barMarginH - Style.barHeight
            calculatedX = (availableWidth - panelWidth) / 2
          } else {
            calculatedX = (root.width - panelWidth) / 2
          }
        } else {
          calculatedX = (root.width - panelWidth) / 2
        }
      } else if (root.effectivePanelAnchorRight) {
        if (panelContent.couldAttach && root.barIsVertical && root.barPosition === "right") {
          var rightBarEdge = root.width - root.barMarginH - Style.barHeight
          calculatedX = rightBarEdge - panelWidth
        } else if (panelContent.couldAttach) {
          calculatedX = root.width - panelWidth
        } else {
          calculatedX = root.width - panelWidth - Style.marginL
        }
      } else if (root.effectivePanelAnchorLeft) {
        if (panelContent.couldAttach && root.barIsVertical && root.barPosition === "left") {
          var leftBarEdge = root.barMarginH + Style.barHeight
          calculatedX = leftBarEdge
        } else if (panelContent.couldAttach) {
          calculatedX = 0
        } else {
          calculatedX = Style.marginL
        }
      } else {
        // No explicit anchor: default to centering on bar
        if (root.barIsVertical) {
          if (root.barPosition === "left") {
            var availableStart = root.barMarginH + Style.barHeight
            var availableWidth = root.width - availableStart - Style.marginL
            calculatedX = availableStart + (availableWidth - panelWidth) / 2
          } else {
            var availableWidth = root.width - root.barMarginH - Style.barHeight - Style.marginL
            calculatedX = Style.marginL + (availableWidth - panelWidth) / 2
          }
        } else {
          if (panelContent.couldAttach) {
            var cornerInset = Style.radiusL + (root.barFloating ? Style.radiusL : 0)
            var barLeftEdge = root.barMarginH + cornerInset
            var barRightEdge = root.width - root.barMarginH - cornerInset
            var centeredX = (root.width - panelWidth) / 2
            calculatedX = Math.max(barLeftEdge, Math.min(centeredX, barRightEdge - panelWidth))
          } else {
            calculatedX = (root.width - panelWidth) / 2
          }
        }
      }
    }

    // Edge snapping for X
    if (panelContent.couldAttach && !root.barFloating && root.width > 0 && panelWidth > 0) {
      var leftEdgePos = root.barMarginH
      if (root.barPosition === "left") {
        leftEdgePos = root.barMarginH + Style.barHeight
      }

      var rightEdgePos = root.width - root.barMarginH - panelWidth
      if (root.barPosition === "right") {
        rightEdgePos = root.width - root.barMarginH - Style.barHeight - panelWidth
      }

      if (Math.abs(calculatedX - leftEdgePos) <= root.edgeSnapDistance) {
        calculatedX = leftEdgePos
      } else if (Math.abs(calculatedX - rightEdgePos) <= root.edgeSnapDistance) {
        calculatedX = rightEdgePos
      }
    }

    // ===== Y POSITIONING =====
    if (root.useButtonPosition && root.height > 0 && panelHeight > 0) {
      if (root.barPosition === "top") {
        var topBarEdge = root.barMarginV + Style.barHeight
        if (panelContent.couldAttach) {
          calculatedY = topBarEdge
        } else {
          calculatedY = topBarEdge + Style.marginM
        }
      } else if (root.barPosition === "bottom") {
        var bottomBarEdge = root.height - root.barMarginV - Style.barHeight
        if (panelContent.couldAttach) {
          calculatedY = bottomBarEdge - panelHeight
        } else {
          calculatedY = bottomBarEdge - panelHeight - Style.marginM
        }
      } else if (root.barIsVertical) {
        var panelY = root.buttonPosition.y + root.buttonHeight / 2 - panelHeight / 2
        var extraPadding = (panelContent.couldAttach && root.barFloating) ? Style.radiusL : 0
        if (panelContent.couldAttach) {
          var cornerInset = extraPadding + (root.barFloating ? Style.radiusL : 0)
          var barTopEdge = root.barMarginV + cornerInset
          var barBottomEdge = root.height - root.barMarginV - cornerInset
          panelY = Math.max(barTopEdge, Math.min(panelY, barBottomEdge - panelHeight))
        } else {
          panelY = Math.max(Style.marginL + extraPadding, Math.min(panelY, root.height - panelHeight - Style.marginL - extraPadding))
        }
        calculatedY = panelY
      }
    } else {
      // Standard anchor positioning
      var barOffset = 0
      if (!panelContent.couldAttach) {
        if (root.barPosition === "top") {
          barOffset = root.barMarginV + Style.barHeight + Style.marginM
        } else if (root.barPosition === "bottom") {
          barOffset = root.barMarginV + Style.barHeight + Style.marginM
        }
      } else {
        if (root.effectivePanelAnchorTop && root.barPosition === "top") {
          calculatedY = root.barMarginV + Style.barHeight
        } else if (root.effectivePanelAnchorBottom && root.barPosition === "bottom") {
          calculatedY = root.height - root.barMarginV - Style.barHeight - panelHeight
        } else if (!root.hasExplicitVerticalAnchor) {
          if (root.barPosition === "top") {
            calculatedY = root.barMarginV + Style.barHeight
          } else if (root.barPosition === "bottom") {
            calculatedY = root.height - root.barMarginV - Style.barHeight - panelHeight
          }
        }
      }

      if (calculatedY === undefined) {
        if (root.panelAnchorVerticalCenter) {
          if (!root.barIsVertical) {
            if (root.barPosition === "top") {
              var availableStart = root.barMarginV + Style.barHeight
              var availableHeight = root.height - availableStart
              calculatedY = availableStart + (availableHeight - panelHeight) / 2
            } else if (root.barPosition === "bottom") {
              var availableHeight = root.height - root.barMarginV - Style.barHeight
              calculatedY = (availableHeight - panelHeight) / 2
            } else {
              calculatedY = (root.height - panelHeight) / 2
            }
          } else {
            calculatedY = (root.height - panelHeight) / 2
          }
        } else if (root.effectivePanelAnchorTop) {
          if (panelContent.couldAttach) {
            calculatedY = 0
          } else {
            var topBarOffset = (root.barPosition === "top") ? barOffset : 0
            calculatedY = topBarOffset + Style.marginL
          }
        } else if (root.effectivePanelAnchorBottom) {
          if (panelContent.couldAttach) {
            calculatedY = root.height - panelHeight
          } else {
            var bottomBarOffset = (root.barPosition === "bottom") ? barOffset : 0
            calculatedY = root.height - panelHeight - bottomBarOffset - Style.marginL
          }
        } else {
          if (root.barIsVertical) {
            if (panelContent.couldAttach) {
              var cornerInset = root.barFloating ? Style.radiusL * 2 : 0
              var barTopEdge = root.barMarginV + cornerInset
              var barBottomEdge = root.height - root.barMarginV - cornerInset
              var centeredY = (root.height - panelHeight) / 2
              calculatedY = Math.max(barTopEdge, Math.min(centeredY, barBottomEdge - panelHeight))
            } else {
              calculatedY = (root.height - panelHeight) / 2
            }
          } else {
            if (panelContent.couldAttach && !root.barIsVertical) {
              if (root.barPosition === "top") {
                calculatedY = root.barMarginV + Style.barHeight
              } else if (root.barPosition === "bottom") {
                calculatedY = root.height - root.barMarginV - Style.barHeight - panelHeight
              }
            } else {
              if (root.barPosition === "top") {
                calculatedY = barOffset + Style.marginL
              } else if (root.barPosition === "bottom") {
                calculatedY = Style.marginL
              } else {
                calculatedY = Style.marginL
              }
            }
          }
        }
      }
    }

    // Edge snapping for Y
    if (panelContent.couldAttach && !root.barFloating && root.height > 0 && panelHeight > 0) {
      var topEdgePos = root.barMarginV
      if (root.barPosition === "top") {
        topEdgePos = root.barMarginV + Style.barHeight
      }

      var bottomEdgePos = root.height - root.barMarginV - panelHeight
      if (root.barPosition === "bottom") {
        bottomEdgePos = root.height - root.barMarginV - Style.barHeight - panelHeight
      }

      if (Math.abs(calculatedY - topEdgePos) <= root.edgeSnapDistance) {
        calculatedY = topEdgePos
      } else if (Math.abs(calculatedY - bottomEdgePos) <= root.edgeSnapDistance) {
        calculatedY = bottomEdgePos
      }
    }

    // Apply calculated positions (set targets for animation)
    panelBackground.targetX = calculatedX
    panelBackground.targetY = calculatedY

    Logger.d("SmartPanel", "Position calculated:", calculatedX, calculatedY)
    Logger.d("SmartPanel", "  Panel size:", panelWidth, "x", panelHeight)
  }

  // Watch for changes in content-driven sizes and update position
  Connections {
    target: contentLoader.item
    ignoreUnknownSignals: true

    function onContentPreferredWidthChanged() {
      if (root.isPanelOpen && root.isPanelVisible) {
        root.setPosition()
      }
    }

    function onContentPreferredHeightChanged() {
      if (root.isPanelOpen && root.isPanelVisible) {
        root.setPosition()
      }
    }
  }

  // Opacity animation
  // Opening: fade in after size animation reaches 75%
  // Closing: fade out immediately
  opacity: {
    if (isClosing)
      return 0.0 // Fade out when closing
    if (isPanelVisible && sizeAnimationComplete)
      return 1.0 // Fade in when opening
    return 0.0
  }

  Behavior on opacity {
    NumberAnimation {
      id: opacityAnimation
      duration: Style.animationFast
      easing.type: Easing.OutQuad

      onRunningChanged: {
        // When opacity fade completes during close, trigger size animation
        if (!running && isClosing && root.opacity === 0.0) {
          opacityFadeComplete = true
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
      if (isPanelVisible) {
        sizeAnimationComplete = true
      }
    }
  }

  // ------------------------------------------------
  // Panel Content
  Item {
    id: panelContent
    anchors.fill: parent

    // Screen-dependent attachment properties
    readonly property bool couldAttach: Settings.data.ui.panelsAttachedToBar
    readonly property bool couldAttachToBar: {
      if (!Settings.data.ui.panelsAttachedToBar || Settings.data.bar.backgroundOpacity < 1.0) {
        return false
      }

      // A panel can only be attached to a bar if there is a bar on that screen
      var monitors = Settings.data.bar.monitors || []
      var result = monitors.length === 0 || monitors.includes(root.screen?.name || "")
      return result
    }

    // Edge detection - detect if panel is touching screen edges
    readonly property bool touchingLeftEdge: couldAttach && panelBackground.x <= 1
    readonly property bool touchingRightEdge: couldAttach && (panelBackground.x + panelBackground.width) >= (root.width - 1)
    readonly property bool touchingTopEdge: couldAttach && panelBackground.y <= 1
    readonly property bool touchingBottomEdge: couldAttach && (panelBackground.y + panelBackground.height) >= (root.height - 1)

    // Bar edge detection - detect if panel is touching bar edges (for cases where centered panels snap to bar due to height constraints)
    readonly property bool touchingTopBar: couldAttachToBar && root.barPosition === "top" && !root.barIsVertical && Math.abs(panelBackground.y - (root.barMarginV + Style.barHeight)) <= 1
    readonly property bool touchingBottomBar: couldAttachToBar && root.barPosition === "bottom" && !root.barIsVertical && Math.abs((panelBackground.y + panelBackground.height) - (root.height - root.barMarginV - Style.barHeight)) <= 1
    readonly property bool touchingLeftBar: couldAttachToBar && root.barPosition === "left" && root.barIsVertical && Math.abs(panelBackground.x - (root.barMarginH + Style.barHeight)) <= 1
    readonly property bool touchingRightBar: couldAttachToBar && root.barPosition === "right" && root.barIsVertical && Math.abs((panelBackground.x + panelBackground.width) - (root.width - root.barMarginH - Style.barHeight)) <= 1

    // Expose panelBackground for mask region
    property alias maskRegion: panelBackground

    // The actual panel background - provides geometry for PanelBackground rendering
    Item {
      id: panelBackground

      // Store target dimensions (set by setPosition())
      property real targetWidth: root.preferredWidth
      property real targetHeight: root.preferredHeight
      property real targetX: root.x
      property real targetY: root.y

      property var bezierCurve: [0.05, 0, 0.133, 0.06, 0.166, 0.4, 0.208, 0.82, 0.25, 1, 1, 1]

      // Animate based on bar orientation:
      // - Horizontal bars (top/bottom): animate height only (slide out from bar)
      // - Vertical bars (left/right): animate width only (slide out from bar)
      // When closing: wait for opacity fade to complete before shrinking
      x: targetX
      y: targetY
      width: {
        // When closing and opacity fade complete, start shrinking
        if (isClosing && opacityFadeComplete) {
          return root.barIsVertical ? 0 : targetWidth
        }
        // When closing but opacity hasn't completed, or when open, keep full size
        if (isClosing || isPanelVisible)
          return targetWidth
        // Default: shrink based on bar orientation
        return root.barIsVertical ? 0 : targetWidth
      }
      height: {
        // When closing and opacity fade complete, start shrinking
        if (isClosing && opacityFadeComplete) {
          return root.barIsVertical ? targetHeight : 0
        }
        // When closing but opacity hasn't completed, or when open, keep full size
        if (isClosing || isPanelVisible)
          return targetHeight
        // Default: shrink based on bar orientation
        return root.barIsVertical ? targetHeight : 0
      }

      Behavior on width {
        enabled: root.barIsVertical // Only animate width for vertical bars
        NumberAnimation {
          id: widthCloseAnimation
          duration: Style.animationNormal
          easing.type: Easing.BezierSpline
          easing.bezierCurve: panelBackground.bezierCurve

          onRunningChanged: {
            // When width shrink completes during close, finalize
            if (!running && isClosing && panelBackground.width === 0 && root.barIsVertical) {
              finalizeClose()
            }
          }
        }
      }

      Behavior on height {
        enabled: !root.barIsVertical // Only animate height for horizontal bars
        NumberAnimation {
          id: heightCloseAnimation
          duration: Style.animationNormal
          easing.type: Easing.BezierSpline
          easing.bezierCurve: panelBackground.bezierCurve

          onRunningChanged: {
            // When height shrink completes during close, finalize
            if (!running && isClosing && panelBackground.height === 0 && !root.barIsVertical) {
              finalizeClose()
            }
          }
        }
      }

      Behavior on x {
        NumberAnimation {
          duration: isPanelVisible ? Style.animationNormal : 0 // Instant when not visible to prevent (0,0) slide
          easing.type: Easing.BezierSpline
          easing.bezierCurve: panelBackground.bezierCurve
        }
      }

      Behavior on y {
        NumberAnimation {
          duration: isPanelVisible ? Style.animationNormal : 0 // Instant when not visible to prevent (0,0) slide
          easing.type: Easing.BezierSpline
          easing.bezierCurve: panelBackground.bezierCurve
        }
      }

      // Corner states for PanelBackground to read
      // State -1: No radius (flat/square corner)
      // State 0: Normal (inner curve)
      // State 1: Horizontal inversion (outer curve on X-axis)
      // State 2: Vertical inversion (outer curve on Y-axis)

      // Smart corner state calculation based on bar attachment and edge touching
      property int topLeftCornerState: {
        // Bar attachment: only attach to bar if bar opacity >= 1.0 (no color clash)
        var barInverted = panelContent.couldAttachToBar && ((root.barPosition === "top" && !root.barIsVertical && root.effectivePanelAnchorTop) || (root.barPosition === "left" && root.barIsVertical && root.effectivePanelAnchorLeft))
        // Also detect when panel touches bar edge (e.g., centered panel that's too tall)
        var barTouchInverted = panelContent.touchingTopBar || panelContent.touchingLeftBar
        // Screen edge contact: can attach to screen edges even if bar opacity < 1.0
        // For horizontal bars: invert when touching left/right edges
        // For vertical bars: invert when touching top/bottom edges
        var edgeInverted = panelContent.couldAttach && ((panelContent.touchingLeftEdge && !root.barIsVertical) || (panelContent.touchingTopEdge && root.barIsVertical))
        // Also invert when touching screen edge opposite to bar (e.g., bottom edge when bar is at top)
        var oppositeEdgeInverted = panelContent.couldAttach && (panelContent.touchingTopEdge && !root.barIsVertical && root.barPosition !== "top")

        if (barInverted || barTouchInverted || edgeInverted || oppositeEdgeInverted) {
          // Determine direction: horizontal bars → horizontal curves, vertical bars → vertical curves
          // Screen edges: opposite - left/right edges → vertical curves, top/bottom edges → horizontal curves
          if (panelContent.touchingLeftEdge && !root.barIsVertical)
            return 2 // Vertical inversion
          if (panelContent.touchingTopEdge && root.barIsVertical)
            return 1 // Horizontal inversion
          return root.barIsVertical ? 2 : 1
        }
        return 0 // Normal corner
      }

      property int topRightCornerState: {
        var barInverted = panelContent.couldAttachToBar && ((root.barPosition === "top" && !root.barIsVertical && root.effectivePanelAnchorTop) || (root.barPosition === "right" && root.barIsVertical && root.effectivePanelAnchorRight))
        var barTouchInverted = panelContent.touchingTopBar || panelContent.touchingRightBar
        var edgeInverted = panelContent.couldAttach && ((panelContent.touchingRightEdge && !root.barIsVertical) || (panelContent.touchingTopEdge && root.barIsVertical))
        var oppositeEdgeInverted = panelContent.couldAttach && (panelContent.touchingTopEdge && !root.barIsVertical && root.barPosition !== "top")

        if (barInverted || barTouchInverted || edgeInverted || oppositeEdgeInverted) {
          if (panelContent.touchingRightEdge && !root.barIsVertical)
            return 2
          if (panelContent.touchingTopEdge && root.barIsVertical)
            return 1
          return root.barIsVertical ? 2 : 1
        }
        return 0
      }

      property int bottomLeftCornerState: {
        var barInverted = panelContent.couldAttachToBar && ((root.barPosition === "bottom" && !root.barIsVertical && root.effectivePanelAnchorBottom) || (root.barPosition === "left" && root.barIsVertical && root.effectivePanelAnchorLeft))
        var barTouchInverted = panelContent.touchingBottomBar || panelContent.touchingLeftBar
        var edgeInverted = panelContent.couldAttach && ((panelContent.touchingLeftEdge && !root.barIsVertical) || (panelContent.touchingBottomEdge && root.barIsVertical))
        var oppositeEdgeInverted = panelContent.couldAttach && (panelContent.touchingBottomEdge && !root.barIsVertical && root.barPosition !== "bottom")

        if (barInverted || barTouchInverted || edgeInverted || oppositeEdgeInverted) {
          if (panelContent.touchingLeftEdge && !root.barIsVertical)
            return 2
          if (panelContent.touchingBottomEdge && root.barIsVertical)
            return 1
          return root.barIsVertical ? 2 : 1
        }
        return 0
      }

      property int bottomRightCornerState: {
        var barInverted = panelContent.couldAttachToBar && ((root.barPosition === "bottom" && !root.barIsVertical && root.effectivePanelAnchorBottom) || (root.barPosition === "right" && root.barIsVertical && root.effectivePanelAnchorRight))
        var barTouchInverted = panelContent.touchingBottomBar || panelContent.touchingRightBar
        var edgeInverted = panelContent.couldAttach && ((panelContent.touchingRightEdge && !root.barIsVertical) || (panelContent.touchingBottomEdge && root.barIsVertical))
        var oppositeEdgeInverted = panelContent.couldAttach && (panelContent.touchingBottomEdge && !root.barIsVertical && root.barPosition !== "bottom")

        if (barInverted || barTouchInverted || edgeInverted || oppositeEdgeInverted) {
          if (panelContent.touchingRightEdge && !root.barIsVertical)
            return 2
          if (panelContent.touchingBottomEdge && root.barIsVertical)
            return 1
          return root.barIsVertical ? 2 : 1
        }
        return 0
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
    }

    // Panel top content: Text, icons, etc...
    Loader {
      id: contentLoader
      active: isPanelOpen
      x: panelBackground.x
      y: panelBackground.y
      width: panelBackground.width
      height: panelBackground.height
      sourceComponent: root.panelContent

      // When content finishes loading, calculate position then make visible
      onLoaded: {
        // Calculate position FIRST so targetX/targetY are set before animation starts
        // This prevents the panel from animating from (0,0) on first open
        setPosition()

        // THEN make panel visible to start the animation from the correct position
        // Corner state bindings will have valid context
        isPanelVisible = true

        // Start timer to trigger opacity fade at 75% of size animation
        opacityTrigger.start()

        // Emit opened signal
        opened()
      }
    }
  }
}
