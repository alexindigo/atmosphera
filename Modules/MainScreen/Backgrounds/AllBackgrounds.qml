import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Widgets


/**
 * AllBackgrounds - Unified Shape container for all bar and panel backgrounds
 *
 * Unified shadow system. This component contains a single Shape
 * with multiple ShapePath children (one for bar, one for each panel type).
 *
 * Benefits:
 * - Single GPU-accelerated rendering pass for all backgrounds
 * - Unified shadow system (one MultiEffect for everything)
 */
Item {
  id: root

  // Reference Bar
  required property var bar

  // Reference to MainScreen (for panel access)
  required property var windowRoot

  anchors.fill: parent

  // Wrapper with layer caching for better shadow performance
  Item {
    anchors.fill: parent

    // Enable layer caching to prevent continuous re-rendering
    // This caches the Shape to a GPU texture, reducing GPU tessellation overhead
    layer.enabled: true

    // The unified Shape container
    Shape {
      id: backgroundsShape
      anchors.fill: parent

      // Use curve renderer for smooth corners (GPU-accelerated)
      preferredRendererType: Shape.CurveRenderer

      enabled: false // Disable mouse input on the Shape itself

      Component.onCompleted: {
        Logger.d("AllBackgrounds", "AllBackgrounds initialized")
        Logger.d("AllBackgrounds", "  bar:", root.bar)
        Logger.d("AllBackgrounds", "  windowRoot:", root.windowRoot)
      }


      /**
     *  Bar
     */
      BarBackground {
        bar: root.bar
        shapeContainer: backgroundsShape
      }


      /**
     *  Panels
     */

      // Audio
      PanelBackground {
        panel: root.windowRoot.audioPanel
        shapeContainer: backgroundsShape
      }

      // Battery
      PanelBackground {
        panel: root.windowRoot.batteryPanel
        shapeContainer: backgroundsShape
      }

      // Bluetooth
      PanelBackground {
        panel: root.windowRoot.bluetoothPanel
        shapeContainer: backgroundsShape
      }

      // Calendar
      PanelBackground {
        panel: root.windowRoot.calendarPanel
        shapeContainer: backgroundsShape
      }

      // Control Center
      PanelBackground {
        panel: root.windowRoot.controlCenterPanel
        shapeContainer: backgroundsShape
      }

      // Launcher
      PanelBackground {
        panel: root.windowRoot.launcherPanel
        shapeContainer: backgroundsShape
      }

      // Notification History
      PanelBackground {
        panel: root.windowRoot.notificationHistoryPanel
        shapeContainer: backgroundsShape
      }

      // Session Menu
      PanelBackground {
        panel: root.windowRoot.sessionMenuPanel
        shapeContainer: backgroundsShape
      }

      // Settings
      PanelBackground {
        panel: root.windowRoot.settingsPanel
        shapeContainer: backgroundsShape
      }

      // Setup Wizard
      PanelBackground {
        panel: root.windowRoot.setupWizardPanel
        shapeContainer: backgroundsShape
      }

      // TrayDrawer
      PanelBackground {
        panel: root.windowRoot.trayDrawerPanel
        shapeContainer: backgroundsShape
      }

      // TrayMenu
      PanelBackground {
        panel: root.windowRoot.trayMenuPanel
        shapeContainer: backgroundsShape
      }

      // Wallpaper
      PanelBackground {
        panel: root.windowRoot.wallpaperPanel
        shapeContainer: backgroundsShape
      }

      // WiFi
      PanelBackground {
        panel: root.windowRoot.wifiPanel
        shapeContainer: backgroundsShape
      }
    }

    // Apply shadow to the cached layer
    NDropShadows {
      anchors.fill: parent
      source: backgroundsShape
    }
  }
}
