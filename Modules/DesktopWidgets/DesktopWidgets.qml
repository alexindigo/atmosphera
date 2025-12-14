import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

Variants {
  id: root
  model: Quickshell.screens
  
  delegate: Loader {
    required property ShellScreen modelData
    active: modelData && Settings.data.desktopWidgets.enabled
    
    sourceComponent: PanelWindow {
      id: window
      color: Color.transparent
      screen: modelData
      
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-desktop-widgets-" + (screen?.name || "unknown")
      
      anchors {
        top: true
        bottom: true
        right: true
        left: true
      }
      
      // Check if there's a focused workspace on this screen
      // Widgets only show on the currently active workspace to save resources
      function getFocusedWorkspaceForScreen() {
        if (!screen || !screen.name) {
          return false;
        }
        const screenName = screen.name.toLowerCase();
        
        for (var i = 0; i < CompositorService.workspaces.count; i++) {
          const ws = CompositorService.workspaces.get(i);
          if (ws.isFocused && ws.output && ws.output.toLowerCase() === screenName) {
            return true;
          }
        }
        return false;
      }
      
      property bool shouldShowWidgets: getFocusedWorkspaceForScreen()
      
      Connections {
        target: CompositorService
        function onWorkspaceChanged() {
          shouldShowWidgets = getFocusedWorkspaceForScreen();
        }
      }
      
      onScreenChanged: {
        shouldShowWidgets = getFocusedWorkspaceForScreen();
      }
      
      Item {
        id: widgetsContainer
        anchors.fill: parent
        
        // Collision detection to prevent widgets from overlapping
        function checkCollision(widget, newX, newY) {
          if (!widget || !widget.parent) return false;
          
          var widgetWidth = widget.width || 0;
          var widgetHeight = widget.height || 0;
          
          for (var i = 0; i < widgetsContainer.children.length; i++) {
            var child = widgetsContainer.children[i];
            
            // Skip self, container, and edit mode button (widgets can overlap button)
            if (child === widget || child === widgetsContainer || child === editModeButton) {
              continue;
            }
            
            var otherWidget = null;
            
            // Handle Loader items - get the actual widget from the Loader
            if (child.toString().indexOf("Loader") !== -1) {
              if (!child.active || !child.item) {
                continue;
              }
              otherWidget = child.item;
            } else {
              otherWidget = child;
            }
            
            if (!otherWidget || !otherWidget.visible) {
              continue;
            }
            
            if (otherWidget === widget) {
              continue;
            }
            
            var otherX = otherWidget.x || 0;
            var otherY = otherWidget.y || 0;
            var otherWidth = otherWidget.width || 0;
            var otherHeight = otherWidget.height || 0;
            
            // AABB overlap check
            if (newX < otherX + otherWidth && 
                newX + widgetWidth > otherX && 
                newY < otherY + otherHeight && 
                newY + widgetHeight > otherY) {
              return true;
            }
          }
          
          return false;
        }
        
        // Load widgets dynamically from array
        Repeater {
          model: Settings.data.desktopWidgets.widgets || []
          
          delegate: Loader {
            id: widgetLoader
            active: shouldShowWidgets && DesktopWidgetRegistry.hasWidget(modelData.id)
            
            property var widgetData: modelData
            property int widgetIndex: index
            
            sourceComponent: {
              var component = DesktopWidgetRegistry.getWidget(modelData.id);
              if (component) {
                return component;
              }
              return null;
            }
            
            onLoaded: {
              if (item) {
                item.screen = window.screen;
                item.parent = widgetsContainer;
                item.widgetData = widgetData;
                item.widgetIndex = widgetIndex;
              }
            }
          }
        }

        // Exit edit mode button
        NButton {
          id: editModeButton
          visible: Settings.data.desktopWidgets.editMode && Settings.data.desktopWidgets.enabled
          
          readonly property string barPos: Settings.data.bar.position || "top"
          readonly property bool barFloating: Settings.data.bar.floating || false
          // Calculate offset from bar based on position and floating state
          readonly property int barOffsetTop: {
            if (barPos !== "top") return Style.marginXL * Style.uiScaleRatio;
            const floatMarginV = barFloating ? Math.ceil(Settings.data.bar.marginVertical * Style.marginXL) : 0;
            return Style.barHeight + floatMarginV + Style.marginM + (Style.marginXL * Style.uiScaleRatio);
          }
          readonly property int barOffsetRight: {
            if (barPos !== "right") return Style.marginXL * Style.uiScaleRatio;
            const floatMarginH = barFloating ? Math.ceil(Settings.data.bar.marginHorizontal * Style.marginXL) : 0;
            return Style.barHeight + floatMarginH + Style.marginM + (Style.marginXL * Style.uiScaleRatio);
          }
          
          anchors {
            top: parent.top
            right: parent.right
            topMargin: barOffsetTop
            rightMargin: barOffsetRight
          }
          text: I18n.tr("settings.desktop-widgets.edit-mode.exit-button")
          icon: "check"
          backgroundColor: Color.mSurface
          textColor: Color.mOnSurface
          hoverColor: Color.mSurfaceVariant
          outlined: false
          fontSize: Style.fontSizeM * 1.1
          iconSize: Style.fontSizeL * 1.1
          z: 10000
          onClicked: Settings.data.desktopWidgets.editMode = false
        }
      }
    }
  }
}