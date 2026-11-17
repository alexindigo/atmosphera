"""Guest-side RFB observation/input for the exact VM's local-only VNC console.

Ark only forwards its named fork's loopback VNC port over pinned guest SSH.
Pixels come from the VM console, never compositor screencopy or the host desktop.
"""
import os
from pathlib import Path
import socket
import struct
import time


class Framebuffer:
    def __init__(self):
        port = int(os.environ['LOCKER_FRAMEBUFFER_PORT'])
        expected = os.environ['LOCKER_TEST_VM_NAME']
        self.socket = socket.create_connection(('127.0.0.1', port), timeout=8)
        assert self.read(12).startswith(b'RFB 003.'), 'unexpected console protocol'
        self.socket.sendall(b'RFB 003.008\n')
        security = self.read(self.read(1)[0])
        assert 1 in security, 'console authentication route differs from fixture'
        self.socket.sendall(b'\1')
        assert self.read(4) == b'\0\0\0\0'
        self.socket.sendall(b'\1')
        header = self.read(24)
        self.width, self.height = struct.unpack('>HH', header[:4])
        self.name = self.read(struct.unpack('>I', header[20:])[0]).decode()
        assert self.name == 'QEMU (' + expected + ')', 'wrong VM framebuffer'
        pixel = struct.pack('>BBBBHHHBBBxxx', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
        self.socket.sendall(b'\0\0\0\0' + pixel)
        self.socket.sendall(b'\2\0\0\1' + struct.pack('>i', 0))

    def read(self, count):
        value = bytearray()
        while len(value) < count:
            chunk = self.socket.recv(count - len(value))
            if not chunk:
                raise EOFError('VM console closed')
            value.extend(chunk)
        return bytes(value)

    def capture(self, path):
        self.socket.sendall(struct.pack('>BBHHHH', 3, 0, 0, 0, self.width, self.height))
        assert self.read(1) == b'\0'
        rectangles = struct.unpack('>xH', self.read(3))[0]
        assert rectangles, 'console returned no framebuffer rectangles'
        frame = bytearray(self.width * self.height * 3)
        covered = 0
        for _ in range(rectangles):
            x, y, width, height, encoding = struct.unpack('>HHHHi', self.read(12))
            assert encoding == 0, 'console did not honor raw framebuffer encoding'
            assert x + width <= self.width and y + height <= self.height
            covered += width * height
            data = self.read(width * height * 4)
            for yy in range(height):
                row = data[yy * width * 4:(yy + 1) * width * 4]
                rgb = bytearray(width * 3)
                rgb[0::3], rgb[1::3], rgb[2::3] = row[2::4], row[1::4], row[0::4]
                offset = ((y + yy) * self.width + x) * 3
                frame[offset:offset + len(rgb)] = rgb
        assert covered == self.width * self.height, 'nonincremental capture did not cover the whole framebuffer'
        self.pixels = frame
        Path(path).write_bytes(f'P6\n{self.width} {self.height}\n255\n'.encode() + frame)

    def sentinel_corners(self):
        return [self.pixels[((y * self.width) + x) * 3:((y * self.width) + x) * 3 + 3] == b'\xff\x00\xff'
                for x, y in ((16, 16), (self.width - 17, 16), (16, self.height - 17),
                             (self.width - 17, self.height - 17))]

    def sentinel_visible(self):
        return b'\xff\x00\xff' * 8 in self.pixels

    def click(self, x, y):
        assert 0 <= x < self.width and 0 <= y < self.height
        self.socket.sendall(struct.pack('>BBHH', 5, 1, x, y))
        self.socket.sendall(struct.pack('>BBHH', 5, 0, x, y))
        time.sleep(.15)

    def chord(self, *keysyms):
        # RFC 6143 section 7.5.4: KeyEvent is type/down/pad/X11 keysym.
        # This reaches QEMU's emulated keyboard, including compositor binds;
        # a Wayland virtual keyboard can depend on an existing focused client.
        pressed = []
        try:
            for keysym in keysyms:
                self.socket.sendall(struct.pack('>BBHI', 4, 1, 0, keysym))
                pressed.append(keysym)
            time.sleep(.1)
        finally:
            for keysym in reversed(pressed):
                self.socket.sendall(struct.pack('>BBHI', 4, 0, 0, keysym))

    def close(self):
        self.socket.close()
