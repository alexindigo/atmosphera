"""Complete PNG validation, pixel reconstruction and freedesktop metadata.

The decoder's exit code is not validation. In addition to CRC/chunk integrity,
reconstruct every noninterlaced 8-bit row, including all PNG predictors. This
independent reader accepts the explicit PNG32 outputs emitted by our decoders.
"""
import hashlib
import os
from pathlib import Path
import struct
import tempfile
from urllib.parse import quote_from_bytes
import zlib

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
    if not data.startswith(PNG):
        raise ValueError('Invalid PNG signature')
    offset, kinds = 8, []
    while offset + 12 <= len(data):
        length = struct.unpack_from('!I', data, offset)[0]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError('Truncated PNG')
        kind, content = data[offset + 4:offset + 8], data[offset + 8:end - 4]
        if struct.unpack_from('!I', data, end - 4)[0] != zlib.crc32(kind + content):
            raise ValueError('Invalid PNG CRC')
        kinds.append(kind)
        yield kind, content
        offset = end
        if kind == b'IEND':
            if content or kinds[0] != b'IHDR' or kinds.count(b'IHDR') != 1 or b'IDAT' not in kinds or offset != len(data):
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
            buffer.extend(decoder.decompress(value))
            consume()
    buffer.extend(decoder.flush())
    consume()
    if not decoder.eof or decoder.unused_data or buffer or rows != height:
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


def atomic_write(path, data, root):
    root = Path(root)
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    folder = root
    folder.chmod(0o700)
    for part in path.parent.relative_to(root).parts:
        folder = folder / part
        folder.mkdir(mode=0o700, exist_ok=True)
        folder.chmod(0o700)
    fd, temporary = tempfile.mkstemp(prefix='.atmosphera-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)
