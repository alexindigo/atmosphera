#!/usr/bin/env python3
"""Controlled NM protocol peer. Only launched on a private guest bus."""
import argparse
import json
import os
from pathlib import Path
import time

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

NM = "org.freedesktop.NetworkManager"
ROOT = "/org/freedesktop/NetworkManager"
PROPS = "org.freedesktop.DBus.Properties"
TEST = "dev.atmosphera.NmFixture"


def variant(signature, value):
    if signature == "aa{sv}":
        value = [{k: GLib.Variant("s", v) if isinstance(v, str) else GLib.Variant("u", v)
                  for k, v in row.items()} for row in value]
    return GLib.Variant(signature, value)


class Fixture:
    def __init__(self, ready):
        assert os.environ["DBUS_SYSTEM_BUS_ADDRESS"] == os.environ["DBUS_SESSION_BUS_ADDRESS"]
        assert os.environ["DBUS_SESSION_BUS_ADDRESS"].startswith("unix:path=/home/tester/Projects/nm-events/")
        self.address = os.environ["DBUS_SESSION_BUS_ADDRESS"]
        self.control_bus = self.connection()
        self.bus = self.connection()
        self.calls = []
        self.objects = {}
        self.registrations = {}
        self.delayed = set()
        self.held = []
        self.denied = set()
        self.options = {"activation": "pending", "activationReply": "normal", "scan": "pending"}
        self.active_serial = 0
        self.register_control()
        self.claim(self.control_bus, TEST)
        self.claim(self.bus, NM)
        self.put(ROOT, NM, {"Devices": ("ao", []), "ActiveConnections": ("ao", []),
                           "Connectivity": ("u", 4), "WirelessEnabled": ("b", True)})
        self.put(ROOT + "/Settings", NM + ".Settings", {})
        self.put(ROOT + "/Settings/1", NM + ".Settings.Connection", {}, settings={
            "connection": {"uuid": "fixture-uuid", "id": "Initial", "type": "wireguard"}})
        ready.write_text(self.bus.get_unique_name())

    def connection(self):
        return Gio.DBusConnection.new_for_address_sync(self.address,
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None, None)

    def claim(self, connection, name):
        connection.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                             "RequestName", GLib.Variant("(su)", (name, 4)), None,
                             Gio.DBusCallFlags.NONE, 3000, None)

    def register_control(self):
        xml = f'<node><interface name="{TEST}"><method name="Control"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="out"/></method></interface></node>'
        info = Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0]
        self.control_bus.register_object("/fixture", info, self.control, None, None)

    def control(self, _connection, _sender, _path, _iface, _method, parameters, invocation):
        action, encoded = parameters.unpack()
        values = json.loads(encoded)
        try:
            result = self.perform(action, values)
            invocation.return_value(GLib.Variant("(s)", (json.dumps(result),)))
        except Exception as error:
            invocation.return_dbus_error(TEST + ".Error", str(error))

    def perform(self, action, values):
        if action == "calls":
            return self.calls
        if action == "configure":
            self.options.update(values)
            return self.options
        if action in ("restart", "lose", "appear"):
            if action != "appear":
                self.bus.close_sync(None)
            if action != "lose":
                objects = self.objects
                self.objects, self.registrations = {}, {}
                self.bus = self.connection()
                for (path, iface), obj in objects.items():
                    self.put(path, iface, obj["props"], settings=obj["settings"], introspect=obj["introspect"])
                self.claim(self.bus, NM)
            return self.bus.get_unique_name()
        if action == "change":
            path, iface = values["path"], values["iface"]
            obj = self.objects[(path, iface)]
            changed = {}
            for name, value in values.get("props", {}).items():
                signature = obj["props"][name][0]
                obj["props"][name] = (signature, value)
                changed[name] = variant(signature, value)
            invalidated = values.get("invalidated", [])
            self.emit(path, PROPS, "PropertiesChanged", "(sa{sv}as)", (iface, changed, invalidated))
            return True
        if action == "signal":
            if values["member"] == "StateChanged" and (values["path"], values["iface"]) in self.objects:
                self.objects[(values["path"], values["iface"])]["props"]["State"] = ("u", values["args"][0])
            self.emit(values["path"], values["iface"], values["member"],
                      values.get("signature", "()"), tuple(values.get("args", [])))
            return True
        if action == "settings":
            obj = self.objects[(values["path"], NM + ".Settings.Connection")]
            obj["settings"] = values["settings"]
            self.emit(values["path"], NM + ".Settings.Connection", "Updated", "()", ())
            return True
        if action == "delay":
            self.delayed.add((values["path"], values["method"]))
            return True
        if action == "release":
            held, self.held = self.held, []
            self.delayed.clear()
            for invocation, signature, result in held:
                invocation.return_value(GLib.Variant(signature, result))
            return len(held)
        if action == "deny":
            self.denied.add((values["path"], values["method"]))
            return True
        if action == "allow":
            self.denied.discard((values["path"], values["method"]))
            return True
        if action == "put":
            self.put(values["path"], values["iface"], {k: tuple(v) for k, v in values.get("props", {}).items()},
                     settings=values.get("settings"), introspect=values.get("introspect", True))
            return True
        if action == "remove":
            path = values["path"]
            for key in list(self.objects):
                if key[0] == path:
                    self.bus.unregister_object(self.registrations.pop(key))
                    del self.objects[key]
            self.emit(path, NM + ".Settings.Connection", "Removed", "()", ())
            self.emit(ROOT + "/Settings", NM + ".Settings", "ConnectionRemoved", "(o)", (path,))
            return True
        raise ValueError("unknown action " + action)

    def emit(self, path, iface, member, signature, args):
        self.bus.emit_signal(None, path, iface, member, GLib.Variant(signature, args))

    def put(self, path, iface, props, settings=None, introspect=True):
        key = (path, iface)
        assert key not in self.objects
        self.objects[key] = dict(props=props, settings=settings, introspect=introspect)
        methods = ""
        signals = ""
        if iface == NM:
            methods = '<method name="ActivateConnection"><arg type="o" direction="in"/><arg type="o" direction="in"/><arg type="o" direction="in"/><arg type="o" direction="out"/></method><method name="DeactivateConnection"><arg type="o" direction="in"/></method><method name="AddAndActivateConnection"><arg type="a{sa{sv}}" direction="in"/><arg type="o" direction="in"/><arg type="o" direction="in"/><arg type="o" direction="out"/><arg type="o" direction="out"/></method>'
            signals = '<signal name="DeviceAdded"><arg type="o"/></signal><signal name="DeviceRemoved"><arg type="o"/></signal>'
        elif iface == NM + ".Settings":
            methods = '<method name="ListConnections"><arg type="ao" direction="out"/></method>'
            signals = '<signal name="NewConnection"><arg type="o"/></signal><signal name="ConnectionRemoved"><arg type="o"/></signal>'
        elif iface == NM + ".Settings.Connection":
            methods = '<method name="GetSettings"><arg type="a{sa{sv}}" direction="out"/></method><method name="Delete"/>'
            signals = '<signal name="Updated"/><signal name="Removed"/>'
        elif iface == NM + ".Connection.Active":
            signals = '<signal name="StateChanged"><arg type="u"/><arg type="u"/></signal>'
        elif iface == NM + ".Device.Wireless":
            methods = '<method name="GetAllAccessPoints"><arg type="ao" direction="out"/></method><method name="RequestScan"><arg type="a{sv}" direction="in"/></method>'
            signals = '<signal name="AccessPointAdded"><arg type="o"/></signal><signal name="AccessPointRemoved"><arg type="o"/></signal>'
        xml = f'<node><interface name="{iface}">{methods}{signals}'
        xml += ''.join(f'<property name="{name}" type="{signature}" access="readwrite"/>' for name, (signature, _) in props.items())
        xml += '</interface></node>'
        info = Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0]
        self.registrations[key] = self.bus.register_object(path, info, self.method, self.get, self.set)
        if (path, PROPS) not in self.registrations:
            xml = f'<node><interface name="{PROPS}"><method name="GetAll"><arg type="s" direction="in"/><arg type="a{{sv}}" direction="out"/></method><method name="Get"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method><method name="Set"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/></method><signal name="PropertiesChanged"><arg type="s"/><arg type="a{{sv}}"/><arg type="as"/></signal></interface></node>'
            info = Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0]
            self.registrations[(path, PROPS)] = self.bus.register_object(path, info, self.method, None, None)
        if not introspect and (path, "org.freedesktop.DBus.Introspectable") not in self.registrations:
            info = Gio.DBusNodeInfo.new_for_xml('<node><interface name="org.freedesktop.DBus.Introspectable"><method name="Introspect"><arg type="s" direction="out"/></method></interface></node>').interfaces[0]
            self.registrations[(path, "org.freedesktop.DBus.Introspectable")] = self.bus.register_object(path, info, self.method, None, None)

    def get(self, _bus, sender, path, iface, name):
        self.calls.append(dict(sender=sender, path=path, iface=iface, method="Get", property=name))
        signature, value = self.objects[(path, iface)]["props"][name]
        return variant(signature, value)

    def set(self, _bus, _sender, path, iface, name, value):
        signature = self.objects[(path, iface)]["props"][name][0]
        self.objects[(path, iface)]["props"][name] = (signature, value.unpack())
        self.emit(path, PROPS, "PropertiesChanged", "(sa{sv}as)", (iface, {name: value}, []))
        return True

    def method(self, _bus, sender, path, iface, member, parameters, invocation):
        self.calls.append(dict(sender=sender, path=path, iface=iface, method=member, monotonic=time.monotonic()))
        if member == "AddAndActivateConnection":
            # This daemon accepts synthetic fixture inputs only, never real
            # credentials. Retain the wire-decoded values and variant types so
            # enterprise/hidden-network marshalling is actually observed.
            settings, device, specific = parameters.unpack()
            variants = parameters.get_child_value(0)
            types = {}
            for index in range(variants.n_children()):
                section = variants.get_child_value(index)
                name = section.get_child_value(0).get_string()
                fields = section.get_child_value(1)
                types[name] = {fields.get_child_value(i).get_child_value(0).get_string():
                               fields.get_child_value(i).get_child_value(1).get_variant().get_type_string()
                               for i in range(fields.n_children())}
            self.calls[-1].update(settings=settings, device=device, specific=specific, variantTypes=types)
        if iface == "org.freedesktop.DBus.Introspectable":
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", "Child rejects introspection")
            return
        if (path, member) in self.denied:
            invocation.return_dbus_error(NM + ".PermissionDenied", "Permission denied")
            return
        if iface == PROPS:
            args = parameters.unpack()
            obj = self.objects[(path, args[0])]
            if member == "GetAll":
                signature, result = "(a{sv})", ({name: variant(s, v) for name, (s, v) in obj["props"].items()},)
            elif member == "Get":
                self.calls[-1]["property"] = args[1]
                s, v = obj["props"][args[1]]
                signature, result = "(v)", (variant(s, v),)
            elif member == "Set":
                s = obj["props"][args[1]][0]
                obj["props"][args[1]] = (s, args[2])
                self.emit(path, PROPS, "PropertiesChanged", "(sa{sv}as)", (args[0], {args[1]: GLib.Variant(s, args[2])}, []))
                signature, result = "()", ()
        elif member == "ListConnections":
            signature, result = "(ao)", ([p for p, i in self.objects if i == NM + ".Settings.Connection"],)
        elif member == "GetSettings":
            settings = self.objects[(path, iface)]["settings"]
            signature = "(a{sa{sv}})"
            result = ({section: {k: GLib.Variant("s", v) if isinstance(v, str) else GLib.Variant("ay", v)
                                  for k, v in fields.items()} for section, fields in settings.items()},)
        elif member == "GetAllAccessPoints":
            signature, result = "(ao)", (self.objects[(path, iface)]["props"].get("AccessPoints", ("ao", []))[1],)
        elif member == "ActivateConnection":
            self.active_serial += 1
            active_path = ROOT + "/ActiveConnection/" + str(self.active_serial)
            profile_path = parameters.unpack()[0]
            profile = self.objects[(profile_path, NM + ".Settings.Connection")]["settings"]["connection"]
            self.put(active_path, NM + ".Connection.Active", {"Id": ("s", profile["id"]), "Uuid": ("s", profile["uuid"]),
                "Type": ("s", profile["type"]), "Connection": ("o", profile_path), "Devices": ("ao", []), "State": ("u", 1),
                "Ip4Config": ("o", "/"), "Ip6Config": ("o", "/")}, introspect=False)
            paths = self.objects[(ROOT, NM)]["props"]["ActiveConnections"][1] + [active_path]
            self.perform("change", dict(path=ROOT, iface=NM, props={"ActiveConnections": paths}))
            if self.options["activation"] in ("success", "failure"):
                state = 2 if self.options["activation"] == "success" else 4
                self.perform("signal", dict(path=active_path, iface=NM + ".Connection.Active", member="StateChanged", signature="(uu)", args=[state, 9 if state == 4 else 0]))
            signature, result = "(o)", (active_path,)
            if self.options["activationReply"] == "hold":
                self.held.append((invocation, signature, result))
                return
        elif member == "DeactivateConnection":
            active_path = parameters.unpack()[0]
            self.perform("signal", dict(path=active_path, iface=NM + ".Connection.Active", member="StateChanged", signature="(uu)", args=[4, 0]))
            paths = [p for p in self.objects[(ROOT, NM)]["props"]["ActiveConnections"][1] if p != active_path]
            self.perform("change", dict(path=ROOT, iface=NM, props={"ActiveConnections": paths}))
            signature, result = "()", ()
        elif member == "Delete":
            signature, result = "()", ()
            self.perform("remove", dict(path=path))
        elif member == "RequestScan":
            if self.options["scan"] == "before-reply":
                last = self.objects[(path, iface)]["props"]["LastScan"][1]
                self.perform("change", dict(path=path, iface=iface, props={"LastScan": last + 1}))
            signature, result = "()", ()
        else:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", member)
            return
        if (path, member) in self.delayed:
            self.held.append((invocation, signature, result))
        else:
            invocation.return_value(GLib.Variant(signature, result))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ready", type=Path, required=True)
    args = parser.parse_args()
    fixture = Fixture(args.ready)
    GLib.MainLoop().run()
