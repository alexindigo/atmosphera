// Theme.qml
pragma Singleton
import QtQuick

QtObject {
    // Backgrounds
    readonly property color backgroundPrimary: "#0C0D11"     // Deep indigo-black
    readonly property color backgroundSecondary: "#151720"   // Slightly lifted dark
    readonly property color backgroundTertiary: "#1D202B"    // Soft contrast surface

    // Surfaces & Elevation
    readonly property color surface: "#1A1C26"               // Material-like base layer
    readonly property color surfaceVariant: "#2A2D3A"        // Lightly elevated

    // Text Colors
    readonly property color textPrimary: "#CACEE2"           // Gentle off-white
    readonly property color textSecondary: "#B7BBD0"         // Muted lavender-blue
    readonly property color textDisabled: "#6B718A"          // Dimmed blue-gray

    // Accent Colors (lavender-gold theme)
    readonly property color accentPrimary: "#A8AEFF"         // Light enchanted lavender
    readonly property color accentSecondary: "#9EA0FF"       // Softer lavender hue
    readonly property color accentTertiary: "#8EABFF"        // Warm golden glow (from lantern)

    // Error/Warning
    readonly property color error: "#FF6B81"                 // Soft rose red
    readonly property color warning: "#FFBB66"               // Candlelight amber-orange

    // Highlights & Focus
    readonly property color highlight: "#E3C2FF"             // Bright magical lavender
    readonly property color rippleEffect: "#F3DEFF"          // Gentle soft splash

    // Additional Theme Properties
    readonly property color onAccent: "#1A1A1A"              // Text on accent background
    readonly property color outline: "#44485A"               // Subtle bluish-gray line

    // Shadows & Overlays
    readonly property color shadow: "#000000B3"              // Standard soft black shadow
    readonly property color overlay: "#11121ACC"             // Deep bluish overlay

    // Font Properties
    readonly property string fontFamily: "Roboto"         // Family for all text
    
    readonly property int fontSizeHeader: 32              // Headers and titles
    readonly property int fontSizeBody: 16                // Body text and general content
    readonly property int fontSizeSmall: 14               // Small text like clock, labels
    readonly property int fontSizeCaption: 12             // Captions and fine print
}
