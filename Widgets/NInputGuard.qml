import QtQuick

// One ownership predicate for focus-based Keys and window-scoped Shortcuts.
// Logical hiding temporarily overrides enabled, restoring the caller's binding.
// Native inactivity affects only keyboard eligibility, never pointer/style state.
QtObject {
  id: root
  required property Item target
  property bool active: true
  property bool manageEnabled: true
  property Item focusOwner: null
  property Item focusTarget: target
  property bool focusOnActivation: false
  readonly property bool surfaceAvailable: active && target.visible && !!target.Window.window && target.Window.window.visible
  readonly property bool ownsKeys: keyboardEligible()
  readonly property bool acceptsKeys: ownsKeys && target.enabled
  property Item _focusedItem: null
  property Item _resumeItem: null
  property bool _returnPending: false
  property bool _suppress: false

  function keyboardEligible() {
    return surfaceAvailable && target.Window.active;
  }

  function updateSuppression() {
    if (!manageEnabled || surfaceAvailable) {
      _suppress = false;
    } else if (target.enabled) {
      // An already-disabled ancestor provides the protection. Do not capture
      // its effective false as this item's original local enabled value.
      _suppress = true;
    }
  }

  function rememberFocus() {
    if (!keyboardEligible())
      return;
    const window = target.Window.window;
    const focused = window ? window.activeFocusItem : null;
    let item = focused;
    while (item && item !== target)
      item = item.parent;
    _focusedItem = item === target ? focused : null;
  }

  function settleFocus() {
    if (_returnPending) {
      _returnPending = false;
      if (focusOwner && focusOwner.visible && focusOwner.enabled && focusOwner.Window.active)
        focusOwner.forceActiveFocus();
    }
    if (acceptsKeys) {
      const item = focusOnActivation ? focusTarget : _resumeItem;
      _resumeItem = null;
      if (item && item.visible && item.enabled)
        item.forceActiveFocus();
      rememberFocus();
    }
  }

  function updateOwnership() {
    // Capture the return intent before enabled suppression can clear focus.
    // Either native/logical notification may arrive first; pending return is
    // latched until settleFocus consumes it, never overwritten by the second.
    if (!keyboardEligible()) {
      if (!surfaceAvailable) {
        _returnPending = _returnPending || !!_focusedItem;
        _resumeItem = null;
      } else {
        _resumeItem = _focusedItem;
      }
    }
    updateSuppression();
    Qt.callLater(root.settleFocus);
  }
  onOwnsKeysChanged: updateOwnership()
  onSurfaceAvailableChanged: updateOwnership()
  onManageEnabledChanged: updateSuppression()
  // The surface can activate before an owning Loader/ancestor enables its
  // content. Focus requests must settle at effective readiness, not just at
  // the earlier native activation edge.
  onAcceptsKeysChanged: {
    if (acceptsKeys)
      Qt.callLater(root.settleFocus);
  }

  property Binding _enabledGuard: Binding {
    target: root.target
    property: "enabled"
    value: false
    when: root._suppress
    restoreMode: Binding.RestoreBindingOrValue
  }
  property Connections _focusObserver: Connections {
    target: root.target.Window.window
    function onActiveFocusItemChanged() {
      root.rememberFocus();
    }
  }
  property Connections _enabledObserver: Connections {
    target: root.target
    function onEnabledChanged() {
      root.updateSuppression();
    }
  }
  Component.onCompleted: {
    updateSuppression();
    rememberFocus();
    Qt.callLater(root.settleFocus);
  }
}
