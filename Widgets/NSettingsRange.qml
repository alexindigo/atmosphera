import QtQuick

// Independent metadata bindings keep a dependent range from evaluating siblings.
QtObject {
  required property string field
  property real from: 0
  property real to: 1
}
