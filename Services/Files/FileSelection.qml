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

  function _selectable(entry) {
    return entry && entry.directory === (selectable === "folders");
  }

  function clear() {
    _selectedPaths = [];
    cursor = -1;
    _anchor = -1;
    _cursorPath = "";
    _anchorPath = "";
    _prefix = "";
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
      _selectedPaths = paths;
    } else {
      _anchor = index;
      _anchorPath = item.path;
      if (!_selectable(item)) {
        if (!(multiple && (modifiers & Qt.ControlModifier)))
          _selectedPaths = [];
      } else if (multiple && (modifiers & Qt.ControlModifier)) {
        _selectedPaths = _selectedPaths.includes(item.path) ? _selectedPaths.filter(p => p !== item.path) : _selectedPaths.concat([item.path]);
      } else
        _selectedPaths = [item.path];
    }
  }

  function move(delta, extend) {
    if (browser.count)
      click(Math.max(0, Math.min(browser.count - 1, cursor < 0 ? (delta < 0 ? browser.count - 1 : 0) : cursor + delta)), extend ? Qt.ShiftModifier : Qt.NoModifier);
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
    _selectedPaths = paths;
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
    _selectedPaths = _selectedPaths.filter(function(path) {
      var index = browser.indexOfPath(path);
      return index >= 0 && root._selectable(browser.entry(index));
    });
    if (!multiple && _selectedPaths.length > 1)
      _selectedPaths = _selectedPaths.slice(0, 1);
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
    function onListingChanged() { root._revalidate(); }
    function onStatusChanged() { root._revalidate(); }
  }
}
