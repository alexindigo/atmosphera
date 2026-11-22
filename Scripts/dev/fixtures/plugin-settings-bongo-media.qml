// Inert common MPRIS observation; no real player discovery.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
  property bool isPlaying: false
}
