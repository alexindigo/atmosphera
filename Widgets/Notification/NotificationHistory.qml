import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Components
import qs.Settings
import QtQuick.Layouts

PanelWindow {
    id: notificationHistoryWin
    width: 400
    height: 500
    color: "transparent"
    visible: false
    screen: Quickshell.primaryScreen
    focusable: true
    anchors.top: true
    anchors.right: true
    margins.top: 4
    margins.right: 4

    property int maxHistory: 100
    property string configDir: Quickshell.configDir
    property string historyFilePath: configDir + "/notification_history.json"

    ListModel {
        id: historyModel // Holds notification objects
    }

    FileView {
        id: historyFileView
        path: historyFilePath
        blockLoading: true
        printErrors: true
        watchChanges: true
        
        JsonAdapter {
            id: historyAdapter
            property var notifications: [] // Array of notification objects
        }

        onFileChanged: {
            reload() // Reload if file changes on disk
        }

        onLoaded: {
            loadHistory() // Populate model after loading
        }

        onLoadFailed: function(error) {
            console.error("Failed to load history file:", error)
            if (error.includes("No such file")) {
                historyAdapter.notifications = [] // Create new file if missing
                writeAdapter()
            }
        }

        onSaved: {}
        onSaveFailed: function(error) {
            console.error("Failed to save history:", error)
        }

        Component.onCompleted: {
            if (path) reload()
        }
    }

    function loadHistory() {
        if (historyAdapter.notifications) {
            historyModel.clear()
            const notifications = historyAdapter.notifications
            const count = Math.min(notifications.length, maxHistory)
            for (let i = 0; i < count; i++) {
                if (typeof notifications[i] === 'object' && notifications[i] !== null) {
                    historyModel.append(notifications[i])
                }
            }
        }
    }

    function saveHistory() {
        const historyArray = []
        const count = Math.min(historyModel.count, maxHistory)
        for (let i = 0; i < count; ++i) {
            let obj = historyModel.get(i)
            if (typeof obj === 'object' && obj !== null) {
                historyArray.push({
                    id: obj.id,
                    appName: obj.appName,
                    summary: obj.summary,
                    body: obj.body,
                    timestamp: obj.timestamp
                })
            }
        }
        historyAdapter.notifications = historyArray
        Qt.callLater(function() {
            historyFileView.writeAdapter()
        })
    }

    function addToHistory(notification) {
        if (!notification.id) notification.id = Date.now()
        if (!notification.timestamp) notification.timestamp = new Date().toISOString()
        for (let i = 0; i < historyModel.count; ++i) {
            if (historyModel.get(i).id === notification.id) {
                historyModel.remove(i)
                break
            }
        }
        historyModel.insert(0, notification)
        if (historyModel.count > maxHistory) historyModel.remove(maxHistory)
        saveHistory()
    }

    function clearHistory() {
        historyModel.clear()
        historyAdapter.notifications = []
        historyFileView.writeAdapter()
    }

    function formatTimestamp(ts) {
        if (!ts) return "";
        var date = typeof ts === "number" ? new Date(ts) : new Date(Date.parse(ts));
        var y = date.getFullYear();
        var m = (date.getMonth()+1).toString().padStart(2,'0');
        var d = date.getDate().toString().padStart(2,'0');
        var h = date.getHours().toString().padStart(2,'0');
        var min = date.getMinutes().toString().padStart(2,'0');
        return `${y}-${m}-${d} ${h}:${min}`;
    }

    Rectangle {
        width: notificationHistoryWin.width
        height: notificationHistoryWin.height
        anchors.fill: parent
        color: Theme.backgroundPrimary
        radius: 20

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            RowLayout {
                spacing: 4
                anchors.top: parent.top
                anchors.topMargin: 16
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                Text {
                    text: "Notification History"
                    font.pixelSize: 18
                    font.bold: true
                    color: Theme.textPrimary
                    Layout.alignment: Qt.AlignVCenter
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    id: clearAllButton
                    width: 90
                    height: 32
                    radius: 20
                    color: clearAllMouseArea.containsMouse ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: Theme.accentPrimary
                    border.width: 1
                    Layout.alignment: Qt.AlignVCenter
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: "delete_sweep"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 14
                            color: clearAllMouseArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            text: "Clear"
                            font.pixelSize: Theme.fontSizeSmall
                            color: clearAllMouseArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                            font.bold: true
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    MouseArea {
                        id: clearAllMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: notificationHistoryWin.clearHistory()
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 0
                color: "transparent"
                visible: true
            }

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 56
                anchors.bottom: parent.bottom
                color: Theme.surfaceVariant
                radius: 20

                Rectangle {
                    anchors.fill: parent
                    color: Theme.backgroundPrimary
                    radius: 20
                    border.width: 1
                    border.color: Theme.surfaceVariant
                    z: 0
                }
                Rectangle {
                    id: listContainer
                    anchors.fill: parent
                    anchors.topMargin: 12
                    anchors.bottomMargin: 12
                    color: "transparent"
                    clip: true
                    ListView {
                        id: historyList
                        anchors.fill: parent
                        spacing: 12
                        model: historyModel
                        delegate: Item {
                            height: notificationCard.implicitHeight + 12
                            Rectangle {
                                id: notificationCard
                                width: parent.width - 24
                                anchors.horizontalCenter: parent.horizontalCenter
                                color: Theme.backgroundPrimary
                                radius: 16
                                border.color: Theme.outline
                                border.width: 1
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: 0
                                implicitHeight: contentColumn.implicitHeight + 20
                                Column {
                                    id: contentColumn
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 6
                                    RowLayout {
                                        id: headerRow
                                        spacing: 8
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.rightMargin: 0
                                        Rectangle {
                                            id: iconBackground
                                            width: 28
                                            height: 28
                                            radius: 20
                                            color: Theme.accentPrimary
                                            border.color: Qt.darker(Theme.accentPrimary, 1.2)
                                            border.width: 1.2
                                            Layout.alignment: Qt.AlignVCenter
                                            Text {
                                                anchors.centerIn: parent
                                                text: model.appName ? model.appName.charAt(0).toUpperCase() : "?"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 15
                                                font.bold: true
                                                color: Theme.backgroundPrimary
                                            }
                                        }
                                        Column {
                                            id: appInfoColumn
                                            spacing: 0
                                            Layout.alignment: Qt.AlignVCenter
                                            Text {
                                                text: model.appName || "Unknown App"
                                                font.bold: true
                                                color: Theme.textPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSmall
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            Text {
                                                text: formatTimestamp(model.timestamp)
                                                color: Theme.textSecondary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeCaption
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            id: deleteButton
                                            width: 24
                                            height: 24
                                            radius: 12
                                            color: deleteMouseArea.containsMouse ? Theme.accentPrimary : Theme.surfaceVariant
                                            border.color: Theme.accentPrimary
                                            border.width: 1
                                            Layout.alignment: Qt.AlignVCenter
                                            z: 2
                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 0
                                                Text {
                                                    text: "close"
                                                    font.family: "Material Symbols Outlined"
                                                    font.pixelSize: 16
                                                    color: deleteMouseArea.containsMouse ? Theme.onAccent : Theme.error
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                            }
                                            MouseArea {
                                                id: deleteMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    historyModel.remove(index)
                                                    saveHistory()
                                                }
                                            }
                                        }
                                    }
                                    Text {
                                        text: model.summary || ""
                                        color: Theme.textSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        width: parent.width
                                        wrapMode: Text.Wrap
                                    }
                                    Text {
                                        text: model.body || ""
                                        color: Theme.textDisabled
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        width: parent.width
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { width: 1; height: 24; color: "transparent" }
        }
    }
}