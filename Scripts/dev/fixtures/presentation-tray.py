"""Bounded private-bus SNI/dbusmenu fixture for presentation sequence tests."""
import dbus
import dbus.service
import dbus.mainloop.glib
import os
from pathlib import Path
from gi.repository import GLib

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName('org.kde.StatusNotifierItem.sequence', bus)
PROPS = 'org.freedesktop.DBus.Properties'
MENU = 'com.canonical.dbusmenu'

class Item(dbus.service.Object):
    def __init__(self, connection, suffix=''):
        self.suffix = suffix
        super().__init__(connection, '/StatusNotifierItem')

    @dbus.service.method(PROPS, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        return {'Category': 'ApplicationStatus', 'Id': 'sequence-tray' + self.suffix, 'Title': 'Sequence Tray' + self.suffix,
                'Status': 'Active', 'IconName': 'applications-system', 'ItemIsMenu': True,
                'Menu': dbus.ObjectPath('/Menu')}

    @dbus.service.method(PROPS, in_signature='ss', out_signature='v')
    def Get(self, interface, key):
        return self.GetAll(interface)[key]

class Menu(dbus.service.Object):
    def __init__(self, connection, suffix=''):
        self.suffix = suffix
        self.gate = Path(os.environ['PRESENTATION_TRAY_GATE_FILE']) if suffix == '-a' else None
        self.ready = self.gate is None or self.gate.exists()
        self.revision = 1
        super().__init__(connection, '/Menu')

    def props(self, ident):
        return {'label': 'Sequence Action' + self.suffix, 'enabled': True, 'visible': True} if ident else {'children-display': 'submenu'}

    @dbus.service.signal(MENU, signature='ui')
    def LayoutUpdated(self, revision, parent):
        pass

    def poll_gate(self):
        ready = self.gate.exists()
        if ready != self.ready:
            self.ready = ready
            self.revision += 1
            self.LayoutUpdated(dbus.UInt32(self.revision), dbus.Int32(0))
        return True

    @dbus.service.method(PROPS, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        return {'Version': dbus.UInt32(4), 'TextDirection': 'ltr', 'Status': 'normal',
                'IconThemePath': dbus.Array([], signature='s')}

    @dbus.service.method(PROPS, in_signature='ss', out_signature='v')
    def Get(self, interface, key):
        return self.GetAll(interface)[key]

    @dbus.service.method(MENU, in_signature='iias', out_signature='u(ia{sv}av)')
    def GetLayout(self, parent, depth, names):
        children = dbus.Array([dbus.Struct((dbus.Int32(1), dbus.Dictionary(self.props(1), signature='sv'),
                                           dbus.Array([], signature='v')), signature='ia{sv}av', variant_level=1)], signature='v') if parent == 0 and self.ready else dbus.Array([], signature='v')
        return dbus.UInt32(self.revision), dbus.Struct((dbus.Int32(parent), dbus.Dictionary(self.props(parent), signature='sv'), children), signature='ia{sv}av')

    @dbus.service.method(MENU, in_signature='aias', out_signature='a(ia{sv})')
    def GetGroupProperties(self, ids, names):
        return [(i, self.props(i)) for i in ids]

    @dbus.service.method(MENU, in_signature='is', out_signature='v')
    def GetProperty(self, ident, key):
        return self.props(ident)[key]

    @dbus.service.method(MENU, in_signature='i', out_signature='b')
    def AboutToShow(self, ident):
        return False

identity_mode = 'PRESENTATION_TRAY_GATE_FILE' in os.environ
item = Item(bus, '-a' if identity_mode else '')
menu = Menu(bus, '-a' if identity_mode else '')
if identity_mode:
    bus_b = dbus.SessionBus(private=True)
    name_b = dbus.service.BusName('org.kde.StatusNotifierItem.sequenceB', bus_b)
    item_b = Item(bus_b, '-b')
    menu_b = Menu(bus_b, '-b')
    GLib.timeout_add(50, menu.poll_gate)

def register():
    try:
        watcher = dbus.Interface(bus.get_object('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher'), 'org.kde.StatusNotifierWatcher')
        watcher.RegisterStatusNotifierItem(name.get_name())
        if identity_mode:
            watcher_b = dbus.Interface(bus_b.get_object('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher'), 'org.kde.StatusNotifierWatcher')
            watcher_b.RegisterStatusNotifierItem(name_b.get_name())
        return False
    except dbus.DBusException:
        return True

loop = GLib.MainLoop()
GLib.timeout_add(100, register)
# The harness/private bus owns this process. No unrelated fixture deadline.
loop.run()
