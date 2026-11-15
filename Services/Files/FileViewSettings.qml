import QtQuick
import Quickshell

// Request-local presentation preferences. Persistence belongs to request success.
Scope {
  id: root
  property string mode: "grid"
  property var zooms: ({
                         grid: 3,
                         compact: 1,
                         list: 1
                       })
  property bool thumbnails: true
  property var columnShares: [.55, .16, .29]
  readonly property var columnMinima: [80, 64, 120]
  property real dialogWidth: 1100
  property real dialogHeight: 740
  readonly property int zoom: zooms[mode] === undefined ? 3 : zooms[mode]
  readonly property int iconSize: (mode === "grid" ? [48, 64, 80, 96, 112, 128, 160] : [16, 20, 24, 32, 40, 48, 64])[zoom]
  property real _wheel: 0
  property bool _pixelWheel: false
  onModeChanged: _wheel = 0

  function bounded(value, fallback, low, high) {
    return typeof value === "number" && isFinite(value) ? Math.max(low, Math.min(high, value)) : fallback;
  }
  function restore(prefs) {
    prefs = prefs || {};
    mode = ["grid", "compact", "list"].includes(prefs.mode) ? prefs.mode : "grid";
    var stored = prefs.zooms || {};
    zooms = {
      grid: Math.round(bounded(stored.grid, 3, 0, 6)),
      compact: Math.round(bounded(stored.compact, 1, 0, 6)),
      list: Math.round(bounded(stored.list, 1, 0, 6))
    };
    thumbnails = prefs.thumbnails !== false;
    // JsonAdapter reloads JSON arrays as native QML sequences, not JS Arrays.
    // Normalize at the persistence boundary before validating or deriving widths.
    var shares = prefs.columns && prefs.columns.length === 3 ? Array.from(prefs.columns) : [];
    if (shares.length === 3 && shares.every(n => typeof n === "number" && isFinite(n) && n >= 0) && shares.reduce((a, b) => a + b, 0) > 0) {
      var total = shares.reduce((a, b) => a + b, 0);
      columnShares = shares.map(n => n / total);
    } else
      columnShares = [.55, .16, .29];
    setDialogSize(prefs.width, prefs.height);
  }
  function setZoom(value) {
    var next = Object.assign({}, zooms);
    next[mode] = Math.round(bounded(value, zoom, 0, 6));
    zooms = next;
  }
  function zoomBy(delta) {
    setZoom(zoom + delta);
  }
  function wheelZoom(delta, pixels) {
    if (_pixelWheel !== pixels)
      _wheel = 0;
    _pixelWheel = pixels;
    _wheel += delta;
    var unit = pixels ? 40 : 120;
    var steps = Math.trunc(_wheel / unit);
    if (steps) {
      zoomBy(steps);
      _wheel -= steps * unit;
    }
  }
  function widths(available) {
    var extra = Math.max(0, available - columnMinima.reduce((a, b) => a + b, 0));
    return columnMinima.map((minimum, i) => minimum + extra * columnShares[i]);
  }
  function resizeColumn(boundary, delta, available) {
    if (![0, 1].includes(boundary))
      return;
    var current = widths(available), extra = available - columnMinima.reduce((a, b) => a + b, 0);
    if (extra <= 0)
      return;
    delta = Math.max(columnMinima[boundary] - current[boundary], Math.min(current[boundary + 1] - columnMinima[boundary + 1], delta));
    current[boundary] += delta;
    current[boundary + 1] -= delta;
    columnShares = current.map((width, i) => Math.max(0, width - columnMinima[i]) / extra);
  }
  function setDialogSize(width, height) {
    // The view owns its actual layout minimum and output bounds. Preferences
    // retain the chosen logical size without imposing a separate screen limit.
    dialogWidth = typeof width === "number" && isFinite(width) && width > 0 ? width : 1100;
    dialogHeight = typeof height === "number" && isFinite(height) && height > 0 ? height : 740;
  }
  function snapshot() {
    return {
      mode: mode,
      zooms: Object.assign({}, zooms),
      thumbnails: thumbnails,
      columns: columnShares.slice(),
      width: dialogWidth,
      height: dialogHeight
    };
  }
}
