pragma Singleton
import QtMultimedia

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  // Map to track active sound players: resolvedPath -> MediaPlayer instance
  property var activePlayers: ({})

  // Container for dynamically created players
  Item {
    id: playersContainer
  }

  // Component for creating MediaPlayer instances
  Component {
    id: playerComponent
    MediaPlayer {
      id: mediaPlayer
      property string resolvedPath: ""
      property bool shouldFallback: false
      property real soundVolume: 1.0

      audioOutput: AudioOutput {
        volume: soundVolume
      }

      onErrorOccurred: {
        Logger.w("SoundService", "Error playing sound:", source, error, errorString);
        if (shouldFallback) {
          const fallbackPath = Quickshell.shellDir + "/Assets/Sounds/notification.mp3";
          if (fallbackPath !== resolvedPath) {
            root.playSound(fallbackPath, {
                             volume: soundVolume,
                             fallback: false,
                             repeat: false
                           });
          }
        }
        // Clean up on error
        if (root.activePlayers[resolvedPath]) {
          delete root.activePlayers[resolvedPath];
        }
        destroy();
      }

      onPlaybackStateChanged: function (state) {
        if (state === MediaPlayer.StoppedState && loops === 1) {
          // Clean up non-looping players when they finish
          if (root.activePlayers[resolvedPath]) {
            delete root.activePlayers[resolvedPath];
          }
          destroy();
        }
      }

      Component.onCompleted: {
        play();
      }
    }
  }

  Component.onCompleted: {
    Logger.i("SoundService", "Service started");
  }

  /**
  * Resolve sound path to absolute file path
  * @param soundPath - Path to the sound file (absolute, relative to shellDir, or just filename for Assets/Sounds/)
  * @returns Resolved absolute path
  */
  function resolvePath(soundPath) {
    if (!soundPath || soundPath === "") {
      return "";
    }

    let resolvedPath = soundPath;

    // If it's just a filename (no path separators), assume it's in Assets/Sounds/
    if (!soundPath.includes("/") && !soundPath.startsWith("file://")) {
      resolvedPath = Quickshell.shellDir + "/Assets/Sounds/" + soundPath;
    } else if (!soundPath.startsWith("/") && !soundPath.startsWith("file://")) {
      // Relative path - assume it's relative to shellDir
      resolvedPath = Quickshell.shellDir + "/" + soundPath;
    } else if (soundPath.startsWith("file://")) {
      resolvedPath = soundPath.substring(7); // Remove "file://" prefix
    }
    // Absolute paths are used as-is

    return resolvedPath;
  }

  /**
  * Play a sound file
  * @param soundPath - Path to the sound file (absolute, relative to shellDir, or just filename for Assets/Sounds/)
  * @param options - Optional object with:
  *   - volume: Volume level (0.0 to 1.0, default: 1.0)
  *   - fallback: Whether to fallback to default notification sound if file not found (default: false)
  *   - repeat: Whether to repeat/loop the sound continuously (default: false)
  */
  function playSound(soundPath, options) {
    if (!soundPath || soundPath === "") {
      Logger.w("SoundService", "No sound path provided");
      return;
    }

    const opts = options || {};
    const volume = opts.volume !== undefined ? opts.volume : 1.0;
    const fallback = opts.fallback !== undefined ? opts.fallback : false;
    const repeat = opts.repeat !== undefined ? opts.repeat : false;

    // Resolve path
    const resolvedPath = resolvePath(soundPath);

    // Stop any existing player for this path if it's looping
    if (repeat && activePlayers[resolvedPath]) {
      stopSound(soundPath);
    }

    // Create MediaPlayer instance
    const player = playerComponent.createObject(playersContainer, {
                                                  resolvedPath: resolvedPath,
                                                  source: "file://" + resolvedPath,
                                                  loops: repeat ? MediaPlayer.Infinite : 1,
                                                  soundVolume: Math.max(0, Math.min(1, volume)),
                                                  shouldFallback: fallback && !repeat
                                                });

    if (!player) {
      Logger.w("SoundService", "Failed to create MediaPlayer for:", resolvedPath);
      // Try fallback if requested
      if (fallback && !repeat) {
        const defaultSound = Quickshell.shellDir + "/Assets/Sounds/notification.mp3";
        if (defaultSound !== resolvedPath) {
          playSound(defaultSound, {
                      volume: volume,
                      fallback: false,
                      repeat: false
                    });
        }
      }
      return;
    }

    // Store player in activePlayers map
    activePlayers[resolvedPath] = player;

    Logger.d("SoundService", "Playing sound:", resolvedPath, `(volume: ${Math.round(volume * 100)}%)`, repeat ? "(repeat)" : "");
  }

  /**
  * Stop a playing sound
  * @param soundPath - Path to the sound file to stop (optional, if not provided stops all repeating sounds)
  */
  function stopSound(soundPath) {
    if (soundPath) {
      // Resolve path the same way as playSound
      const resolvedPath = resolvePath(soundPath);

      // Stop and remove the player for this specific sound
      if (activePlayers[resolvedPath]) {
        const player = activePlayers[resolvedPath];
        player.stop();
        delete activePlayers[resolvedPath];
        player.destroy();
        Logger.d("SoundService", "Stopped sound:", resolvedPath);
      }
    } else {
      // Stop all active players (typically used for repeating sounds)
      const paths = Object.keys(activePlayers);
      for (let i = 0; i < paths.length; i++) {
        const path = paths[i];
        const player = activePlayers[path];
        player.stop();
        player.destroy();
      }
      activePlayers = {};
      Logger.d("SoundService", "Stopped all sounds");
    }
  }
}
