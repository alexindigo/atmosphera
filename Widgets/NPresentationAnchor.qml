import QtQuick

// An anchor QObject can survive while its delegate represents another entity.
// Callers expose presentationIdentity (or their own modelData) as input; this
// guard never walks into the caller's parent/delegate implementation.
QtObject {
  id: root

  property Item anchorItem: null
  property Item physicalAnchor: null
  property var identity: undefined
  property bool armed: false
  readonly property bool hasIdentity: anchorItem !== null && ("presentationIdentity" in anchorItem || "modelData" in anchorItem)
  readonly property var currentIdentity: anchorItem === null ? undefined : ("presentationIdentity" in anchorItem ? anchorItem.presentationIdentity : ("modelData" in anchorItem ? anchorItem.modelData : undefined))
  readonly property bool valid: armed && anchorItem !== null && physicalAnchor !== null && (!hasIdentity || currentIdentity === identity)

  signal invalidated
  onValidChanged: {
    if (armed && !valid)
      invalidated();
  }

  function request(item, requestedIdentity, physicalItem) {
    armed = false;
    anchorItem = item;
    physicalAnchor = physicalItem === undefined ? item : physicalItem;
    identity = requestedIdentity === undefined ? currentIdentity : requestedIdentity;
    armed = true;
    if (!valid)
      invalidated();
  }

  function cancel() {
    armed = false;
    anchorItem = null;
    physicalAnchor = null;
    identity = undefined;
  }
}
