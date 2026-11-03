import QtQuick

// UI input ownership only. The editor supplies its boundary; native controls
// own their buffers/validation. No page-state inspection or preference writes.
QtObject {
  id: root
  required property Item target
  property bool active: true
  property bool dirty: false
  property int generation: 0
  readonly property var focusedInput: {
    var window = target.Window.window;
    var focused = active && window ? window.activeFocusItem : null;
    var item = focused;
    while (item && item !== target)
      item = item.parent;
    return item === target ? focused : null;
  }

  function edited() {
    if (!active)
      return;
    generation++;
    dirty = true;
  }

  function capture() {
    return generation;
  }

  function acknowledge(fence) {
    if (fence === generation)
      dirty = false;
  }

  function reset() {
    generation++;
    dirty = false;
  }

  function commit() {
    if (!dirty)
      return;
    var input = focusedInput;
    if (input && typeof input.commitEdit === "function")
      input.commitEdit();
    // Native text editingFinished and the control's public focus-lost contract
    // settle synchronously before the editor gathers its submitted values.
    _focusSink.forceActiveFocus();
  }

  // Focusing a FocusScope preserves its focused child. An owned, unpainted
  // Item is the actual focus destination, so every native editor receives blur.
  property Item _focusSink: Item {
    parent: root.target
  }

  property Connections _userInput: Connections {
    target: root.focusedInput
    ignoreUnknownSignals: true
    function onTextEdited() { root.edited(); }
    function onValueModified() { root.edited(); }
    function onMoved() { root.edited(); }
    function onActivated() { root.edited(); }
  }
}
