import QtQuick

// A shortcut belongs to a live visual scope, not merely to a QML object.
// enabled is an additional caller condition; it cannot bypass scope ownership.
Item {
  id: root
  required property Item scope
  parent: scope
  property alias sequence: binding.sequence
  property alias sequences: binding.sequences
  signal activated

  NInputGuard {
    id: ownership
    target: root
    manageEnabled: false
  }

  Shortcut {
    id: binding
    enabled: ownership.acceptsKeys
    onActivated: root.activated()
  }
}
