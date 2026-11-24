"""Independently authored freedesktop identity and PNG thumbnail fixtures."""
import ctypes
import hashlib
from pathlib import Path
import os
import struct
import zlib

from image_decoding_fixtures import COLORS


def uri(path):
    glib = ctypes.CDLL('libglib-2.0.so.0')
    glib.g_filename_to_uri.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.c_void_p]
    glib.g_filename_to_uri.restype = ctypes.c_void_p
    glib.g_free.argtypes = [ctypes.c_void_p]
    pointer = glib.g_filename_to_uri(os.fsencode(os.path.abspath(path)), None, None)
    assert pointer
    try:
        return ctypes.string_at(pointer).decode('ascii')
    finally:
        glib.g_free(pointer)


def target(root, source, directory='normal'):
    return Path(root) / directory / (hashlib.md5(uri(source).encode('ascii')).hexdigest() + '.png')


def thumbnail(source, color=COLORS[1], depth=8, interlace=0, text='tEXt', size=True, changes=None):
    def chunk(kind, value):
        return struct.pack('!I', len(value)) + kind + value + struct.pack('!I', zlib.crc32(kind + value))
    attributes = {'Thumb::URI': uri(source), 'Thumb::MTime': str(int(source.stat().st_mtime)),
                  'Software': 'Independent GLib thumbnail fixture'}
    if size:
        attributes['Thumb::Size'] = str(source.stat().st_size)
    attributes.update(changes or {})
    chunks = []
    for key, value in attributes.items():
        prefix = key.encode('latin-1') + b'\0'
        if text == 'zTXt':
            payload = prefix + b'\0' + zlib.compress(value.encode('latin-1'))
        elif text == 'iTXt':
            payload = prefix + b'\1\0en\0\0' + zlib.compress(value.encode('utf-8'))
        else:
            payload = prefix + value.encode('latin-1')
        chunks.append(chunk(text.encode('ascii'), payload))
    # 1x1 Adam7 has just the first pass, independently exercising interlace
    # without relying on the product's decoder to author expected pixels.
    rgba = bytes(color) if depth == 8 else struct.pack('!HHHH', *[c * 257 for c in color])
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!IIBBBBB', 1, 1, depth, 6, 0, 0, interlace))
            + b''.join(chunks) + chunk(b'IDAT', zlib.compress(b'\0' + rgba)) + chunk(b'IEND', b''))
