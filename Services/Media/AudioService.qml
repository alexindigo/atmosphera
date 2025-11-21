pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons

Singleton {
  id: root

  // Devices

  readonly property PwNode sink: Pipewire.defaultAudioSink
  readonly property PwNode source: validatedSource
  readonly property bool hasInput: !!source

  readonly property list<PwNode> sinks: deviceNodes.sinks
  readonly property list<PwNode> sources: deviceNodes.sources

  // Output Volume

  readonly property real volume: volumeValue
  readonly property bool muted: mutedValue

  // Input Volume

  readonly property real inputVolume: inputVolumeValue
  readonly property bool inputMuted: inputMutedValue

  readonly property real stepVolume: Settings.data.audio.volumeStep / 100.0

  // Filtered device nodes (non-stream sinks and sources)
  readonly property var deviceNodes: Pipewire.nodes.values.reduce((acc, node) => {
                                                                    if (!node.isStream) {
                                                                      if (node.isSink) {
                                                                        acc.sinks.push(node);
                                                                      } else if (node.audio) {
                                                                        acc.sources.push(node);
                                                                      }
                                                                    }
                                                                    return acc;
                                                                  }, {
                                                                    "sources": [],
                                                                    "sinks": []
                                                                  })

  // Validated source (ensures it's a proper audio source, not a sink)
  readonly property PwNode validatedSource: {
    const raw = Pipewire.defaultAudioSource;
    if (!raw || raw.isSink)
    return null;
    if (raw.mediaClass && !raw.mediaClass.startsWith("Audio/Source"))
    return null;
    return raw;
  }

  // Internal state
  property real volumeValue: 0
  property bool mutedValue: true
  property real inputVolumeValue: 0
  property bool inputMutedValue: true
  property bool isClampingOutput: false
  property bool isClampingInput: false

  // Initialization

  Component.onCompleted: {
    updateOutputVolume();
    updateInputVolume();
  }

  // Watchers

  onSinkChanged: updateOutputVolume()
  onSourceChanged: updateInputVolume()

  // Bind all devices to ensure their properties are available
  PwObjectTracker {
    objects: [...root.sinks, ...root.sources]
  }

  // Watch output device changes
  Connections {
    target: sink?.audio ?? null

    function onVolumeChanged() {
      const vol = sink?.audio?.volume ?? 0;
      if (isNaN(vol))
        return;

      // Clamp volume if it exceeds max when volumeOverdrive is disabled
      if (!root.isClampingOutput) {
        const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
        if (vol > maxVolume) {
          root.isClampingOutput = true;
          Qt.callLater(() => {
                         if (root.sink?.audio) {
                           root.sink.audio.volume = maxVolume;
                         }
                         root.isClampingOutput = false;
                       });
          return;
        }
      }

      if (Math.abs(root.volumeValue - vol) > 0.001) {
        root.volumeValue = vol;
      }
    }

    function onMutedChanged() {
      const newMuted = sink?.audio?.muted ?? true;
      if (root.mutedValue !== newMuted) {
        root.mutedValue = newMuted;
      }
    }
  }

  // Watch input device changes
  Connections {
    target: source?.audio ?? null

    function onVolumeChanged() {
      const vol = source?.audio?.volume;
      if (vol === undefined || isNaN(vol))
        return;

      // Clamp volume if it exceeds max when volumeOverdrive is disabled
      if (!root.isClampingInput) {
        const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
        if (vol > maxVolume) {
          root.isClampingInput = true;
          Qt.callLater(() => {
                         if (root.source?.audio) {
                           root.source.audio.volume = maxVolume;
                         }
                         root.isClampingInput = false;
                       });
          return;
        }
      }

      if (Math.abs(root.inputVolumeValue - vol) > 0.001) {
        root.inputVolumeValue = vol;
      }
    }

    function onMutedChanged() {
      const newMuted = source?.audio?.muted ?? true;
      if (root.inputMutedValue !== newMuted) {
        root.inputMutedValue = newMuted;
      }
    }
  }

  // Watch for default device changes
  Connections {
    target: Pipewire

    function onDefaultAudioSourceChanged() {
      updateInputVolume();
    }
  }

  // Output Control

  function increaseVolume() {
    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    if (volume >= maxVolume) {
      return;
    }
    setVolume(volume + stepVolume);
  }

  function decreaseVolume() {
    setVolume(volume - stepVolume);
  }

  function setVolume(newVolume: real) {
    if (!sink?.audio) {
      Logger.w("AudioService", "No sink available");
      return;
    }

    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    sink.audio.muted = false;
    sink.audio.volume = Math.max(0, Math.min(maxVolume, newVolume));
  }

  function setOutputMuted(muted: bool) {
    if (!sink?.audio) {
      Logger.w("AudioService", "No sink available");
      return;
    }

    sink.audio.muted = muted;
  }

  function getOutputIcon() {
    if (muted)
      return "volume-mute";
    if (volume <= Number.EPSILON)
      return "volume-zero";
    if (volume <= 0.5)
      return "volume-low";
    return "volume-high";
  }

  // Input Control

  function increaseInputVolume() {
    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    if (inputVolume >= maxVolume) {
      return;
    }
    setInputVolume(inputVolume + stepVolume);
  }

  function decreaseInputVolume() {
    setInputVolume(inputVolume - stepVolume);
  }

  function setInputVolume(newVolume: real) {
    if (!source?.audio) {
      Logger.w("AudioService", "No source available");
      return;
    }

    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    source.audio.muted = false;
    source.audio.volume = Math.max(0, Math.min(maxVolume, newVolume));
  }

  function setInputMuted(muted: bool) {
    if (!source?.audio) {
      Logger.w("AudioService", "No source available");
      return;
    }

    source.audio.muted = muted;
  }

  function getInputIcon() {
    if (inputMuted || inputVolume <= Number.EPSILON) {
      return "microphone-mute";
    }
    return "microphone";
  }

  // Device Selection

  function setAudioSink(newSink: PwNode): void {
    Pipewire.preferredDefaultAudioSink = newSink;
    // Values will update via onSinkChanged -> updateOutputVolume()
  }

  function setAudioSource(newSource: PwNode): void {
    Pipewire.preferredDefaultAudioSource = newSource;
    // Values will update via onSourceChanged -> updateInputVolume()
  }

  // Internal

  function updateOutputVolume() {
    if (sink?.audio) {
      const vol = sink.audio.volume;
      if (vol !== undefined && !isNaN(vol)) {
        volumeValue = vol;
      }
      mutedValue = !!sink.audio.muted;
    } else {
      mutedValue = true;
    }
  }

  function updateInputVolume() {
    if (source?.audio) {
      const vol = source.audio.volume;
      if (vol !== undefined && !isNaN(vol)) {
        inputVolumeValue = vol;
      }
      // Preserve last known volume if undefined/NaN
      inputMutedValue = !!source.audio.muted;
    } else {
      // Only reset muted state when no source
      inputMutedValue = true;
    }
  }
}
