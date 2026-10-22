import QtQuick
import Quickshell.Io

Process {
  stdout: StdioCollector {}
  stderr: StdioCollector {}
}
