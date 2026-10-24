import QtQuick

// One native editor and one key table per surface. Commands precede native
// editing; controls and window/application Shortcuts cannot bypass the owner.
QtObject {
  id: root
  required property Item scope
  required property TextInput input
  required property var keyTable
  required property var keyString
  property bool active: true
  readonly property bool available: active && !!scope && !!input && scope.visible && scope.enabled && input.visible && input.enabled && !!input.Window.window && input.Window.window.visible
  readonly property bool ownsKeys: available && input.Window.active

  function claimFocus() {
    if (available && input.Window.window.activeFocusItem !== input)
      input.forceActiveFocus();
  }

  function entryFor(event) {
    const key = keyString(event);
    for (const entry of keyTable) {
      if ((entry.keys && entry.keys.indexOf(key) !== -1) || (entry.matches && entry.matches(event)))
        return entry;
    }
    return null;
  }

  function dispatch(event) {
    // Preedit, including Enter/Escape, belongs to the input method.
    if (!ownsKeys || input.inputMethodComposing || input.preeditText.length > 0)
      return;
    const entry = entryFor(event);
    if (entry && entry.kind === "command") {
      event.accepted = true;
      entry.run();
    }
  }

  onAvailableChanged: claimFocus()
  onOwnsKeysChanged: claimFocus()
  Component.onCompleted: claimFocus()

  property Binding _priority: Binding {
    target: root.input.Keys
    property: "priority"
    value: Keys.BeforeItem
    when: root.active
    restoreMode: Binding.RestoreBindingOrValue
  }
  property Connections _keys: Connections {
    target: root.input.Keys
    enabled: root.ownsKeys
    function onShortcutOverride(event) {
      // Use the same table as dispatch. Native editing/IME keeps Qt's own
      // override/filtering path; only surface commands are reserved here.
      const entry = root.entryFor(event);
      if (entry && entry.kind === "command")
        event.accepted = true;
    }
    function onPressed(event) {
      root.dispatch(event);
    }
  }
  property Connections _focus: Connections {
    target: root.input.Window.window
    function onActiveFocusItemChanged() {
      // Synchronous, including controls introduced by plugins. No settling
      // queue or timer: the next key sees the same owner.
      root.claimFocus();
    }
  }
}
