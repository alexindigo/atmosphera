// Portal backend for org.freedesktop.impl.portal.Settings.
// Registers on the session bus so xdg-desktop-portal delegates
// color-scheme queries to the shell instead of requiring GNOME/KDE.
// The main portal daemon discovers this via Portals/atmosphera.portal.
//
// Depends on the D-Bus QML library from https://github.com/alexindigo/dbus-qml
// (or equivalent) for registering D-Bus objects and methods.
//
// TODO: Replace the placeholders below with actual D-Bus bindings once
// the library API is stable.

pragma Singleton
import QtQuick
import Quickshell
import qs.Services.Theming
// import org.freedesktop.DBus          // your D-Bus QML library

QtObject {
  id: root

  // Register on session bus as org.freedesktop.impl.portal.atmosphera
  // and serve Read/ReadAll methods at /org/freedesktop/portal/desktop.

  function handleRead(namespace, key) {
    if (namespace === "org.freedesktop.appearance" && key === "color-scheme") {
      return Settings.data.colorSchemes.darkMode ? 1 : 0;
    }
    return null; // fall through to other backends
  }

  function handleReadAll() {
    return {
      "org.freedesktop.appearance": {
        "color-scheme": Settings.data.colorSchemes.darkMode ? 1 : 0
      }
    };
  }

  // When the user toggles dark/light, emit SettingChanged on
  // org.freedesktop.portal.Settings so listening apps update live.
  Connections {
    target: Settings.data.colorSchemes
    function onDarkModeChanged() {
      // DBusSignal: org.freedesktop.portal.Settings.SettingChanged
      // ("org.freedesktop.appearance", "color-scheme", variant(value))
    }
  }
}
