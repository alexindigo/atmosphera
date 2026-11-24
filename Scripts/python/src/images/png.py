"""Complete PNG validation, pixel reconstruction and freedesktop metadata.

The decoder's exit code is not validation. In addition to CRC/chunk integrity,
reconstruct every noninterlaced 8-bit row, including all PNG predictors. This
independent reader accepts the explicit PNG32 outputs emitted by our decoders.
"""
import hashlib
import os
from pathlib import Path
import struct
from urllib.parse import quote_from_bytes
import zlib

from .storage import atomic_write

PNG = b'\x89PNG\r\n\x1a\n'
BUCKETS = ((128, 'normal'), (256, 'large'), (512, 'x-large'), (1024, 'xx-large'))
LIMIT = 16 * 1024 * 1024  # Compatibility constant for the old video adapter.


def bucket(pixels):
    return next((pair for pair in BUCKETS if pair[0] >= pixels), BUCKETS[-1])


def canonical_uri(path):
    return 'file://' + quote_from_bytes(os.fsencode(os.path.abspath(path)), safe="/!$&'()*+,=:@~")


def cache_name(uri):
    return hashlib.md5(uri.encode('utf-8'), usedforsecurity=False).hexdigest() + '.png'


def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))


def png_chunks(data):
    if data[:8] != PNG:
        raise ValueError('Invalid PNG signature')
    offset, first, seen_data, data_ended = 8, True, False, False
    while offset + 12 <= len(data):
        length = struct.unpack_from('!I', data, offset)[0]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError('Truncated PNG')
        kind, content = bytes(data[offset + 4:offset + 8]), data[offset + 8:end - 4]
        if struct.unpack_from('!I', data, end - 4)[0] != zlib.crc32(content, zlib.crc32(kind)):
            raise ValueError('Invalid PNG CRC')
        if (first and kind != b'IHDR') or (kind == b'IHDR' and (not first or length != 13)):
            raise ValueError('Invalid PNG header')
        if kind == b'IDAT':
            if data_ended:
                raise ValueError('Nonconsecutive PNG image data')
            seen_data = True
        elif seen_data:
            data_ended = True
        first = False
        yield kind, content
        offset = end
        if kind == b'IEND':
            if content or not seen_data or offset != len(data):
                raise ValueError('Invalid PNG structure')
            return
    raise ValueError('Missing PNG end')


def validate(data, maximum=None):
    parts = list(png_chunks(data))
    width, height, depth, mode, compression, filtering, interlace = struct.unpack('!IIBBBBB', parts[0][1])
    if not width or not height or depth != 8 or mode not in (0, 2, 3, 4, 6) or compression or filtering or interlace:
        raise ValueError('Unsupported or invalid PNG encoding')
    if maximum and (width > maximum[0] or height > maximum[1]):
        raise ValueError('PNG exceeds the requested representation dimensions')
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[mode]
    palettes = [value for kind, value in parts if kind == b'PLTE']
    palette = palettes[0] if palettes else None
    if mode == 3 and (not palette or len(palette) % 3 or len(palette) > 768):
        raise ValueError('Invalid PNG palette')
    stride, previous, buffer, rows = width * channels, bytearray(width * channels), bytearray(), 0
    decoder = zlib.decompressobj()
    def consume():
        nonlocal rows, previous, buffer
        while len(buffer) >= stride + 1:
            filter_kind, row = buffer[0], bytearray(buffer[1:stride + 1])
            del buffer[:stride + 1]
            if filter_kind > 4:
                raise ValueError('Invalid PNG row filter')
            for x in range(stride):
                left, up, corner = row[x - channels] if x >= channels else 0, previous[x], previous[x - channels] if x >= channels else 0
                if filter_kind == 1:
                    predictor = left
                elif filter_kind == 2:
                    predictor = up
                elif filter_kind == 3:
                    predictor = (left + up) // 2
                elif filter_kind == 4:
                    p = left + up - corner
                    distances = (abs(p - left), abs(p - up), abs(p - corner))
                    predictor = (left, up, corner)[distances.index(min(distances))]
                else:
                    predictor = 0
                row[x] = (row[x] + predictor) & 255
            if mode == 3 and any(index * 3 >= len(palette) for index in row):
                raise ValueError('Invalid PNG palette index')
            previous = row
            rows += 1
            if rows > height:
                raise ValueError('Excess PNG scanlines')
    for kind, value in parts:
        if kind == b'IDAT':
            while value:
                if decoder.eof:
                    raise ValueError('Unexpected data after PNG pixel stream')
                # The declared scanlines, not compressed input size, bound every
                # inflation allocation. One extra byte detects excess pixels.
                remaining = (height - rows) * (stride + 1) - len(buffer)
                try:
                    inflated = decoder.decompress(value, min(65536, remaining + 1))
                except zlib.error as error:
                    raise ValueError('Invalid PNG compression') from error
                if len(inflated) > remaining:
                    raise ValueError('Excess PNG scanlines')
                buffer.extend(inflated)
                consume()
                if decoder.eof:
                    if decoder.unused_data or decoder.unconsumed_tail:
                        raise ValueError('Unexpected data after PNG pixel stream')
                    break
                value = decoder.unconsumed_tail
    if not decoder.eof or buffer or rows != height:
        raise ValueError('Incomplete PNG pixel stream')
    return dict(format='png', width=width, height=height, frames=1, animated=False, delaysMs=[], loop=None)


def metadata(data):
    values = {}
    for kind, content in png_chunks(data):
        if kind not in (b'tEXt', b'zTXt', b'iTXt'):
            continue
        key, value = content.split(b'\0', 1)
        if not 1 <= len(key) <= 79 or key.decode('latin-1') in values:
            raise ValueError('Invalid or duplicate PNG text keyword')
        encoding = 'latin-1'
        if kind == b'zTXt':
            if value[:1] != b'\0':
                raise ValueError('Invalid PNG text compression')
            value = zlib.decompress(value[1:])
        elif kind == b'iTXt':
            compressed, method = value[:2]
            if compressed not in (0, 1) or method:
                raise ValueError('Invalid PNG international text compression')
            language, translated, value = value[2:].split(b'\0', 2)
            language.decode('ascii')
            translated.decode('utf-8')
            value = zlib.decompress(value) if compressed else value
            encoding = 'utf-8'
        values[key.decode('latin-1')] = value.decode(encoding)
    return values


def with_metadata(data, attributes):
    parts = list(png_chunks(data))
    # Replace existing attributes rather than author ambiguous duplicate keys.
    return PNG + b''.join(chunk(kind, content) for kind, content in parts[:-1]
        if kind not in (b'tEXt', b'zTXt', b'iTXt') or content.split(b'\0', 1)[0].decode('latin-1') not in attributes) + b''.join(
        chunk(b'tEXt', key.encode('latin-1') + b'\0' + value.encode('latin-1'))
        for key, value in attributes.items()) + chunk(b'IEND', b'')


def empty_png():
    return PNG + chunk(b'IHDR', struct.pack('!IIBBBBB', 1, 1, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b'\0\0\0\0\0')) + chunk(b'IEND', b'')
