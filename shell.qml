// Directory preparation precedes all settings/service singleton construction.
//@ pragma ShellId app.atmosphera.Shell
//@ pragma Env QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi,vdpau
//@ pragma Env QT_FFMPEG_ENCODING_HW_DEVICE_TYPES=vaapi,vdpau
import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
  SettingsBootstrap { id: bootstrap }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component { ShellSession {} }
  }
}
