pragma Singleton

import QtQuick

QtObject {
  id: root

  // Map of version number to migration component
  readonly property var migrations: ({
                                       27: migration27Component,
                                       28: migration28Component
                                     })

  // Migration components
  property Component migration27Component: Migration27 {}
  property Component migration28Component: Migration28 {}
}
