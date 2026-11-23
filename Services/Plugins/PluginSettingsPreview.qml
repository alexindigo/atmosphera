import QtQuick

// Presentation uses the actual selected native draft. Revision tokens below
// acknowledge UI input only; no copied preference values or rollback snapshots.
QtObject {
  id: root
  required property var sourceValue
  property var sourceReadOwner: null
  required property var currentOwner
  required property var draftFactory
  property var _token: null
  property var _owner: null
  property var _editor: null
  property var _baseScope: null
  property bool _ownedEditor: false
  property var _revisions: ({})
  property var _inputs: ({})
  property var _lifetime: ({
                             alive: true
                           })
  readonly property var values: _token && _editor && !_editor.closed && currentOwner() === _owner ? _editor.previewValues : sourceValue
  readonly property var readOwner: _token && _editor && !_editor.closed && currentOwner() === _owner ? _baseScope : sourceReadOwner
  readonly property var baseScope: _token && _editor && !_editor.closed && currentOwner() === _owner ? _baseScope : null
  property Connections _editorRebase: Connections {
    target: root._editor
    function onRebased(result) {
      root.rebased(result);
    }
  }
  function rebased(result) {
    var editor = root._editor;
    if (!_lifetime.alive || !_token || !editor || editor.closed || currentOwner() !== _owner)
      return;
    if (_baseScope)
      _baseScope.detach();
    // These are explicit UI inputs, not a preference snapshot. Successful
    // native Apply closes its scopes even when its acknowledgement is stale.
    if (result && result.refreshState === "stale") {
      var revisions = Object.create(null);
      var inputs = Object.create(null);
      for (var key of Object.keys(_revisions))
        if (editor.publishPreview(key, _inputs[key], _revisions[key])) {
          revisions[key] = _revisions[key];
          inputs[key] = _inputs[key];
        }
      _revisions = revisions;
      _inputs = inputs;
    }
    _baseScope = editor.previewScope();
  }
  Component.onDestruction: {
    if (_baseScope)
      _baseScope.detach();
    if (_ownedEditor && _editor)
      _editor.destroy();
    _lifetime.alive = false;
  }

  function open(providedEditor) {
    var identity = currentOwner();
    if (_token || identity === null || identity === undefined)
      return null;
    var editor = providedEditor || draftFactory();
    if (!editor || !editor.ready) {
      // A refused synchronous preview owns no session. Release only editors
      // created here; a supplied editor still belongs to its caller.
      if (editor && !providedEditor)
        editor.discard();
      return null;
    }
    var owned = !providedEditor;
    var token = {};
    var lifetime = _lifetime;
    _token = token;
    _owner = identity;
    _editor = editor;
    _ownedEditor = owned;
    _baseScope = editor.previewScope();
    _revisions = Object.create(null);
    _inputs = Object.create(null);
    function active() {
      return lifetime.alive && root._token === token && root._editor && !root._editor.closed;
    }
    return {
      update: function (patch, writeFields) {
        if (!active() || root.currentOwner() !== identity || !patch || typeof patch !== "object" || Array.isArray(patch) || editor.busy)
          return false;
        try {
          var edits = editor.copyValue(patch);
          for (var key of Object.keys(edits))
            if (editor.fields.indexOf(key) === -1)
              return false;
          var revisions = Object.assign(Object.create(null), root._revisions);
          var inputs = Object.assign(Object.create(null), root._inputs);
          function publish(key) {
            var revision = editor.publishPreview(key, edits[key]);
            if (!revision)
              return false;
            revisions[key] = revision;
            inputs[key] = edits[key];
            return true;
          }
          // The selected capability still owns field validation and dirty state,
          // but it uses the same publisher as the standalone preview and replay.
          if (typeof writeFields === "function") {
            if (writeFields(edits, publish) !== true)
              return false;
          } else {
            for (var key of Object.keys(edits))
              if (!publish(key))
                return false;
          }
          root._inputs = inputs;
          root._revisions = revisions;
          return true;
        } catch (error) {
          return false;
        }
      },
      capture: function () {
        return active() ? {
                            owner: token,
                            revisions: Object.assign(Object.create(null), root._revisions)
                          } : null;
      },
      acknowledge: function (captured) {
        if (!active() || !captured || captured.owner !== token)
          return false;
        var remaining = Object.create(null);
        var inputs = Object.create(null);
        for (var key of Object.keys(root._revisions))
          if (root._revisions[key] !== captured.revisions[key]) {
            remaining[key] = root._revisions[key];
            inputs[key] = root._inputs[key];
          }
        root._inputs = inputs;
        root._revisions = remaining;
        return true;
      },
      pending: function () {
        return active() && Object.keys(root._revisions).length > 0;
      },
      values: function () {
        return active() ? editor.previewValues : null;
      },
      close: function () {
        if (lifetime.alive && root._token === token) {
          if (owned && root._editor && !root._editor.closed && !editor.discard())
            return false;
          if (root._baseScope)
            root._baseScope.detach();
          root._baseScope = null;
          root._token = null;
          root._owner = null;
          root._editor = null;
          root._ownedEditor = false;
          root._revisions = Object.create(null);
          root._inputs = Object.create(null);
        }
        return true;
      }
    };
  }
}
