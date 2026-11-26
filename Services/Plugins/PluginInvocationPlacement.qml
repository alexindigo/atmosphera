import QtQuick
import qs.Services.Plugins

// Several views of a shared placement count as one instance.
QtObject {
  id: root

  property var api: null
  onApiChanged: PluginInstances.noteSpawnedView(root.api)
  Component.onCompleted: PluginInstances.noteSpawnedView(root.api)
}
