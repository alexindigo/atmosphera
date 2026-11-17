//@ pragma Env ATMOSPHERA_LOCKSCREEN=1
import QtQuick
import Quickshell

ShellRoot {
  // Reading settings never creates preference directories or starts a writer.
  LockSession {}
}
