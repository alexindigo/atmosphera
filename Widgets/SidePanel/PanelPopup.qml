import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Components
import qs.Settings
import qs.Widgets.SettingsWindow

PanelWithOverlay {
    id: sidebarPopup

    property var shell: null

    function showAt() {
        sidebarPopupRect.showAt();
    }

    function hidePopup() {
        sidebarPopupRect.hidePopup();
    }

    function show() {
        sidebarPopupRect.showAt();
    }

    function dismiss() {
        sidebarPopupRect.hidePopup();
    }

    // Trigger initial weather loading when component is completed
    Component.onCompleted: {
        // Load initial weather data after a short delay to ensure all components are ready
        Qt.callLater(function() {
            if (weather && weather.fetchCityWeather)
                weather.fetchCityWeather();

        });
    }

    Rectangle {
        // Access the shell's SettingsWindow instead of creating a new one

        id: sidebarPopupRect

        property real slideOffset: width
        property bool isAnimating: false
        property int leftPadding: 20 * Theme.uiScale
        property int bottomPadding: 20 * Theme.uiScale
        // Recording properties
        property bool isRecording: false

        Process {
            id: checkRecordingProcess
            command: ["pgrep", "-f", "gpu-screen-recorder.*portal"]
            onExited: function(exitCode, exitStatus) {
                var isActuallyRecording = exitCode === 0
                if (isRecording && !isActuallyRecording) {
                    isRecording = isActuallyRecording
                }
            }
        }

        function checkRecordingStatus() {
            if (isRecording) {
                checkRecordingProcess.running = true
            }
        }

        function showAt() {
            if (!sidebarPopup.visible) {
                sidebarPopup.visible = true;
                forceActiveFocus();
                slideAnim.from = width;
                slideAnim.to = 0;
                slideAnim.running = true;
                if (weather)
                    weather.startWeatherFetch();

                if (systemWidget)
                    systemWidget.panelVisible = true;
            }
        }

        function hidePopup() {
            if (shell && shell.settingsWindow && shell.settingsWindow.visible)
                shell.settingsWindow.visible = false;



            if (sidebarPopup.visible) {
                slideAnim.from = 0;
                slideAnim.to = width;
                slideAnim.running = true;
            }
        }

        // Start screen recording using Quickshell.execDetached
        function startRecording() {
            var currentDate = new Date();
            var hours = String(currentDate.getHours()).padStart(2, '0');
            var minutes = String(currentDate.getMinutes()).padStart(2, '0');
            var day = String(currentDate.getDate()).padStart(2, '0');
            var month = String(currentDate.getMonth() + 1).padStart(2, '0');
            var year = currentDate.getFullYear();
            var filename = hours + "-" + minutes + "-" + day + "-" + month + "-" + year + ".mp4";
            var videoPath = Settings.settings.videoPath;
            if (videoPath && !videoPath.endsWith("/"))
                videoPath += "/";

            var outputPath = videoPath + filename;
            var command = "gpu-screen-recorder -w portal" + " -f " + Settings.settings.recordingFrameRate + " -a default_output" + " -k " + Settings.settings.recordingCodec + " -ac " + Settings.settings.audioCodec + " -q " + Settings.settings.recordingQuality + " -cursor " + (Settings.settings.showCursor ? "yes" : "no") + " -cr " + Settings.settings.colorRange + " -o " + outputPath;
            Quickshell.execDetached(["sh", "-c", command]);
            isRecording = true;
        }

        // Stop recording using Quickshell.execDetached
        function stopRecording() {
            Quickshell.execDetached(["sh", "-c", "pkill -SIGINT -f 'gpu-screen-recorder.*portal'"]);
            // Optionally, force kill after a delay
            var cleanupTimer = Qt.createQmlObject('import QtQuick; Timer { interval: 3000; running: true; repeat: false }', sidebarPopupRect);
            cleanupTimer.triggered.connect(function() {
                Quickshell.execDetached(["sh", "-c", "pkill -9 -f 'gpu-screen-recorder.*portal' 2>/dev/null || true"]);
                cleanupTimer.destroy();
            });
            isRecording = false;
        }

        implicitWidth: 500 * Theme.uiScale
        implicitHeight: 700 * Theme.uiScale
        visible: parent.visible
        color: "transparent"
        anchors.top: parent.top
        anchors.right: parent.right
        // Clean up processes on destruction
        Component.onDestruction: {
            if (isRecording)
                stopRecording();

        }

        // Prevent closing when clicking in the panel bg
        MouseArea {
            anchors.fill: parent
        }

        NumberAnimation {
            id: slideAnim

            target: sidebarPopupRect
            property: "slideOffset"
            duration: 300
            easing.type: Easing.OutCubic
            onStopped: {
                if (sidebarPopupRect.slideOffset === sidebarPopupRect.width) {
                    sidebarPopup.visible = false;
                    if (weather)
                        weather.stopWeatherFetch();

                    if (systemWidget)
                        systemWidget.panelVisible = false;
                }
                sidebarPopupRect.isAnimating = false;
            }
            onStarted: {
                sidebarPopupRect.isAnimating = true;
            }
        }

        Rectangle {
            id: mainRectangle

            width: sidebarPopupRect.width - sidebarPopupRect.leftPadding
            height: sidebarPopupRect.height - sidebarPopupRect.bottomPadding
            anchors.top: sidebarPopupRect.top
            x: sidebarPopupRect.leftPadding + sidebarPopupRect.slideOffset
            y: 0
            color: Theme.backgroundPrimary
            bottomLeftRadius: 20 * Theme.uiScale
            z: 0

            Behavior on x {
                enabled: !sidebarPopupRect.isAnimating

                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }

            }

        }



        // SettingsIcon component
        SettingsIcon {
            id: settingsModal

            onWeatherRefreshRequested: {
                if (weather && weather.fetchCityWeather)
                    weather.fetchCityWeather();

            }
        }

        Item {
            anchors.fill: mainRectangle
            x: sidebarPopupRect.slideOffset
            Keys.onEscapePressed: sidebarPopupRect.hidePopup()

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20 * Theme.uiScale
                spacing: 4 * Theme.uiScale

                PowerMenu {
                    id: systemWidget
                    settingsModal: settingsModal

                    Layout.alignment: Qt.AlignHCenter
                    z: 3
                }

                Weather {
                    id: weather
                    Layout.alignment: Qt.AlignHCenter
                    z: 2
                }

                // Music and System Monitor row
                RowLayout {
                    spacing: 12 * Theme.uiScale
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter

                    Music {
                        z: 2
                    }

                    SystemMonitor {
                        id: systemMonitor
                        z: 2
                    }

                }

                // Power profile, Record and Wallpaper row
                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 10 * Theme.uiScale
                    Layout.preferredHeight: 80 * Theme.uiScale
                    z: 3

                    PowerProfile {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: 80 * Theme.uiScale
                    }

                    // Record and Wallpaper card
                    Rectangle {
                        Layout.preferredHeight: 80 * Theme.uiScale
                        Layout.preferredWidth: 140 * Theme.uiScale
                        Layout.fillWidth: false
                        color: Theme.surface
                        radius: 18 * Theme.uiScale

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 20 * Theme.uiScale

                            // Record button
                            Rectangle {
                                id: recordButton

                                width: 36 * Theme.uiScale
                                height: 36 * Theme.uiScale
                                radius: 18 * Theme.uiScale
                                border.color: Theme.accentPrimary
                                border.width: 1 * Theme.uiScale
                                color: sidebarPopupRect.isRecording ? Theme.accentPrimary : 
                                       (recordButtonArea.containsMouse ? Theme.accentPrimary : "transparent")

                                Text {
                                    anchors.centerIn: parent
                                    text: "photo_camera"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 22 * Theme.uiScale
                                    color: sidebarPopupRect.isRecording || recordButtonArea.containsMouse ? Theme.backgroundPrimary : Theme.accentPrimary
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                MouseArea {
                                    id: recordButtonArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (sidebarPopupRect.isRecording) {
                                            sidebarPopupRect.stopRecording();
                                            sidebarPopup.dismiss();
                                        } else {
                                            sidebarPopupRect.startRecording();
                                            sidebarPopup.dismiss();
                                        }
                                    }
                                }

                                StyledTooltip {
                                    text: sidebarPopupRect.isRecording ? "Stop Recording" : "Start Recording"
                                    targetItem: recordButtonArea
                                    tooltipVisible: recordButtonArea.containsMouse
                                }

                            }

                            // Wallpaper button
                            Rectangle {
                                id: wallpaperButton

                                width: 36 * Theme.uiScale
                                height: 36 * Theme.uiScale
                                radius: 18 * Theme.uiScale
                                border.color: Theme.accentPrimary
                                border.width: 1 * Theme.uiScale
                                color: wallpaperButtonArea.containsMouse ? Theme.accentPrimary : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "image"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 22 * Theme.uiScale
                                    color: wallpaperButtonArea.containsMouse ? Theme.backgroundPrimary : Theme.accentPrimary
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                MouseArea {
                                    id: wallpaperButtonArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (typeof settingsModal !== 'undefined' && settingsModal && settingsModal.openSettings) {
                                            settingsModal.openSettings(6);
                                            sidebarPopup.dismiss();
                                        }
                                    }
                                }

                                StyledTooltip {
                                    text: "Wallpaper"
                                    targetItem: wallpaperButtonArea
                                    tooltipVisible: wallpaperButtonArea.containsMouse
                                }

                            }

                        }

                    }

                }



            }

            Behavior on x {
                enabled: !sidebarPopupRect.isAnimating

                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }

            }

        }

        Loader {
            active: Settings.settings.showCorners
            anchors.fill: parent

            sourceComponent: Item {
                Corners {
                    id: sidebarCornerLeft

                    position: "bottomright"
                    size: 1.1
                    fillColor: Theme.backgroundPrimary
                    anchors.top: parent.top
                    offsetX: -464 + sidebarPopupRect.slideOffset
                    offsetY: 0

                    Behavior on offsetX {
                        enabled: !sidebarPopupRect.isAnimating

                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutCubic
                        }

                    }

                }

                Corners {
                    id: sidebarCornerBottom

                    position: "bottomright"
                    size: 1.1
                    fillColor: Theme.backgroundPrimary
                    anchors.bottom: sidebarPopupRect.bottom
                    offsetX: 33 + sidebarPopupRect.slideOffset
                    offsetY: 46

                    Behavior on offsetX {
                        enabled: !sidebarPopupRect.isAnimating

                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutCubic
                        }

                    }

                }

            }

        }

    }

}
