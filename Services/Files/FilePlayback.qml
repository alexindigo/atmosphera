import QtQuick
import QtMultimedia
import Quickshell

// One transport for both media kinds. Views attach an output and send intents;
// no view owns a player, a playback flag, a position or a volume copy.
Scope {
  id: root
  property url source
  property bool active: false
  property bool looping: false
  property var videoOutput: null
  property real _volume: 0.75
  readonly property var player: engine.item
  readonly property bool playing: !!player && player.playbackState === MediaPlayer.PlayingState
  readonly property real position: player ? player.position : 0
  readonly property real duration: player ? player.duration : 0
  readonly property bool seekable: !!player && player.seekable && duration > 0
  readonly property real volume: player ? player.audioOutput.volume : _volume
  readonly property string status: !active ? "idle" : !player ? "loading" : player.error !== MediaPlayer.NoError ? "error" : player.hasAudio || player.hasVideo ? "ready" : "loading"
  readonly property string title: player ? player.metaData.stringValue(MediaMetaData.Title) : ""
  readonly property string artist: player ? (player.metaData.stringValue(MediaMetaData.ContributingArtist) || player.metaData.stringValue(MediaMetaData.AlbumArtist)) : ""
  readonly property string album: player ? player.metaData.stringValue(MediaMetaData.AlbumTitle) : ""
  readonly property var snapshot: ({playing: playing, position: position, duration: duration, seekable: seekable, volume: volume, status: status, title: title, artist: artist, album: album, engineActive: !!player})

  function toggle() {
    if (!player || status === "error") return;
    if (playing) player.pause();
    else {
      if (duration > 0 && position >= duration) player.setPosition(0);
      player.play();
    }
  }
  function seek(milliseconds) {
    if (seekable && Number.isFinite(milliseconds)) player.setPosition(Math.round(Math.max(0, Math.min(duration, milliseconds))));
  }
  function seekBy(milliseconds) { seek(position + milliseconds); }
  function setVolume(value) {
    if (Number.isFinite(value)) _volume = Math.max(0, Math.min(1, value));
  }
  function volumeBy(amount) { setVolume(volume + amount); }
  function time(milliseconds) {
    var seconds = Math.floor(Math.max(0, milliseconds) / 1000);
    var hours = Math.floor(seconds / 3600);
    var minutes = Math.floor(seconds / 60) % 60;
    return (hours ? hours + ":" + String(minutes).padStart(2, "0") : String(minutes)) + ":" + String(seconds % 60).padStart(2, "0");
  }
  // Only the scalar volume survives close. Native decoders, audio devices and
  // video resources are owned by this preview lifetime, not an idle chooser.
  Loader {
    id: engine
    active: root.active && String(root.source) !== ""
    sourceComponent: MediaPlayer {
      source: root.source
      loops: root.looping ? MediaPlayer.Infinite : MediaPlayer.Once
      audioOutput: AudioOutput { volume: root._volume }
      videoOutput: root.videoOutput
      autoPlay: true
      onSourceChanged: if (String(source) !== "") play()
    }
  }
}
