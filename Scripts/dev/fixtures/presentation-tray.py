"""Bounded private-bus SNI/dbusmenu fixture for presentation sequence tests."""
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName('org.kde.StatusNotifierItem.sequence', bus)
PROPS = 'org.freedesktop.DBus.Properties'
MENU = 'com.canonical.dbusmenu'

class Item(dbus.service.Object):
    @dbus.service.method(PROPS, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        return {'Category': 'ApplicationStatus', 'Id': 'sequence-tray', 'Title': 'Sequence Tray',
                'Status': 'Active', 'IconName': 'applications-system', 'ItemIsMenu': True,
                'Menu': dbus.ObjectPath('/Menu')}

    @dbus.service.method(PROPS, in_signature='ss', out_signature='v')
    def Get(self, interface, key):
        return self.GetAll(interface)[key]

class Menu(dbus.service.Object):
    def props(self, ident):
        return {'label': 'Sequence Action', 'enabled': True, 'visible': True} if ident else {'children-display': 'submenu'}

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
                                           dbus.Array([], signature='v')), signature='ia{sv}av', variant_level=1)], signature='v') if parent == 0 else dbus.Array([], signature='v')
        return dbus.UInt32(1), dbus.Struct((dbus.Int32(parent), dbus.Dictionary(self.props(parent), signature='sv'), children), signature='ia{sv}av')

    @dbus.service.method(MENU, in_signature='aias', out_signature='a(ia{sv})')
    def GetGroupProperties(self, ids, names):
        return [(i, self.props(i)) for i in ids]

    @dbus.service.method(MENU, in_signature='is', out_signature='v')
    def GetProperty(self, ident, key):
        return self.props(ident)[key]

    @dbus.service.method(MENU, in_signature='i', out_signature='b')
    def AboutToShow(self, ident):
        return False

item = Item(bus, '/StatusNotifierItem')
menu = Menu(bus, '/Menu')

def register():
    try:
        watcher = dbus.Interface(bus.get_object('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher'), 'org.kde.StatusNotifierWatcher')
        watcher.RegisterStatusNotifierItem(name.get_name())
        return False
    except dbus.DBusException:
        return True

loop = GLib.MainLoop()
GLib.timeout_add(100, register)
GLib.timeout_add_seconds(100, lambda: (loop.quit(), False)[1])
loop.run()
