import QtQuick
import qs.Commons
import qs.Services
import Quickshell

Item {
    id: clockRoot

    property var now
    property color backgroundColor: Color.mPrimary
    property color clockColor: Color.mOnPrimary

    height: Math.round((Style.fontSizeXXXL * 1.9) / 2 * Style.uiScaleRatio) * 2
    width: clockRoot.height

    Loader {
        id: clockLoader
        anchors.fill: parent

        source: Settings.data.location.analogClockInCalendar ? "AnalogClock.qml" : "DigitalClock.qml"

        onLoaded: {
            // Bind the loaded item's 'now' property to *this* component's 'now' property
            item.now = Qt.binding(function() { return clockRoot.now })
            item.backgroundColor = Qt.binding(function() { return clockRoot.backgroundColor })
            item.clockColor = Qt.binding(function() { return clockRoot.clockColor })
        }
    }
}
