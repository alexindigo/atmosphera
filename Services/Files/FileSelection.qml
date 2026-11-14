import QtQuick
import Quickshell

Scope {
  id: root
  required property FileBrowser browser
  property string selectable: "files"
  property bool multiple: false
  readonly property var selectedPaths: _selectedPaths
  property int cursor: -1
  readonly property int anchor: _anchor
  property var _selectedPaths: []
  property int _anchor: -1
  property string _cursorPath: ""
  property string _anchorPath: ""
  property string _prefix: ""
  property double _typedAt: 0
  property var _band: null
  signal chosen(string path)
  function _setPaths(paths) {
    if (paths.length === _selectedPaths.length && paths.every((path, index) => path === _selectedPaths[index]))
      return;
    _selectedPaths = paths;
  }

  function _selectable(entry) {
    return entry && entry.directory === (selectable === "folders");
  }

  function clear() {
    _band = null;
    _setPaths([]);
    cursor = -1;
    _anchor = -1;
    _cursorPath = "";
    _anchorPath = "";
    _prefix = "";
  }

  function snapshot() { return {paths: selectedPaths.slice(), cursor: _cursorPath, anchor: _anchorPath}; }
  function restore(state) {
    if (!state) return;
    _setPaths(state.paths || []);
    _cursorPath = state.cursor || "";
    _anchorPath = state.anchor || "";
    _revalidate();
  }

  function click(index, modifiers) {
    var item = browser.entry(index);
    if (!item)
      return;
    cursor = index;
    _cursorPath = item.path;
    if (multiple && (modifiers & Qt.ShiftModifier) && _anchor >= 0) {
      var paths = [];
      for (var i = Math.min(_anchor, index); i <= Math.max(_anchor, index); i++) {
        var entry = browser.entry(i);
        if (_selectable(entry))
          paths.push(entry.path);
      }
      _setPaths(paths);
    } else {
      _anchor = index;
      _anchorPath = item.path;
      if (!_selectable(item)) {
        if (!(multiple && (modifiers & Qt.ControlModifier)))
          _setPaths([]);
      } else if (modifiers & Qt.ControlModifier) {
        _setPaths(_selectedPaths.includes(item.path) ? _selectedPaths.filter(p => p !== item.path) : multiple ? _selectedPaths.concat([item.path]) : [item.path]);
      } else
        _setPaths([item.path]);
    }
    chosen(item.path);
  }

  function moveTo(index, extend, focusOnly) {
    if (!browser.count)
      return;
    index = Math.max(0, Math.min(browser.count - 1, index));
    if (focusOnly) {
      cursor = index;
      _cursorPath = browser.entry(index).path;
    } else click(index, extend ? Qt.ShiftModifier : Qt.NoModifier);
  }
  function move(delta, extend, focusOnly) {
    moveTo(cursor < 0 ? (delta < 0 ? browser.count - 1 : 0) : cursor + delta, extend, focusOnly);
  }
  function toggleCurrent() {
    if (cursor >= 0)
      click(cursor, Qt.ControlModifier);
  }
  function background(modifiers) {
    if (!(modifiers & (Qt.ControlModifier | Qt.ShiftModifier)))
      clear();
  }
  function beginBand(modifiers, startIndex) {
    _band = multiple ? {base: _selectedPaths.slice(), modifiers: modifiers, anchor: startIndex, indices: []} : null;
  }
  function updateBand(indices) {
    if (!_band || !multiple)
      return;
    var paths = indices.map(i => browser.entry(i)).filter(item => _selectable(item)).map(item => item.path);
    _band.indices = indices;
    if (_band.modifiers & Qt.ShiftModifier)
      paths = _band.base.concat(paths.filter(path => !_band.base.includes(path)));
    else if (_band.modifiers & Qt.ControlModifier)
      paths = _band.base.filter(path => !paths.includes(path)).concat(paths.filter(path => !_band.base.includes(path)));
    _setPaths(paths);
  }
  function endBand(index) {
    if (!_band)
      return;
    var indices = _band.indices;
    if (indices.length) {
      cursor = index >= 0 ? index : indices[indices.length - 1];
      _anchor = _band.anchor >= 0 ? _band.anchor : indices[0];
      var entry = browser.entry(_anchor);
      _anchorPath = entry ? entry.path : "";
    }
    _band = null;
  }

  function selectAll() {
    if (!multiple)
      return;
    var paths = [];
    for (var i = 0; i < browser.count; i++) {
      var item = browser.entry(i);
      if (_selectable(item))
        paths.push(item.path);
    }
    _setPaths(paths);
  }

  function typeAhead(text) {
    var now = Date.now();
    var prefix = now - _typedAt > 1000 ? text : _prefix + text;
    _typedAt = now;
    _prefix = prefix.toLowerCase();
    for (var offset = 1; offset <= browser.count; offset++) {
      var index = (Math.max(-1, cursor) + offset) % browser.count;
      if (browser.entry(index).name.toLowerCase().startsWith(_prefix)) {
        click(index, Qt.NoModifier);
        return;
      }
    }
  }

  function _revalidate() {
    if (!browser || browser.status === "loading")
      return;
    _band = null;
    var paths = _selectedPaths.filter(function(path) {
      var index = browser.indexOfPath(path);
      return index >= 0 && root._selectable(browser.entry(index));
    });
    if (!multiple && paths.length > 1)
      paths = paths.slice(0, 1);
    _setPaths(paths);
    cursor = browser.indexOfPath(_cursorPath);
    _anchor = browser.indexOfPath(_anchorPath);
  }

  onSelectableChanged: _revalidate()
  onMultipleChanged: _revalidate()
  onCursorChanged: {
    var item = browser.entry(cursor);
    _cursorPath = item ? item.path : "";
  }
  Connections {
    target: root.browser
    function onCurrentPathChanged() { root.clear(); }
    function onHistoryLeaving() { root.browser.rememberHistory("selection", root.snapshot()); }
    function onHistoryRestored(state) { root.restore(state.selection); }
    function onListingChanged() { root._revalidate(); }
    function onStatusChanged() { root._revalidate(); }
  }
}
