import QtQuick
import Quickshell
import qs.Settings
import qs.Components

Item {
    id: volumeDisplay
    property var shell
    property int volume: 0

    // The total width will match the pill's width
    width: pillIndicator.width
    height: pillIndicator.height

    PillIndicator {
        id: pillIndicator
        icon: volume === 0 ? "volume_off" : (volume < 30 ? "volume_down" : "volume_up")
        text: volume + "%"

        pillColor: Theme.surfaceVariant
        iconCircleColor: Theme.accentPrimary
        iconTextColor: Theme.backgroundPrimary
        textColor: Theme.textPrimary
    }

    Connections {
        target: shell && shell.defaultAudioSink && shell.defaultAudioSink.audio ? shell.defaultAudioSink.audio : null
        onVolumeChanged: {
            volume = Math.round(shell.defaultAudioSink.audio.volume * 100);
            pillIndicator.text = volume + "%";
            pillIndicator.icon = volume === 0 ? "volume_off" : (volume < 30 ? "volume_down" : "volume_up");
            pillIndicator.show();
        }
    }

    Component.onCompleted: {
        if (shell && shell.volume !== undefined) {
            volume = shell.volume
            pillIndicator.show()
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton // Accept wheel events only
        propagateComposedEvents: true
        onWheel: {
            if (!shell || !shell.defaultAudioSink || !shell.defaultAudioSink.audio) return;
            let step = 0.05; // 5% as float
            let newVolume = shell.defaultAudioSink.audio.volume;
            if (wheel.angleDelta.y > 0) {
                newVolume = Math.min(1, newVolume + step);
            } else if (wheel.angleDelta.y < 0) {
                newVolume = Math.max(0, newVolume - step);
            }
            shell.defaultAudioSink.audio.volume = newVolume;
        }
    }
}
