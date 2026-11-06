import QtQuick

// Independent metadata bindings keep a dependent range from evaluating siblings.
QtObject {
  required property string field
  property real from: 0
  property real to: 1

  function project(value) {
    return Math.max(Math.min(from, to), Math.min(Math.max(from, to), value));
  }
}
