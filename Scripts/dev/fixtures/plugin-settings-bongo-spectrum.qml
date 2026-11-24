// Inert common audio observation, installed only in the disposable test copy.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
  property var values: []
  property bool isIdle: true
  property var registrations: new Set()
  property int registerCalls: 0
  property int unregisterCalls: 0
  function registerComponent(id) {
    registrations.add(id);
    registerCalls++;
  }
  function unregisterComponent(id) {
    registrations.delete(id);
    unregisterCalls++;
  }
}
