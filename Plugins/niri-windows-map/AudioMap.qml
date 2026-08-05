import QtQuick
import Quickshell.Services.Pipewire
import qs.Services.Compositor
import qs.Services.Media

// AudioMap — per-window "is producing sound" attribution for the niri
// windows map. Pure QML over the live PipeWire graph; no helper process.
//
// Attribution ladder:
//   1. stream's application.process.id == window pid (Firefox, most apps)
//   2. stream's application.icon-name == window appId (Chromium-family:
//      audio runs in a child utility process, pid never matches a window)
//   3. multi-window app: MPRIS currently-playing title ⊆ window title
//      (only paired while MPRIS is Playing — paused titles are stale)
//   4. no confident match: NO badge (deliberate — an all-app badge would
//      cry wolf)
//
// Sticky cache: pairs (streamId -> winId) created when attribution is
// confident are REMEMBERED. When a second tab starts sounding, the new
// stream is by elimination the unpaired one and gets paired to the newly
// MPRIS-matched window — both windows keep badges, and each mute button
// controls its own cached stream. Pairs die when the stream corks/dies
// or the window closes.
Item {
  id: root

  property bool active: true

  // winId -> {node: PwNode, muted: bool} for windows confidently
  // attributed to a live output stream
  property var audioInfo: ({})

  // sticky associations: stream node id -> winId
  property var _pairs: ({})

  function _normTitle(t) {
    return String(t || "").toLowerCase().replace(/^\(\d+\)\s*/, "").trim();
  }

  function _windows() {
    const backend = CompositorService.niriBackend;
    return backend ? (backend.windows || []) : [];
  }

  function _liveStreams() {
    if (!Pipewire.ready)
      return [];
    return Pipewire.nodes.values.filter(n => n && n.isStream && (n.properties && n.properties["media.class"] === "Stream/Output/Audio") && n.properties["pulse.corked"] !== "true");
  }

  function _streamAppId(node) {
    // icon-name is the desktop-id — matches niri app_id for Chromium-family
    const props = node.properties || {};
    return props["application.icon-name"] || "";
  }

  function _streamPid(node) {
    const props = node.properties || {};
    return parseInt(props["application.process.id"] || "0", 10) || 0;
  }

  function _update() {
    if (!root.active) {
      if (Object.keys(root.audioInfo).length > 0)
        root.audioInfo = ({});
      root._pairs = ({});
      return;
    }

    const streams = root._liveStreams();
    const wins = root._windows();
    const streamIds = {};
    const winIds = {};
    for (const s of streams)
      streamIds[s.id] = true;
    for (const w of wins)
      winIds[w.id] = true;

    // 1. drop dead pairs (stream corked/gone, or window closed)
    const pairs = {};
    for (const sid in root._pairs) {
      if (streamIds[sid] && winIds[root._pairs[sid]])
        pairs[sid] = root._pairs[sid];
    }

    const pairedWins = {};
    for (const sid in pairs)
      pairedWins[pairs[sid]] = true;

    // 2. pair new streams when attribution is confident
    for (const s of streams) {
      if (pairs[s.id] !== undefined)
        continue;

      // candidate windows: exact pid match, else icon-name == appId
      const spid = root._streamPid(s);
      const sapp = root._streamAppId(s);
      let cands = wins.filter(w => (spid !== 0 && w.pid === spid) || (sapp !== "" && w.appId === sapp));
      if (cands.length === 0)
        continue;  // stream from an app with no windows here

      if (cands.length === 1) {
        pairs[s.id] = cands[0].id;
        pairedWins[cands[0].id] = true;
        continue;
      }

      // multi-window app: only a Playing MPRIS title can arbitrate, and
      // only onto a window that isn't already paired
      if (MediaService.isPlaying && MediaService.trackTitle) {
        const track = root._normTitle(MediaService.trackTitle);
        if (track.length >= 4) {
          const m = cands.filter(w => !pairedWins[w.id] && root._normTitle(w.title).indexOf(track) !== -1);
          if (m.length === 1) {
            pairs[s.id] = m[0].id;
            pairedWins[m[0].id] = true;
          }
        }
      }
      // else: leave unattributed — no badge (deliberate)
    }

    // 3. project pairs into winId -> {node, muted}
    const byId = {};
    for (const s of streams)
      byId[s.id] = s;
    const info = {};
    for (const sid in pairs) {
      const node = byId[sid];
      if (!node)
        continue;
      info[pairs[sid]] = {
        "node": node,
        "muted": node.audio ? node.audio.muted : false
      };
    }

    root._pairs = pairs;
    root.audioInfo = info;
  }

  // Toggle mute on the stream attributed to a window. Returns the new
  // muted state (or null if the window has no attributed stream).
  function toggleMute(winId) {
    const entry = root.audioInfo[winId];
    if (!entry || !entry.node || !entry.node.audio)
      return null;
    entry.node.audio.muted = !entry.node.audio.muted;
    _update();
    return entry.node.audio.muted;
  }

  onActiveChanged: _update()

  Timer {
    interval: 1500
    repeat: true
    running: root.active
    onTriggered: root._update()
  }

  Component.onCompleted: _update()
}
