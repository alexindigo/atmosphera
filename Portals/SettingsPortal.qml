// xdg-desktop-portal backend for org.freedesktop.impl.portal.Settings.
//
// Registers on the session bus as
// org.freedesktop.impl.portal.desktop.atmosphera so the portal daemon
// delegates appearance queries to the shell instead of requiring a
// GNOME/GTK/KDE portal package. Discovered via Portals/atmosphera.portal.
//
// Wire-format notes (freedesktop portal spec):
//   - Read (deprecated) wraps the value in TWO variant layers, ReadOne in one
//   - SettingChanged carries the new value as a variant
//   - accent-color is a (ddd) struct, sRGB components in [0,1]
// Reply signatures come from the dbusqml bundled impl.portal.Settings
// catalog; ReadAll marshals as nested string-keyed dicts of variants.
// Requires qt6-dbusqml >= 0.4.0 (struct-in-variant support).
//
// Method names are camelCase because QML forbids uppercase-initial method
// names; dbusqml folds the first character of the PascalCase D-Bus member
// (ReadOne -> readOne) when dispatching.
//
// NOTE: keep curly braces OUT of comments in this file — the quickshell
// qmlscanner mishandles braces inside comments and silently breaks
// singleton instantiation (quickshell bug; observed on quickshell 0.3.1).

pragma Singleton
import DBus 1.0
import DBus 1.0 as DBusQML

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  readonly property string appearanceNamespace: "org.freedesktop.appearance"

  function init() {
    // does nothing but ensure the singleton (and its DBusAdaptor) is created
    // do not remove
    Logger.i("SettingsPortal", "Service started");
  }

  // color-scheme: 0 = no preference, 1 = prefer dark, 2 = prefer light.
  // The shell always has a concrete scheme, so report an explicit choice.
  function colorSchemeValue() {
    return Settings.data.colorSchemes.darkMode ? 1 : 2;
  }

  // accent-color: (ddd) sRGB triple, each component in [0,1].
  function accentColorValue() {
    return new DBusQML.struct_([Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b]);
  }

  // undefined for unknown keys — callers wrap per-method.
  function appearanceValue(key) {
    if (key === "color-scheme")
      return root.colorSchemeValue();
    if (key === "accent-color")
      return root.accentColorValue();
    return undefined;
  }

  DBusAdaptor {
    id: adaptor
    service: "org.freedesktop.impl.portal.desktop.atmosphera"
    path: "/org/freedesktop/portal/desktop"
    iface: "org.freedesktop.impl.portal.Settings"
    connection: SessionBus

    // Deprecated Read: variant-in-variant on the wire
    function read(ns, key) {
      var value = (ns === root.appearanceNamespace) ? root.appearanceValue(key) : undefined;
      if (value === undefined)
        return new DBusQML.variant(new DBusQML.variant(""));
      return new DBusQML.variant(new DBusQML.variant(value));
    }

    // ReadOne: single variant on the wire
    function readOne(ns, key) {
      var value = (ns === root.appearanceNamespace) ? root.appearanceValue(key) : undefined;
      if (value === undefined)
        return new DBusQML.variant("");
      return new DBusQML.variant(value);
    }

    // ReadAll: nested string-keyed dicts of variants — the declared
    // out-signature comes from the dbusqml bundled catalog.
    function readAll(namespaces) {
      var result = {};
      result[root.appearanceNamespace] = {
        "color-scheme": new DBusQML.variant(root.colorSchemeValue()),
        "accent-color": new DBusQML.variant(root.accentColorValue())
      };
      return result;
    }
  }

  Connections {
    target: Settings.data.colorSchemes

    function onDarkModeChanged() {
      adaptor.emitSignal("SettingChanged", [root.appearanceNamespace, "color-scheme", new DBusQML.variant(root.colorSchemeValue())]);
    }
  }

  Connections {
    target: Color

    function onMPrimaryChanged() {
      adaptor.emitSignal("SettingChanged", [root.appearanceNamespace, "accent-color", new DBusQML.variant(root.accentColorValue())]);
    }
  }
}
