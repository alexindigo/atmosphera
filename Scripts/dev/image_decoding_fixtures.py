"""Independent colored image inputs and pixel observations for image regressions.

Expected pixels are authored here, not obtained by decoding a product output.
Only the encoders use external tools. PNG observations use a separate stdlib
reader, so a successful converter exit cannot act as its own pixel oracle.
"""
import binascii
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import zlib


WIDTH, HEIGHT = 96, 64
COLORS = [(230, 35, 55, 255), (20, 195, 85, 255), (35, 65, 225, 255)]
DELAYS_MS = [120, 230, 350]


def _chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', binascii.crc32(kind + data))


def colored_png(color, width=WIDTH, height=HEIGHT):
    # A transparent margin exercises alpha; a finite opaque center is the pixel
    # witness shared by still, animation, crop and rounded/shader consumers.
    rows = []
    for y in range(height):
        row = bytearray()
        for x in range(width):
            value = color if 8 <= x < width - 8 and 8 <= y < height - 8 else (0, 0, 0, 0)
            # Frame-specific transparent-margin marks expose a forgotten clear/
            # disposal operation even when the opaque center still looks right.
            if color == COLORS[0] and 2 <= x < 6 and 2 <= y < 6:
                value = (255, 220, 0, 255)
            elif color == COLORS[1] and width - 6 <= x < width - 2 and 2 <= y < 6:
                value = (0, 220, 240, 255)
            row.extend(value)
        rows.append(b'\0' + row)
    return (b'\x89PNG\r\n\x1a\n' + _chunk(b'IHDR', struct.pack('!IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + _chunk(b'IDAT', zlib.compress(b''.join(rows))) + _chunk(b'IEND', b''))


def read_png(path):
    """Decode noninterlaced 8-bit PNGs written by Qt, including all filters."""
    data = Path(path).read_bytes()
    assert data.startswith(b'\x89PNG\r\n\x1a\n'), 'Not a PNG'
    offset, payload, palette, transparency, ended = 8, bytearray(), None, b'', False
    while offset + 12 <= len(data):
        size = struct.unpack_from('!I', data, offset)[0]
        kind = data[offset + 4:offset + 8]
        content = data[offset + 8:offset + 8 + size]
        end = offset + 12 + size
        assert end <= len(data), 'Truncated PNG'
        assert binascii.crc32(kind + content) == struct.unpack_from('!I', data, end - 4)[0], 'PNG CRC'
        if kind == b'IHDR':
            width, height, depth, mode, compression, filtering, interlace = struct.unpack('!IIBBBBB', content)
            assert width > 0 and height > 0 and depth == 8 and compression == filtering == interlace == 0
        elif kind == b'PLTE':
            palette = [tuple(content[i:i + 3]) for i in range(0, len(content), 3)]
        elif kind == b'tRNS':
            transparency = content
        elif kind == b'IDAT':
            payload.extend(content)
        elif kind == b'IEND':
            assert not content and end == len(data)
            ended = True
            break
        offset = end
    assert ended, 'Missing PNG end'
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[mode]
    raw = zlib.decompress(payload)
    stride = width * channels
    assert len(raw) == (stride + 1) * height
    previous, pixels = bytearray(stride), bytearray()
    for y in range(height):
        start = y * (stride + 1)
        filtering, row = raw[start], bytearray(raw[start + 1:start + stride + 1])
        assert filtering in range(5)
        for x in range(stride):
            a, b, c = row[x - channels] if x >= channels else 0, previous[x], previous[x - channels] if x >= channels else 0
            if filtering == 1:
                predict = a
            elif filtering == 2:
                predict = b
            elif filtering == 3:
                predict = (a + b) // 2
            elif filtering == 4:
                p = a + b - c
                distances = (abs(p - a), abs(p - b), abs(p - c))
                predict = (a, b, c)[distances.index(min(distances))]
            else:
                predict = 0
            row[x] = (row[x] + predict) & 255
        for x in range(width):
            pixel = row[x * channels:(x + 1) * channels]
            if mode == 6:
                pixels.extend(pixel)
            elif mode == 2:
                pixels.extend((*pixel, 255))
            elif mode == 0:
                pixels.extend((pixel[0], pixel[0], pixel[0], 255))
            elif mode == 4:
                pixels.extend((pixel[0], pixel[0], pixel[0], pixel[1]))
            else:
                pixels.extend((*palette[pixel[0]], transparency[pixel[0]] if pixel[0] < len(transparency) else 255))
        previous = row
    return width, height, bytes(pixels)


def pixel(path, x=None, y=None):
    width, height, pixels = read_png(path)
    x, y = width // 2 if x is None else x, height // 2 if y is None else y
    if not (0 <= x < width and 0 <= y < height):
        raise ValueError(f'Pixel ({x}, {y}) outside {width}x{height} image: {path}')
    start = (y * width + x) * 4
    return list(pixels[start:start + 4])


def webp_metadata(path):
    """Read RIFF animation declarations independently of the image decoder."""
    data = Path(path).read_bytes()
    assert data[:4] == b'RIFF' and data[8:12] == b'WEBP'
    assert struct.unpack_from('<I', data, 4)[0] + 8 == len(data)
    result = dict(frames=[], loop=None)
    offset = 12
    def uint24(value):
        return int.from_bytes(value, 'little')
    while offset + 8 <= len(data):
        kind, size = data[offset:offset + 4], struct.unpack_from('<I', data, offset + 4)[0]
        payload = data[offset + 8:offset + 8 + size]
        assert len(payload) == size
        if kind == b'VP8X':
            result.update(width=uint24(payload[4:7]) + 1, height=uint24(payload[7:10]) + 1)
        elif kind == b'ANIM':
            result['loop'] = struct.unpack_from('<H', payload, 4)[0]
        elif kind == b'ANMF':
            result['frames'].append(dict(x=2 * uint24(payload[0:3]), y=2 * uint24(payload[3:6]),
                                         width=uint24(payload[6:9]) + 1, height=uint24(payload[9:12]) + 1,
                                         delayMs=uint24(payload[12:15]), flags=payload[15]))
        offset += 8 + size + size % 2
    assert offset == len(data)
    return result


def create_fixtures(root, commands):
    root = Path(root)
    root.mkdir()

    def encode(argv):
        result = subprocess.run(argv, capture_output=True, text=True, timeout=90)
        commands.append(dict(argv=argv, exit=result.returncode, stdout=result.stdout, stderr=result.stderr))
        if result.returncode:
            raise RuntimeError('Fixture encoder failed: ' + json.dumps(commands[-1]))

    for i, color in enumerate(COLORS):
        (root / f'frame-{i}.png').write_bytes(colored_png(color))
    # Fully opaque 2:1 bands distinguish fit, crop and stretch independently
    # of source alpha or the rounded renderer's own output.
    bands = b''.join(bytes(COLORS[0 if x < 30 else 1 if x < 90 else 2]) for x in range(120))
    geometry = (b'\x89PNG\r\n\x1a\n' + _chunk(b'IHDR', struct.pack('!IIBBBBB', 120, 60, 8, 6, 0, 0, 0))
                + _chunk(b'IDAT', zlib.compress((b'\0' + bands) * 60)) + _chunk(b'IEND', b''))
    (root / 'geometry.png').write_bytes(geometry)
    png = str(root / 'frame-0.png')
    # Lossless encodings; expected RGBA remains the independently authored PNG.
    encode(['ffmpeg', '-nostdin', '-v', 'error', '-i', png, '-frames:v', '1', '-threads', '1', '-c:v', 'libwebp', '-lossless', '1', str(root / 'Still.webp')])
    for ext in ('jpg', 'bmp', 'tiff', 'avif', 'heic'):
        encode(['magick', png, str(root / ('Still.' + ext))])
    encode(['magick', png, '-quality', '100', str(root / 'Still.jxl')])
    # Independently authored EXIF orientation 6 (90 degrees clockwise), inserted
    # into a JPEG encoding. No decoder is used to predict its displayed size.
    tiff = b'II\x2a\0' + struct.pack('<I', 8) + struct.pack('<H', 1) + struct.pack('<HHI', 0x112, 3, 1) + struct.pack('<H', 6) + b'\0\0' + b'\0' * 4
    exif = b'Exif\0\0' + tiff
    jpeg = (root / 'Still.jpg').read_bytes()
    (root / 'Oriented.jpg').write_bytes(jpeg[:2] + b'\xff\xe1' + struct.pack('!H', len(exif) + 2) + exif + jpeg[2:])
    args = ['magick']
    for i, delay in enumerate(DELAYS_MS):
        args += ['-delay', str(delay // 10), '-dispose', 'background', str(root / f'frame-{i}.png')]
    encode(args + ['-loop', '0', '-define', 'webp:lossless=true', str(root / 'Motion.webp')])
    encode(args + ['-loop', '0', str(root / 'Motion.gif')])
    encode(['magick', *[str(root / f'frame-{i}.png') for i in range(3)], str(root / 'Multipage.tiff')])
    (root / 'Still.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="96" height="64"><rect x="8" y="8" width="80" height="48" fill="#e62337"/></svg>')
    for name in ('Misleading.png', 'bracket[0]: image.webp', '-leading.webp', 'image:literal.webp', 'Space \u6d77\u5cb8.webp'):
        shutil.copyfile(root / 'Still.webp', root / name)
    (root / 'Corrupt.webp').write_bytes(b'not an image\n')
    (root / 'Truncated.webp').write_bytes((root / 'Motion.webp').read_bytes()[:40])
    (root / 'Unreadable.webp').write_bytes((root / 'Still.webp').read_bytes())
    (root / 'Unreadable.webp').chmod(0)
    motion = webp_metadata(root / 'Motion.webp')
    assert motion['width'] == WIDTH and motion['height'] == HEIGHT and motion['loop'] == 0
    assert [frame['delayMs'] for frame in motion['frames']] == DELAYS_MS, motion
    manifest = dict(schema=1, width=WIDTH, height=HEIGHT, colors=COLORS, delaysMs=DELAYS_MS, loop=0, webpAnimation=motion,
                    expected='Authored RGBA center colors, transparent margin; no product decoder used as oracle',
                    files={p.name: dict(sha256=hashlib.sha256(p.read_bytes()).hexdigest(), size=p.stat().st_size)
                           for p in root.iterdir() if p.name != 'Unreadable.webp'})
    manifest['files']['Unreadable.webp'] = dict(sha256=manifest['files']['Still.webp']['sha256'], size=(root / 'Unreadable.webp').stat().st_size, mode=0)
    (root / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest
