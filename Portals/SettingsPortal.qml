// xdg-desktop-portal backend for org.freedesktop.impl.portal.Settings.
//
// Registers on the session bus as
// org.freedesktop.impl.portal.desktop.atmosphera so the portal daemon
// delegates appearance queries to the shell instead of requiring a
// GNOME/GTK/KDE portal package. Discovered via Portals/atmosphera.portal.
//
// Wire-format notes (freedesktop portal spec):
//   - the impl wraps the value in ONE variant layer for every method;
//     the daemon relays it verbatim into frontend ReadOne and adds the
//     second layer itself for deprecated frontend Read
//   - color-scheme payloads are u-typed (libadwaita validates exactly)
//   - SettingChanged carries the new value as a variant (same single wrap)
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

  // null for unknown keys — callers answer per-method.
  function appearanceVariant(key) {
    if (key === "color-scheme")
      return new DBusQML.variant(root.colorSchemeValue(), "u");
    if (key === "accent-color")
      return new DBusQML.variant(root.accentColorValue()); // struct_ payload self-types
    return null;
  }

  DBusAdaptor {
    id: adaptor
    service: "org.freedesktop.impl.portal.desktop.atmosphera"
    path: "/org/freedesktop/portal/desktop"
    captureSubtree: true
    iface: "org.freedesktop.impl.portal.Settings"
    connection: SessionBus

    // Deprecated Read: the impl wraps ONCE — the daemon adds the second
    // variant layer itself for the deprecated frontend Read.
    function read(ns, key) {
      var v = (ns === root.appearanceNamespace) ? root.appearanceVariant(key) : null;
      if (v === null)
        return new DBusQML.variant("");
      return v;
    }

    // ReadOne: single variant on the wire, relayed verbatim by the daemon.
    // Served for interface completeness; the daemon never calls it.
    function readOne(ns, key) {
      var v = (ns === root.appearanceNamespace) ? root.appearanceVariant(key) : null;
      if (v === null)
        return new DBusQML.variant("");
      return v;
    }

    // ReadAll: nested string-keyed dicts of variants — the declared
    // out-signature comes from the dbusqml bundled catalog.
    function readAll(namespaces) {
      var result = {};
      result[root.appearanceNamespace] = {
        "color-scheme": root.appearanceVariant("color-scheme"),
        "accent-color": root.appearanceVariant("accent-color")
      };
      return result;
    }
  }

  Connections {
    target: Settings.data.colorSchemes

    function onDarkModeChanged() {
      adaptor.emitSignal("SettingChanged", [root.appearanceNamespace, "color-scheme", root.appearanceVariant("color-scheme")]);
    }
  }

  Connections {
    target: Color

    function onMPrimaryChanged() {
      adaptor.emitSignal("SettingChanged", [root.appearanceNamespace, "accent-color", root.appearanceVariant("accent-color")]);
    }
  }
}
