import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
  id: root

  property int currentIndex: 0

  // Private
  property int previousIndex: 0
  property bool initialized: false
  property bool animating: false
  property real animatingHeight: 0
  property real transitionGap: Style.marginXL
  property real transitionTime: Style.animationNormal
  property list<Item> contentItems: []

  default property alias content: container.data

  clip: true
  Layout.fillWidth: true

  // During animation, use max height to prevent clipping. Otherwise use current item height.
  implicitHeight: animating ? animatingHeight : (contentItems[currentIndex] ? contentItems[currentIndex].implicitHeight : 0)

  Item {
    id: container
    anchors.fill: parent
  }

  Component.onCompleted: {
    _initializeItems();
  }

  function _initializeItems() {
    contentItems = [];
    for (let i = 0; i < container.children.length; i++) {
      const child = container.children[i];
      contentItems.push(child);
      child.width = Qt.binding(() => root.width);

      if (i === currentIndex) {
        child.x = 0;
        child.visible = true;
      } else {
        child.x = root.width;
        child.visible = false;
      }
    }
    initialized = true;
  }

  onCurrentIndexChanged: {
    if (!initialized || contentItems.length === 0)
      return;
    if (previousIndex === currentIndex)
      return;

    _animateTransition(previousIndex, currentIndex);
    previousIndex = currentIndex;
  }

  function _animateTransition(fromIdx, toIdx) {
    const fromItem = contentItems[fromIdx];
    const toItem = contentItems[toIdx];
    const slideLeft = toIdx > fromIdx;

    // Set height to max of both items during animation
    const fromHeight = fromItem ? fromItem.implicitHeight : 0;
    const toHeight = toItem ? toItem.implicitHeight : 0;
    animatingHeight = Math.max(fromHeight, toHeight);
    animating = true;

    // Position incoming item off-screen (with gap)
    if (toItem) {
      toItem.visible = true;
      toItem.x = slideLeft ? root.width + transitionGap : -root.width - transitionGap;
    }

    // Animate both items together (with gap)
    if (fromItem) {
      fromAnim.target = fromItem;
      fromAnim.to = slideLeft ? -root.width - transitionGap : root.width + transitionGap;
      fromAnim.start();
    }

    if (toItem) {
      toAnim.target = toItem;
      toAnim.start();
    }
  }

  NumberAnimation {
    id: fromAnim
    property: "x"
    duration: root.transitionTime
    easing.type: Easing.OutCubic
    onFinished: {
      if (target && target !== contentItems[currentIndex]) {
        target.visible = false;
      }
      animating = false;
    }
  }

  NumberAnimation {
    id: toAnim
    property: "x"
    to: 0
    duration: root.transitionTime
    easing.type: Easing.OutCubic
  }
}
