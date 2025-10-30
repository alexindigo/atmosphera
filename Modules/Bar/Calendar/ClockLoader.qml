import QtQuick
import qs.Commons
import qs.Services
import Quickshell

Item {
    id: clockRoot

    property var now

    // Default colors
    property color backgroundColor: Color.mPrimary
    property color clockColor: Color.mOnPrimary
    readonly property real markAlpha: 0.7 // alpha value of hour markers in AnalogClock
    property color secondHandColor: {
        var defaultColor = Color.mError
        var backgroundL = backgroundColor.hslLightness
        var hourMarkL

        if (Settings.data.location.analogClockInCalendar) {
            hourMarkL = (clockColor.hslLightness * markAlpha) + (backgroundL * (1.0 - markAlpha))
        } else {
            hourMarkL = backgroundL
        }

        var bestWorstContrast = -1
        var bestColor = defaultColor

        var candidates = [
            Color.mSecondary,
            Color.mTertiary,
            Color.mError,
        ]

        for (var i = 0; i < candidates.length; i++) {
            var candidateColor = candidates[i]
            var candidateL = candidateColor.hslLightness

            var diffBackground = Math.abs(backgroundL - candidateL)
            var diffHourMark = Math.abs(hourMarkL - candidateL)

            var currentWorstContrast = Math.min(diffBackground, diffHourMark)

            if (currentWorstContrast > bestWorstContrast) {
                bestWorstContrast = currentWorstContrast
                bestColor = candidateColor
            }
        }

        return bestColor
    }
    property color progressColor: clockRoot.secondHandColor


    height: Math.round((Style.fontSizeXXXL * 1.9) / 2 * Style.uiScaleRatio) * 2
    width: clockRoot.height

    Loader {
        id: clockLoader
        anchors.fill: parent

        source: Settings.data.location.analogClockInCalendar ? "AnalogClock.qml" : "DigitalClock.qml"

        onLoaded: {
            item.now = Qt.binding(function() { return clockRoot.now })
            item.backgroundColor = Qt.binding(function() { return clockRoot.backgroundColor })
            item.clockColor = Qt.binding(function() { return clockRoot.clockColor })
            if (item.hasOwnProperty("secondHandColor")) {
                item.secondHandColor = Qt.binding(function() { return clockRoot.secondHandColor })
            }
            if (item.hasOwnProperty("progressColor")) {
                item.progressColor = Qt.binding(function() { return clockRoot.progressColor })
            }
            if (item.hasOwnProperty("markAlpha")) {
                item.markAlpha = Qt.binding(function() { return clockRoot.markAlpha })
            }
        }
    }
}
