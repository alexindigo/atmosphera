import QtQuick

// Stable window ids for Wayland toplevel handles, which carry no id of their
// own. A toplevel keeps its id for its whole lifetime; an id is never derived
// from a list position and never reused, so a captured id cannot come to
// name a different window.
QtObject {
  property var _ids: new Map()
  property int _next: 1

  function idFor(toplevel) {
    if (!_ids.has(toplevel))
      _ids.set(toplevel, _next++);
    return _ids.get(toplevel);
  }

  // Forget toplevels that are no longer listed.
  function retain(toplevels) {
    const listed = new Set(Array.from(toplevels));
    for (const toplevel of Array.from(_ids.keys())) {
      if (!listed.has(toplevel))
        _ids.delete(toplevel);
    }
  }
}
