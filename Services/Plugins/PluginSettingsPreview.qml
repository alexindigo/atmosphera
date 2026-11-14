import QtQuick

// Selected-owner presentation only. I5 supplies draft.values and native owner
// identity here; this transitional view never calls a preference setter.
QtObject {
  id: root
  required property var sourceValue
  required property var currentOwner
  property var _token: null
  property var _owner: null
  property var _fields: ({})
  property var _lifetime: ({alive: true})
  readonly property var values: {
    var source = sourceValue || {};
    if (!_token || currentOwner() !== _owner)
      return source;
    var view = Object.assign(Object.create(null), source);
    for (var key of Object.keys(_fields))
      view[key] = _fields[key].value;
    return view;
  }

  Component.onDestruction: _lifetime.alive = false

  function open() {
    var owner = currentOwner();
    if (_token || owner === null || owner === undefined)
      return null;
    var token = {};
    var lifetime = _lifetime;
    _token = token;
    _owner = owner;
    _fields = Object.create(null);
    function active() { return lifetime.alive && root._token === token; }
    function copy(value) { return JSON.parse(JSON.stringify(value)); }
    return {
      update: function (patch) {
        if (!active() || root.currentOwner() !== owner || !patch || typeof patch !== "object" || Array.isArray(patch))
          return false;
        var owned = copy(patch);
        var fields = Object.assign(Object.create(null), root._fields);
        for (var key of Object.keys(owned))
          fields[key] = {value: owned[key], revision: {}};
        root._fields = fields;
        return true;
      },
      capture: function () {
        if (!active()) return null;
        var revisions = Object.create(null);
        for (var key of Object.keys(root._fields)) revisions[key] = root._fields[key].revision;
        return {owner: token, revisions: revisions};
      },
      acknowledge: function (captured) {
        if (!active() || !captured || captured.owner !== token) return false;
        var remaining = Object.create(null);
        for (var key of Object.keys(root._fields)) {
          if (root._fields[key].revision !== captured.revisions[key]) remaining[key] = root._fields[key];
        }
        root._fields = remaining;
        return true;
      },
      pending: function () { return active() && Object.keys(root._fields).length > 0; },
      values: function () { return active() ? root.values : null; },
      close: function () {
        if (active()) { root._fields = Object.create(null); root._token = null; root._owner = null; }
        return true;
      }
    };
  }
}
