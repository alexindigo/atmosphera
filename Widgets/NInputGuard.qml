import QtQuick

// One ownership predicate for focus-based Keys and window-scoped Shortcuts.
// Suppression temporarily overrides enabled, then restores its caller-owned
// binding/value. Eligibility must not depend on the enabled value we suppress.
QtObject {
  id: root
  required property Item target
  property bool active: true
  property bool manageEnabled: true
  property Item focusOwner: null
  property Item focusTarget: target
  property bool focusOnActivation: false
  readonly property bool ownsKeys: active && target.visible && !!target.Window.window && target.Window.window.visible && target.Window.active
  readonly property bool acceptsKeys: ownsKeys && target.enabled
  property Item _focusedItem: null
  property Item _resumeItem: null
  property bool _returnPending: false
  property bool _suppress: false

  function updateSuppression() {
    if (!manageEnabled || ownsKeys) {
      _suppress = false;
    } else if (target.enabled) {
      // An already-disabled ancestor provides the protection. Do not capture
      // its effective false as this item's original local enabled value.
      _suppress = true;
    }
  }

  function rememberFocus() {
    if (!manageEnabled || !ownsKeys)
      return;
    const window = target.Window.window;
    const focused = window ? window.activeFocusItem : null;
    let item = focused;
    while (item && item !== target)
      item = item.parent;
    _focusedItem = item === target ? focused : null;
  }

  function settleFocus() {
    if (!manageEnabled)
      return;
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

  onOwnsKeysChanged: {
    updateSuppression();
    if (!ownsKeys) {
      if (!active || !target.visible) {
        _returnPending = !!_focusedItem;
        _resumeItem = null;
      } else {
        _resumeItem = _focusedItem;
      }
    }
    Qt.callLater(root.settleFocus);
  }
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
