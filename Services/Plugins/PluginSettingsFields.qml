import QtQuick
import "PluginSettingsRead.js" as Read

// Field capabilities around one already-selected native editor. This object
// belongs to the host/session; pages receive only the frozen handles it returns.
// Native code still owns admission, sparse difference and publication.
QtObject {
  id: root
  required property var editor
  required property string scopeKind
  required property var metadata
  required property var capture
  required property var recapture
  property var _handles: Object.create(null)
  property var _pending: Object.create(null)
  property var _errors: Object.create(null)
  property var _receipt: null
  property var _lifetime: ({
                             alive: true
                           })
  readonly property bool ready: !!editor && editor.ready && !!metadata && metadata.ready === true && !!capture
  readonly property bool busy: !!editor && editor.busy
  property var _presentations: Object.create(null)
  readonly property var undisplayedOverrides: configurationKeys.filter(function (key) {
    return !root._presentations[key] && (root._own(root.capture?.fields, key)?.overridden === true || root._pending[key] === "set");
  }).map(function (key) {
    return root.field(key);
  })

  // A field chrome reports only its own presentation lifetime. The host never
  // queries a page's controls or reads their values to discover missing fields.
  function _presented(key) {
    var next = Object.assign(Object.create(null), _presentations);
    next[key] = (next[key] || 0) + 1;
    _presentations = next;
    var alive = true;
    var lifetime = _lifetime;
    return function () {
      if (!alive || !lifetime.alive)
        return;
      alive = false;
      var remaining = Object.assign(Object.create(null), root._presentations);
      remaining[key] = Math.max(0, (remaining[key] || 0) - 1);
      root._presentations = remaining;
    };
  }
  readonly property string error: Object.keys(_errors).length ? "settings-field-input" : ""
  readonly property var configurationKeys: ready ? Object.keys(metadata.fields).filter(function (key) {
    return root.metadata.fields[key].usage === "configuration";
  }) : []

  function _own(object, key) {
    var member = Object.getOwnPropertyDescriptor(object, key);
    return member ? member.value : undefined;
  }
  function _copy(value) {
    return value === undefined ? undefined : editor.copyValue(value);
  }
  function _recordError(key, code) {
    var errors = Object.assign(Object.create(null), _errors);
    errors[key] = code;
    _errors = errors;
    return false;
  }
  function _clearError(key) {
    var errors = Object.assign(Object.create(null), _errors);
    delete errors[key];
    _errors = errors;
  }
  function _allowed(key, content) {
    var declaration = metadata && metadata.ready === true ? _own(metadata.fields, key) : null;
    return declaration && (content ? scopeKind === "plugin" && declaration.usage === "content" : declaration.usage === "configuration");
  }
  function _canEdit(key, content) {
    if (!_allowed(key, content))
      return _recordError(key, "settings-field-capability");
    if (!ready || !editor.writable || editor.closed || editor._releasePending || busy)
      return _recordError(key, "settings-field-state");
    return true;
  }
  function _set(key, value, content) {
    if (!_canEdit(key, content))
      return false;
    try {
      // This setter is the existing checked native atomic-leaf ingress. No
      // stored effective snapshot or compound presentation alias enters Apply.
      editor.values[key] = value;
      var pending = Object.assign(Object.create(null), _pending);
      pending[key] = "set";
      _pending = pending;
      _clearError(key);
      return true;
    } catch (error) {
      return _recordError(key, "settings-field-value");
    }
  }
  function _reset(key, content) {
    if (!_canEdit(key, content))
      return false;
    if (content)
      return _recordError(key, "settings-content-reset");
    return _resetKeys([key]);
  }
  // One native staged removal, or one overlay unset per atomic path, for a
  // finite multi-field control Reset. Publication remains one native Apply.
  function _resetKeys(keys) {
    if (scopeKind === "plugin") {
      // Never replace this with a default-valued assignment or a live reset.
      if (typeof editor.handle.stageReset !== "function")
        return _recordError(keys[0], "settings-staged-reset-unavailable");
      var lifetime = _lifetime;
      try {
        editor.handle.stageReset(keys.map(function (key) {
          return [key];
        }), function (result) {
          if (!lifetime.alive)
            return;
          for (var key of keys) {
            if (result.status !== "staged")
              root._recordError(key, "settings-field-reset");
            else
              root._markReset(key);
          }
        });
        return true;
      } catch (error) {
        return _recordError(keys[0], "settings-field-reset");
      }
    }
    try {
      for (var key of keys) {
        if (!editor.handle.unset([key]))
          return _recordError(key, "settings-field-reset");
        _markReset(key);
      }
      return true;
    } catch (error) {
      return _recordError(keys[0], "settings-field-reset");
    }
  }
  function resetFields(keys) {
    if (!Array.isArray(keys) || keys.length === 0 || keys.some(function (key) {
      return typeof key !== "string";
    }))
      return false;
    for (var key of keys)
      if (!_canEdit(key, false))
        return false;
    return _resetKeys(keys.slice());
  }
  function _markReset(key) {
    var pending = Object.assign(Object.create(null), _pending);
    pending[key] = "reset";
    _pending = pending;
    _clearError(key);
  }
  function _value(key) {
    var facts = capture ? _own(capture.fields, key) : null;
    // Overlay unset has absent preview presentation before Apply. The frozen
    // inherited read facts supply its presentation, never a stored default.
    if (scopeKind === "instance" && _own(_pending, key) === "reset")
      return facts && facts.inheritedPresent ? _copy(facts.inheritedValue) : undefined;
    return editor && editor.values ? _copy(editor.values[key]) : undefined;
  }
  function _field(key, content) {
    if (typeof key !== "string" || !capture || !_allowed(key, content)) {
      _recordError(typeof key === "string" ? key : "", "settings-field-capability");
      return null;
    }
    if (_own(_handles, key))
      return _handles[key];
    var handle = Object.create(null);
    Object.defineProperties(handle, {
                              key: {
                                value: key,
                                enumerable: true
                              },
                              scopeKind: {
                                value: scopeKind,
                                enumerable: true
                              },
                              sensitive: {
                                value: metadata.fields[key].sensitive === true,
                                enumerable: true
                              },
                              presented: {
                                value: function () {
                                  return root._presented(key);
                                }
                              },
                              value: {
                                get: function () {
                                  return root._value(key);
                                },
                                enumerable: true
                              },
                              present: {
                                get: function () {
                                  return root._value(key) !== undefined;
                                },
                                enumerable: true
                              },
                              inheritedValue: {
                                get: function () {
                                  var facts = root._own(root.capture.fields, key);
                                  return facts && facts.inheritedPresent ? root._copy(facts.inheritedValue) : undefined;
                                },
                                enumerable: true
                              },
                              inheritedPresent: {
                                get: function () {
                                  return root._own(root.capture.fields, key)?.inheritedPresent === true;
                                },
                                enumerable: true
                              },
                              overridden: {
                                get: function () {
                                  return root._own(root.capture.fields, key)?.overridden === true;
                                },
                                enumerable: true
                              },
                              pendingIntent: {
                                get: function () {
                                  return root._own(root._pending, key) || "";
                                },
                                enumerable: true
                              },
                              error: {
                                get: function () {
                                  return root._own(root._errors, key) || "";
                                },
                                enumerable: true
                              },
                              receipt: {
                                get: function () {
                                  return root._copy(root._receipt);
                                },
                                enumerable: true
                              },
                              set: {
                                value: function (value) {
                                  return root._set(key, value, content);
                                }
                              },
                              reset: {
                                value: function () {
                                  return root._reset(key, content);
                                }
                              }
                            });
    Object.freeze(handle);
    _handles[key] = handle;
    return handle;
  }
  function field(key) {
    return _field(key, false);
  }
  function contentField(key) {
    return _field(key, true);
  }

  function readSettings() {
    var result = Object.create(null);
    if (!metadata || !metadata.fields)
      return Read.freeze(result);
    for (var key of Object.keys(metadata.fields)) {
      var value = _value(key);
      if (value !== undefined)
        result[key] = value;
    }
    return Read.freeze(result);
  }

  // Called only by the host at the native accepted-current receipt boundary,
  // before completion signals/callbacks can introduce more user input.
  function acknowledge(result) {
    _receipt = result;
    if (!result || ["saved", "nothing_to_save"].indexOf(result.status) === -1 || result.refreshState !== "current")
      return false;
    if (!editor || editor.closed || editor.dirty || editor.busy || editor.handle.conflicted)
      return false;
    if (editor.handle.editorId && result.editorId !== editor.handle.editorId)
      return false;
    var next = recapture();
    if (!next || !next.current())
      return false;
    capture = next;
    _pending = Object.create(null);
    _errors = Object.create(null);
    return true;
  }
  function resetConfiguration(callback) {
    if (scopeKind !== "instance" || !ready || busy || error)
      return false;
    for (var key of configurationKeys)
      if (!_reset(key, false))
        return false;
    return editor.apply(editor.values, callback);
  }
  Component.onDestruction: _lifetime.alive = false
}
