import QtQuick

// Example usage:
// NLoader {
//   content: Component {
//     YourComponent {
Loader {
  id: loader

  // Boolean control to load/unload the item
  property bool isLoaded: false

  // Provide the component to be loaded.
  property Component content

  active: isLoaded
  asynchronous: true
  sourceComponent: content

  onActiveChanged: {
    if (active && item && item.show) {
      item.show()
    }
  }

  onItemChanged: {
    if (active && item && item.show) {
      item.show()
    }
  }

  Connections {
    target: loader.item
    ignoreUnknownSignals: true
    function onDismissed() {
      loader.isLoaded = false
    }
  }
}
