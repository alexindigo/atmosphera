import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Quickshell.Io
import qs.Components
import qs.Services
import qs.Settings

Rectangle {
    id: systemMonitor
    width: 70
    height: 250
    color: "transparent"

    property bool isVisible: false

    Rectangle {
        id: card
        anchors.fill: parent
        color: Theme.surface
        radius: 18

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 12
            Layout.alignment: Qt.AlignVCenter

            // CPU Usage
            CircularProgressBar {
                progress: Sysinfo.cpuUsage / 100
                size: 50
                strokeWidth: 4
                hasNotch: true
                notchIcon: "speed"
                notchIconSize: 14
                Layout.alignment: Qt.AlignHCenter
            }

            // Cpu Temp
            CircularProgressBar {
                progress: Sysinfo.cpuTemp / 100
                size: 50
                strokeWidth: 4
                hasNotch: true
                units: "°C"
                notchIcon: "thermometer"
                notchIconSize: 14
                Layout.alignment: Qt.AlignHCenter
            }

            // Memory Usage
            CircularProgressBar {
                progress: Sysinfo.memoryUsagePer / 100
                size: 50
                strokeWidth: 4
                hasNotch: true
                notchIcon: "memory"
                notchIconSize: 14
                Layout.alignment: Qt.AlignHCenter
            }

            // Disk Usage
            CircularProgressBar {
                progress: Sysinfo.diskUsage / 100
                size: 50
                strokeWidth: 4
                hasNotch: true
                notchIcon: "storage"
                notchIconSize: 14
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
} 