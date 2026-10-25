"""Native GTK Wayland clipboard consumer, driven only by actual paste keys."""
import base64
import hashlib
import json
from pathlib import Path
import sys
import time
import gi

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib, GdkPixbuf

output = Path(sys.argv[1])
window = Gtk.Window(title=sys.argv[2] if len(sys.argv) > 2 else 'Launcher Paste Target')
window.set_default_size(500, 300)
column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
entry = Gtk.Entry()
image = Gtk.Image()
column.pack_start(entry, False, False, 0)
column.pack_start(image, True, True, 0)
window.add(column)
records = []
pending = 0
clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
def key(widget, event):
    global pending
    if not (int(event.state) & int(Gdk.ModifierType.CONTROL_MASK)) or Gdk.keyval_to_lower(event.keyval) != Gdk.KEY_v:
        return False
    pending += 1
    record = dict(key_at=time.time() * 1000, active_at_key=window.is_active(), focused_at_key=entry.has_focus())
    def text_received(selection, text, data):
        global pending
        entry.set_text(entry.get_text() + (text or ''))
        records.append(dict(record, kind='text', text=text, consumer_text=entry.get_text()))
        pending -= 1
    def image_received(selection, data, user_data):
        global pending
        raw = bytes(data.get_data() or b'')
        loader = GdkPixbuf.PixbufLoader.new_with_type('png')
        loader.write(raw)
        loader.close()
        pixbuf = loader.get_pixbuf()
        image.set_from_pixbuf(pixbuf)
        records.append(dict(record, kind='image', sha256=hashlib.sha256(raw).hexdigest(),
                            bytes=len(raw), width=pixbuf.get_width(), height=pixbuf.get_height()))
        pending -= 1
    if int(event.state) & int(Gdk.ModifierType.SHIFT_MASK):
        clipboard.request_text(text_received, None)
    else:
        clipboard.request_contents(Gdk.Atom.intern('image/png', False), image_received, None)
    return True
entry.connect('key-press-event', key)
window.connect('destroy', Gtk.main_quit)
def tick():
    state = dict(active=window.is_active(), focused=entry.has_focus(), text=entry.get_text(), pending=pending,
                 records=records, display=Gdk.Display.get_default().__gtype__.name)
    staged = output / 'state.pending'
    staged.write_text(json.dumps(state, indent=2, ensure_ascii=False))
    staged.replace(output / 'state.json')
    if (output / 'exit-request').exists():
        window.destroy()
        return False
    return True
window.show_all()
entry.grab_focus()
GLib.timeout_add(40, tick)
Gtk.main()
