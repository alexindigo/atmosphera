pragma Singleton

import Quickshell

// Dock.qml publishes its own current reveal surface. Consumers never reproduce
// the dock's item-count or bar-aware placement calculations.
Singleton {
  id: root
  property var _reveals: ({})

  function publishReveal(owner, screenName, rect) {
    if (!screenName)
      return;
    var next = Object.assign({}, _reveals);
    next[screenName] = {
      owner: owner,
      rect: rect
    };
    _reveals = next;
  }

  function removeReveal(owner, screenName) {
    if (!_reveals[screenName] || _reveals[screenName].owner !== owner)
      return;
    var next = Object.assign({}, _reveals);
    delete next[screenName];
    _reveals = next;
  }

  function revealRect(screenName) {
    return _reveals[screenName] ? _reveals[screenName].rect : null;
  }
}
