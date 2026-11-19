import QtQuick

// UI input ownership only. The editor supplies its boundary; native controls
// own their buffers/validation. No page-state inspection or preference writes.
QtObject {
  id: root
  required property Item target
  property bool active: true
  property bool dirty: false
  property int generation: 0
  property int _committedGeneration: -1
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
    // A persistence receipt cannot cover text still buffered in a control.
    return _committedGeneration;
  }

  function acknowledge(fence) {
    if (fence === generation)
      dirty = false;
  }

  function reset() {
    generation++;
    dirty = false;
    _committedGeneration = generation;
  }

  function commit(moveFocus) {
    var input = focusedInput;
    if (dirty) {
      // Native controls publish their own buffers. A false result means an
      // ongoing gesture cannot yet publish; unknown controls stay unacknowledged.
      if (!input || (typeof input.commitEdit === "function" && input.commitEdit(moveFocus) !== false))
        _committedGeneration = generation;
    }
    // Explicit Apply/close also settles the control's focus-lost contract.
    // Automatic live persistence must not end the user's editing session.
    if (moveFocus !== false) {
      _focusSink.forceActiveFocus();
      _committedGeneration = generation;
    }
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
