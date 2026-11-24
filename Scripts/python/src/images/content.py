"""Content-derived frame declarations, never suffix-based decoder claims."""
import math
import mmap
from pathlib import Path
import re
import struct
from xml.etree import ElementTree

from .png import png_chunks


def webp(data):
    if data[:4] != b'RIFF' or data[8:12] != b'WEBP' or len(data) < 12:
        raise ValueError('Not a WebP container')
    if struct.unpack_from('<I', data, 4)[0] + 8 != len(data):
        raise ValueError('Incomplete WebP container')
    offset, frames, loop, width, height = 12, [], None, 0, 0
    def uint24(value):
        return int.from_bytes(value, 'little')
    while offset + 8 <= len(data):
        kind, length = data[offset:offset + 4], struct.unpack_from('<I', data, offset + 4)[0]
        payload = data[offset + 8:offset + 8 + length]
        if len(payload) != length:
            raise ValueError('Truncated WebP chunk')
        if kind == b'VP8X' and len(payload) == 10:
            width, height = uint24(payload[4:7]) + 1, uint24(payload[7:10]) + 1
        elif kind == b'ANIM' and len(payload) == 6:
            loop = struct.unpack_from('<H', payload, 4)[0]
        elif kind == b'ANMF':
            if len(payload) < 16:
                raise ValueError('Truncated WebP frame')
            frames.append(dict(delayMs=uint24(payload[12:15]), disposal=payload[15] & 1,
                               x=2 * uint24(payload[:3]), y=2 * uint24(payload[3:6]),
                               width=uint24(payload[6:9]) + 1, height=uint24(payload[9:12]) + 1))
        elif kind == b'VP8L' and len(payload) >= 5 and payload[0] == 0x2f:
            bits = int.from_bytes(payload[1:5], 'little')
            width, height = (bits & 0x3fff) + 1, ((bits >> 14) & 0x3fff) + 1
        elif kind == b'VP8 ' and len(payload) >= 10 and payload[3:6] == b'\x9d\x01\x2a':
            width, height = struct.unpack_from('<HH', payload, 6)
            width, height = width & 0x3fff, height & 0x3fff
        offset += 8 + length + length % 2
    if offset != len(data) or not width or not height:
        raise ValueError('Invalid WebP dimensions or chunks')
    return dict(format='webp', width=width, height=height, frames=len(frames) or 1, animated=len(frames) > 1,
                delaysMs=[f['delayMs'] for f in frames], loop=loop, frameInfo=frames)


def gif(data):
    if len(data) < 14 or data[:6] not in (b'GIF87a', b'GIF89a'):
        raise ValueError('Not a GIF')
    width, height = struct.unpack_from('<HH', data, 6)
    if not width or not height:
        raise ValueError('Invalid GIF size')
    packed, offset = data[10], 13
    if packed & 128:
        offset += 3 * (1 << ((packed & 7) + 1))
    frames, delays, disposals, loop, delay, disposal = 0, [], [], None, 0, 0
    def blocks(position, capture=0):
        content = bytearray()
        count = 0
        while position < len(data):
            size = data[position]
            position += 1
            if not size:
                return position, content, count
            if position + size > len(data):
                raise ValueError('Truncated GIF block')
            content.extend(data[position:position + min(size, max(0, capture - len(content)))])
            count += size
            position += size
        raise ValueError('Unterminated GIF blocks')
    while offset < len(data):
        marker = data[offset]
        offset += 1
        if marker == 0x3b:
            if offset != len(data) or not frames:
                raise ValueError('Invalid GIF trailer')
            return dict(format='gif', width=width, height=height, frames=frames, animated=frames > 1,
                        delaysMs=delays, loop=loop, disposals=disposals)
        if marker == 0x21:
            if offset >= len(data):
                raise ValueError('Truncated GIF extension')
            label = data[offset]
            offset += 1
            offset, value, count = blocks(offset, 15)
            if label == 0xf9:
                if count != 4:
                    raise ValueError('Invalid GIF frame control')
                delay, disposal = struct.unpack_from('<H', value, 1)[0] * 10, (value[0] >> 2) & 7
            elif label == 0xff and value[:11] in (b'NETSCAPE2.0', b'ANIMEXTS1.0'):
                if count != 14 or value[11] != 1:
                    raise ValueError('Invalid GIF loop control')
                loop = struct.unpack_from('<H', value, 12)[0]
        elif marker == 0x2c:
            if offset + 9 >= len(data):
                raise ValueError('Truncated GIF image')
            left, top, frame_width, frame_height = struct.unpack_from('<HHHH', data, offset)
            flags = data[offset + 8]
            if not frame_width or not frame_height or left + frame_width > width or top + frame_height > height:
                raise ValueError('Invalid GIF frame bounds')
            offset += 9
            if flags & 128:
                offset += 3 * (1 << ((flags & 7) + 1))
            if offset >= len(data) or not 2 <= data[offset] <= 8:
                raise ValueError('Invalid GIF LZW size')
            offset, content, count = blocks(offset + 1)
            if not count:
                raise ValueError('Empty GIF frame')
            frames += 1
            delays.append(delay)
            disposals.append(disposal)
            delay, disposal = 0, 0
        else:
            raise ValueError('Invalid GIF block marker')
    raise ValueError('Missing GIF trailer')


SVG_LENGTH = re.compile(r'\s*([0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)\s*(px)?\s*$')


def svg(data):
    """Intrinsic size from the root element only; SVG is a still document.

    Returns None when the declaration cannot be read cheaply (compressed SVG,
    relative units, no viewBox) so that the independent decoder inspects it.
    """
    return svg_chunks(data[offset:offset + 4096] for offset in range(0, len(data), 4096))


def svg_chunks(chunks):
    parser = ElementTree.XMLPullParser(events=('start',))
    try:
        for block in chunks:
            parser.feed(block)
            root = next((element for _, element in parser.read_events()), None)
            if root is not None:
                break
        else:
            return None
    except ElementTree.ParseError:
        return None
    if root.tag not in ('svg', '{http://www.w3.org/2000/svg}svg'):
        return None
    lengths = [SVG_LENGTH.match(root.get(name, '')) for name in ('width', 'height')]
    if all(lengths):
        width, height = (float(match.group(1)) for match in lengths)
    else:
        box = (root.get('viewBox') or '').replace(',', ' ').split()
        try:
            width, height = (float(value) for value in box[2:]) if len(box) == 4 else (0, 0)
        except ValueError:
            return None
    if not (0 < width < 1e6 and 0 < height < 1e6):
        return None
    return dict(format='svg', width=math.ceil(width), height=math.ceil(height), frames=1, animated=False, delaysMs=[], loop=None)


def known(path):
    # Map structural inputs read-only rather than copying compressed source
    # bodies into Python memory. Parsers retain only metadata/small views; SVG
    # inspection feeds its root parser incrementally from the file.
    with Path(path).open('rb') as source:
        if not source.seek(0, 2):
            return None
        source.seek(0)
        failure = None
        with mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as mapped:
            try:
                result = known_container(memoryview(mapped))
            except ValueError as error:
                # Drop parser traceback-held views before closing the map.
                failure = str(error)
        if failure is not None:
            raise ValueError(failure)
        if result is not None:
            return result
        return svg_chunks(iter(lambda: source.read(4096), b''))


def known_container(data):
    if data[:8] == b'\x89PNG\r\n\x1a\n':
        # Input PNGs need not use our output's 8-bit encoding. Classify their
        # complete content container, then let the actual decoder read pixels.
        width, height, animation, delays = 0, 0, None, []
        for kind, value in png_chunks(data):
            if kind == b'IHDR':
                width, height = struct.unpack_from('!II', value)
            elif kind == b'acTL':
                if animation is not None or len(value) != 8:
                    raise ValueError('Invalid PNG animation control')
                animation = struct.unpack('!II', value)
            elif kind == b'fcTL':
                if len(value) != 26:
                    raise ValueError('Incomplete PNG animation frames')
                numerator, denominator = struct.unpack_from('!HH', value, 20)
                delays.append(round(1000 * numerator / (denominator or 100)))
        if not width or not height:
            raise ValueError('Invalid PNG dimensions')
        if animation is None:
            return dict(format='png', width=width, height=height, frames=1, animated=False, delaysMs=[], loop=None)
        frames, loop = animation
        if frames != len(delays):
            raise ValueError('Incomplete PNG animation frames')
        return dict(format='apng', width=width, height=height, frames=frames, animated=frames > 1, delaysMs=delays, loop=loop)
    if data[:6] == b'GIF87a' or data[:6] == b'GIF89a':
        return gif(data)
    if data[:4] == b'RIFF' and data[8:12] == b'WEBP':
        return webp(data)
    return None
