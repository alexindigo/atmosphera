import QtQuick
import Quickshell

ShellRoot {
  id: root
  property var favicon
  property var facade
  property int nativeCreations: 0
  property bool capturing: false
  readonly property string plugin: "file://" + Quickshell.env("IMAGE_PLUGINS") + "/niri-windows-map/"

  FloatingWindow {
    implicitWidth: 128
    implicitHeight: 128
    Rectangle {
      id: frame
      anchors.centerIn: parent
      width: 128
      height: 128
      color: "black"
    }
  }

  function create(name, properties) {
    const component = Qt.createComponent(plugin + name + ".qml");
    if (component.status !== Component.Ready) {
      console.error(component.errorString());
      Qt.exit(4);
      return null;
    }
    return component.createObject(frame, properties);
  }

  Component.onCompleted: {
    facade = create("MapFacade", {});
    if (!facade?.currentShell) {
      Qt.exit(5);
      return;
    }
    favicon = create("MapFavicon", {
                       useSharedDecoder: Qt.binding(() => facade.currentShell),
                       iconSource: Quickshell.env("IMAGE_FIXTURES") + "/Still.webp",
                       sourceSize: Qt.size(64, 64),
                       width: 128,
                       height: 128
                     });
    observe.observeItem();
  }

  Connections {
    id: observe
    target: root.favicon ?? null
    function observeItem() {
      if (root.favicon?.item && root.favicon.item.imageState === undefined)
        ++root.nativeCreations;
    }
    function onItemChanged() {
      observeItem();
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      const item = root.favicon?.item;
      if (root.capturing || item?.imageState !== "ready")
        return;
      root.capturing = true;
      frame.grabToImage(result => {
        const saved = result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/map-favicon.png");
        console.log("IMAGE_GRAB|" + JSON.stringify({
                                                     saved: saved
                                                   }));
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         nativeCreations: root.nativeCreations,
                                                         format: item.imageResult.format,
                                                         shared: root.facade.currentShell && String(root.favicon.source).endsWith("/SharedMapFavicon.qml")
                                                       }));
        Qt.quit();
      });
    }
  }
  Timer {
    interval: 15000
    running: true
    onTriggered: Qt.exit(6)
  }
}
