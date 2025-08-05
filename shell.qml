import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import QtQuick
import QtCore
import qs.Bar
import qs.Bar.Modules
import qs.Widgets
import qs.Widgets.LockScreen
import qs.Widgets.Notification
import qs.Settings
import qs.Helpers

import "./Helpers/IdleInhibitor.qml"
import "./Helpers/IPCHandlers.qml"

Scope {
    id: root

    property alias appLauncherPanel: appLauncherPanel
    property var notificationHistoryWin: notificationHistoryWin
    property bool pendingReload: false

    // Round volume to nearest 5% increment for consistent control
    function roundToStep(value, step) {
        return Math.round(value / step) * step;
    }

    // Current audio volume (0-100), synced with system
    property int volume: (defaultAudioSink && defaultAudioSink.audio && !defaultAudioSink.audio.muted)
                        ? Math.round(defaultAudioSink.audio.volume * 100)
                        : 0

    // Update volume with 5-step increments and apply to audio sink
    function updateVolume(vol) {
        var clamped = Math.max(0, Math.min(100, vol));
        var stepped = roundToStep(clamped, 5);
        if (defaultAudioSink && defaultAudioSink.audio) {
            defaultAudioSink.audio.volume = stepped / 100;
        }
        volume = stepped;
    }

    Component.onCompleted: {
        Quickshell.shell = root;
    }

    Bar {
        id: bar
        shell: root
        property var notificationHistoryWin: notificationHistoryWin
    }

    // Create dock for each monitor (respects dockMonitors setting)
    Variants {
        model: Quickshell.screens

        Dock {
            property var modelData
        }
    }

    Applauncher {
        id: appLauncherPanel
        visible: false
    }

    LockScreen {
        id: lockScreen
        onLockedChanged: {
            if (!locked && root.pendingReload) {
                reloadTimer.restart();
                root.pendingReload = false;
            }
        }
    }

    IdleInhibitor {
        id: idleInhibitor
    }

    NotificationServer {
        id: notificationServer
        onNotification: function (notification) {
            console.log("Notification received:", notification.appName);
            notification.tracked = true;
            
            // Distribute notification to all visible notification popups
            for (let i = 0; i < notificationPopupVariants.count; i++) {
                let popup = notificationPopupVariants.objectAt(i);
                if (popup && popup.notificationsVisible) {
                    popup.addNotification(notification);
                }
            }
            
            if (notificationHistoryWin) {
                notificationHistoryWin.addToHistory({
                    id: notification.id,
                    appName: notification.appName || "Notification",
                    summary: notification.summary || "",
                    body: notification.body || "",
                    urgency: notification.urgency,
                    timestamp: Date.now()
                });
            }
        }
    }

    // Create notification popups for each selected monitor
    Variants {
        id: notificationPopupVariants
        model: Quickshell.screens

        NotificationPopup {
            property var modelData
            barVisible: bar.visible
            screen: modelData
            visible: notificationsVisible && notificationModel.count > 0 && 
                    (Settings.settings.notificationMonitors.includes(modelData.name) ||
                     (Settings.settings.notificationMonitors.length === 0)) // Show on all if none selected
        }
    }

    NotificationHistory {
        id: notificationHistoryWin
    }

    // Reference to the default audio sink from Pipewire
    property var defaultAudioSink: Pipewire.defaultAudioSink

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    IPCHandlers {
        appLauncherPanel: appLauncherPanel
        lockScreen: lockScreen
        idleInhibitor: idleInhibitor
        notificationPopupVariants: notificationPopupVariants
    }

    Connections {
        function onReloadCompleted() {
            Quickshell.inhibitReloadPopup();
        }

        function onReloadFailed() {
            Quickshell.inhibitReloadPopup();
        }

        target: Quickshell
    }

    Timer {
        id: reloadTimer
        interval: 500
        repeat: false
        onTriggered: Quickshell.reload(true)
    }

    // Handle screen configuration changes (delay reload if locked)
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (lockScreen.locked) {
                pendingReload = true;
            } else {
                reloadTimer.restart();
            }
        }
    }

    Connections {
        target: defaultAudioSink ? defaultAudioSink.audio : null
        function onVolumeChanged() {
            if (defaultAudioSink.audio && !defaultAudioSink.audio.muted) {
                volume = Math.round(defaultAudioSink.audio.volume * 100);
                console.log("Volume changed externally to:", volume);
            }
        }
        function onMutedChanged() {
            if (defaultAudioSink.audio) {
                if (defaultAudioSink.audio.muted) {
                    volume = 0;
                    console.log("Audio muted, volume set to 0");
                } else {
                    volume = Math.round(defaultAudioSink.audio.volume * 100);
                    console.log("Audio unmuted, volume restored to:", volume);
                }
            }
        }
    }
}
