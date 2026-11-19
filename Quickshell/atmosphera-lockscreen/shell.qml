//@ pragma Env ATMOSPHERA_LOCKSCREEN=1
import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
  SettingsBootstrap { id: bootstrap }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component { LockSession {} }
  }
}
