//@ pragma Env ATMOSPHERA_LOCKSCREEN=1
//@ pragma Env QT_IM_MODULE=compose
//@ pragma Env QT_IM_MODULES=compose
import QtQuick
import Quickshell

ShellRoot {
  // Reading settings never creates preference directories or starts a writer.
  LockSession {}
}
