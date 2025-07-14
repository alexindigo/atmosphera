import QtQuick
import qs.Components

Item {
    id: root
    property int innerRadius: 34
    property int outerRadius: 48
    property color fillColor: "#fff"
    property color strokeColor: "#fff"
    property int strokeWidth: 0
    property var values: []

    width: outerRadius * 2
    height: outerRadius * 2

    Repeater {
        model: root.values.length
        Rectangle {
            property real value: root.values[index]
            property real angle: (index / root.values.length) * 360
            width: Math.max(2, (root.innerRadius * 2 * Math.PI) / root.values.length - 4)
            height: value * (root.outerRadius - root.innerRadius)
            radius: width / 2
            color: root.fillColor
            border.color: root.strokeColor
            border.width: root.strokeWidth
            antialiasing: true

            x: root.width / 2 + (root.innerRadius) * Math.cos(Math.PI/2 + 2 * Math.PI * index / root.values.length) - width / 2
            y: root.height / 2 - (root.innerRadius) * Math.sin(Math.PI/2 + 2 * Math.PI * index / root.values.length) - height

            transform: Rotation {
                origin.x: width / 2
                origin.y: height
                angle: -angle
            }

            Behavior on height { SmoothedAnimation { duration: 120 } }
        }
    }
} 