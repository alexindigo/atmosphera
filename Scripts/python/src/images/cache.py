"""One independently decoded, validated representation/cache owner."""
import asyncio
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile

from . import content
from .png import (atomic_write, bucket, cache_name, canonical_uri, empty_png,
                  metadata, validate as validate_png, with_metadata)
from .process import command, CommandError
from .sources import prepare, identity, SourceError

SCHEMA = 1


def iterations(info):
    value = info.get('loop')
    if value is None:
        return 1
    if value == 0:
        return 0
    return value + 1 if info['format'] == 'gif' else value


def capability_fingerprint():
    rows = []
    for executable in ('magick', 'ffmpeg', 'ffprobe'):
        path = shutil.which(executable)
        rows.append((executable, path, identity(Path(path).stat()) if path else None))
    # A normal package/delegate installation changes this directory even if the
    # converter binary did not change. Also cover manually replaced codec libs.
    for path in [Path('/var/lib/pacman/local'), *Path('/usr/lib').glob('lib*heif*.so*'),
                 *Path('/usr/lib').glob('lib*webp*.so*'), *Path('/usr/lib').glob('lib*avcodec*.so*')]:
        try:
            rows.append((str(path), identity(path.stat())))
        except OSError:
            rows.append((str(path), None))
    return hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()


class Cache:
    def __init__(self, root=None, version=None, timeout=8, emit=lambda event: None):
        self.root = Path(root or Path(os.environ.get('XDG_CACHE_HOME') or Path.home() / '.cache') / 'thumbnails')
        self.private = self.root / 'atmosphera-representations-v1'
        self.staging = self.private / 'staging'
        self.timeout, self.emit = timeout, emit
        self.animation_timeout = 120
        if version is None:
            version = (Path(__file__).resolve().parents[4] / 'VERSION').read_text().strip()
        self.failure_dir = self.root / 'fail' / ('atmosphera-' + version.replace('/', '_'))

    def valid(self, path, uri, info):
        try:
            data = path.read_bytes()
            validate_png(data)
            values = metadata(data)
            return (values.get('Thumb::URI') == uri and values.get('Thumb::MTime') == str(int(info.st_mtime))
                    and ('Thumb::Size' not in values or values['Thumb::Size'] == str(info.st_size))
                    and ('Atmo::MTimeNS' not in values or values['Atmo::MTimeNS'] == str(info.st_mtime_ns))
                    and ('Atmo::CTimeNS' not in values or values['Atmo::CTimeNS'] == str(info.st_ctime_ns)))
        except (OSError, ValueError, UnicodeError):
            return False

    async def command(self, argv):
        self.staging.mkdir(parents=True, mode=0o700, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=self.staging, prefix='.video-command-') as folder:
            output = await command(argv, folder, self.timeout)
            return output.read_bytes()

    async def frame(self, path, size):
        duration = json.loads(await self.command(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', str(path)]))
        seconds = float(duration.get('format', {}).get('duration', 0))
        seek = seconds * .1 if math.isfinite(seconds) and seconds >= 1 else 0
        argv = ['ffmpeg', '-nostdin', '-v', 'error', '-threads', '1', '-ss', str(seek), '-i', str(path),
                                   '-frames:v', '1', '-vf', f'scale={size}:{size}:force_original_aspect_ratio=decrease',
                                   '-threads', '1', '-pix_fmt', 'rgba', '-f', 'image2pipe', '-c:v', 'png', 'pipe:1']
        self.emit(dict(event='ffmpeg', path=str(path), argv=argv))
        return await self.command(argv)

    async def get(self, name, pixels):
        """Compatible freedesktop video entry point; no second decoder pool."""
        path = Path(os.fsdecode(os.path.abspath(name)))
        if path.resolve().is_relative_to(self.root.resolve()):
            return dict(url='', status='excluded')
        info = path.stat()
        if not stat.S_ISREG(info.st_mode) or not os.access(path, os.R_OK):
            return dict(url='', status='unreadable')
        uri = canonical_uri(path)
        size, directory = bucket(pixels)
        target = self.root / directory / cache_name(uri)
        failure = self.failure_dir / target.name
        fingerprint = capability_fingerprint()
        if self.valid(target, uri, info):
            return dict(url=target.as_uri(), status='hit')
        if self.valid(failure, uri, info) and metadata(failure.read_bytes()).get('Atmo::Capability') == fingerprint:
            return dict(url='', status='failure-hit')
        attributes = {'Thumb::URI': uri, 'Thumb::MTime': str(int(info.st_mtime)), 'Thumb::Size': str(info.st_size),
                      'Atmo::MTimeNS': str(info.st_mtime_ns), 'Atmo::CTimeNS': str(info.st_ctime_ns),
                      'Atmo::Capability': fingerprint, 'Software': 'Atmosphera'}
        try:
            data = await asyncio.wait_for(self.frame(path, size), self.timeout)
            validate_png(data)
            data, success = with_metadata(data, attributes), True
        except (ValueError, OSError, CommandError, asyncio.TimeoutError):
            data, success = with_metadata(empty_png(), attributes), False
        if identity(info) != identity(path.stat()):
            return dict(url='', status='changed')
        atomic_write(target if success else failure, data, self.root)
        return dict(url=target.as_uri() if success else '', status='generated' if success else 'failed')

    async def inspect(self, prepared):
        known = content.known(prepared['path'])
        if known:
            return known
        try:
            out = await command(['magick', 'identify', '-format', '%m|%w|%h|%T|%[iterations]|%[orientation]\n', str(prepared['path'])],
                                prepared['directory'], self.timeout, name='inspect-magick', emit=self.emit)
            rows = [row.split('|') for row in out.read_text().splitlines()]
            if not rows or any(len(row) != 6 for row in rows):
                raise ValueError('Invalid image metadata')
            first = rows[0]
            width, height = int(first[1]), int(first[2])
            delays = [round(float(row[3]) * 10) for row in rows]
            if not width or not height:
                raise ValueError('Invalid image dimensions')
            return dict(format=first[0].lower(), width=width, height=height, frames=len(rows),
                        animated=len(rows) > 1 and any(delays), delaysMs=delays,
                        loop=int(first[4]) if first[4] else None, orientation=first[5])
        except (ValueError, OSError, CommandError):
            out = await command(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-count_frames',
                                 '-show_entries', 'stream=codec_name,width,height,nb_read_frames:format=duration', '-of', 'json', str(prepared['path'])],
                                prepared['directory'], self.timeout, name='inspect-ffprobe', emit=self.emit)
            streams = json.loads(out.read_text()).get('streams', [])
            if len(streams) != 1 or not streams[0].get('width') or not streams[0].get('height'):
                raise ValueError('No image stream')
            stream = streams[0]
            count = int(stream.get('nb_read_frames', '1'))
            if count > 1:
                # Frame count without timing cannot certify motion preservation.
                raise SourceError('animation-metadata-unavailable', 'The image timing could not be inspected')
            return dict(format=stream['codec_name'], width=stream['width'], height=stream['height'], frames=count,
                        animated=False, delaysMs=[], loop=None)

    def filters(self, request, ffmpeg=False):
        width, height, fit = request['width'], request['height'], request.get('fit', 'contain')
        if ffmpeg:
            if fit in ('cover', 'circle'):
                return f'scale={width}:{height}:force_original_aspect_ratio=increase,crop={width}:{height}'
            return f'scale={width}:{height}:force_original_aspect_ratio=decrease'
        args = ['-auto-orient', '-filter', 'Lanczos', '-resize', f'{width}x{height}' + ('^' if fit in ('cover', 'circle') else '')]
        if fit in ('cover', 'circle'):
            args += ['-gravity', 'center', '-extent', f'{width}x{height}']
        if fit == 'circle':
            args += ['-alpha', 'set', '(', '+clone', '-channel', 'A', '-evaluate', 'set', '0', '+channel', '-fill', 'white',
                     '-draw', f'circle {width / 2},{height / 2} {width / 2},0', ')', '-compose', 'DstIn', '-composite']
        return args

    async def decode(self, prepared, request, info):
        moving = request.get('animationIntent', 'still') == 'preserve' and info['animated']
        target = prepared['directory'] / ('result.gif' if moving else 'result.png')
        attempts = []
        for decoder in ('magick', 'ffmpeg'):
            target.unlink(missing_ok=True)
            try:
                if not shutil.which(decoder):
                    raise CommandError('decoder-unavailable', 'An independent image decoder is not installed')
                if decoder == 'magick':
                    argv = ['magick', str(prepared['path']) + ('' if moving else '[0]')]
                    if moving:
                        argv += ['-coalesce']
                    argv += self.filters(request)
                    if moving:
                        argv += ['+repage', '-dispose', 'Background', '-loop', str(iterations(info)), 'GIF:' + str(target)]
                    else:
                        argv += ['-strip', 'PNG32:' + str(target)]
                else:
                    argv = ['ffmpeg', '-nostdin', '-v', 'error', '-threads', '1', '-i', str(prepared['path'])]
                    filters = self.filters(request, ffmpeg=True)
                    if moving:
                        loop = iterations(info)
                        argv += ['-filter_complex', f'[0:v]{filters},split[a][b];[a]palettegen=reserve_transparent=1[p];[b][p]paletteuse=alpha_threshold=128',
                                 '-fps_mode', 'passthrough', '-loop', str(0 if loop == 0 else loop - 1 if loop > 1 else -1),
                                 '-final_delay', str(round(info['delaysMs'][-1] / 10)), '-threads', '1', '-f', 'gif', str(target)]
                    else:
                        if request.get('fit') == 'circle':
                            filters += ",format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lte(pow(X-W/2,2)+pow(Y-H/2,2),pow(min(W,H)/2,2)),alpha(X,Y),0)'"
                        argv += ['-frames:v', '1', '-vf', filters, '-threads', '1', '-pix_fmt', 'rgba', '-c:v', 'png', '-f', 'image2', str(target)]
                await command(argv, prepared['directory'], self.animation_timeout if moving else self.timeout,
                              name='decode-' + decoder, emit=self.emit)
                if not target.is_file() or not target.stat().st_size:
                    raise ValueError('Decoder did not produce the exact output')
                output = await self.validate_output(target, prepared['directory'], moving, request)
                if moving and (output['frames'] != info['frames'] or iterations(output) != iterations(info)
                               or len(output['delaysMs']) != len(info['delaysMs'])
                               or any(abs(a - b) > 5 for a, b in zip(output['delaysMs'], info['delaysMs']))):
                    raise ValueError('Decoder did not preserve frame count, timing and looping')
                return target, output, decoder
            except (CommandError, ValueError, OSError) as error:
                attempts.append(dict(decoder=decoder, code=getattr(error, 'code', 'invalid-output'), reason=str(error)))
        # Decoding failure is not evidence that arbitrary source bytes are corrupt.
        failure = SourceError('decode-unavailable', 'No available decoder could produce a valid image')
        failure.attempts = attempts
        raise failure

    async def validate_output(self, path, directory, moving, request):
        if not moving:
            result = validate_png(path.read_bytes(), maximum=(request['width'], request['height']))
        else:
            result = content.gif(path.read_bytes())
        width, height = result['width'], result['height']
        target_width, target_height = request['width'], request['height']
        if request.get('fit', 'contain') in ('cover', 'circle'):
            valid_size = width == target_width and height == target_height
        else:
            valid_size = width <= target_width and height <= target_height and (width == target_width or height == target_height)
        if not valid_size:
            raise ValueError('Decoded image does not have the requested physical dimensions')
        if not moving:
            return result
        # Full independent GIF pixel decoding, in addition to complete structure.
        if shutil.which('ffmpeg'):
            argv = ['ffmpeg', '-nostdin', '-v', 'error', '-threads', '1', '-i', str(path), '-f', 'null', '-']
        elif shutil.which('magick'):
            argv = ['magick', str(path), '-coalesce', 'null:']
        else:
            raise CommandError('decoder-unavailable', 'GIF validation requires an image decoder')
        await command(argv, directory, self.animation_timeout, name='validate-gif', emit=self.emit)
        return result

    async def render(self, request):
        for field in ('width', 'height'):
            if type(request.get(field)) is not int or request[field] <= 0:
                raise ValueError('Positive physical image dimensions required')
        if request.get('fit', 'contain') not in ('contain', 'cover', 'circle') or request.get('animationIntent', 'still') not in ('still', 'preserve'):
            raise ValueError('Invalid image representation')
        async with prepare(request['source'], self.staging, request.get('revision', ''), self.emit) as prepared:
            info = await self.inspect(prepared)
            if request.get('operation') == 'inspect':
                if not prepared['current']():
                    raise SourceError('source-changed', 'Image source changed during inspection')
                return dict(url='', status='inspected', sourceInfo=info, **info)
            moving = request.get('animationIntent') == 'preserve' and info['animated']
            key_data = dict(schema=SCHEMA, content=prepared['contentSha256'], stat=prepared['stat'], revision=prepared['revision'],
                            width=request['width'], height=request['height'], fit=request.get('fit', 'contain'),
                            representation=request.get('animationIntent', 'still'))
            key = hashlib.sha256(json.dumps(key_data, sort_keys=True).encode()).hexdigest()
            target = self.private / ('animated' if moving else 'still') / (key + ('.gif' if moving else '.png'))
            failure = self.private / 'fail' / (key + '.json')
            fingerprint = capability_fingerprint()
            if target.is_file():
                try:
                    output = await self.validate_output(target, prepared['directory'], moving, request)
                    if moving and (output['frames'] != info['frames'] or iterations(output) != iterations(info) or output['delaysMs'] != info['delaysMs']):
                        raise ValueError('Stale animation cache')
                    if not prepared['current']():
                        raise SourceError('source-changed', 'Image source changed before publication')
                    return dict(url=target.as_uri(), status='hit', origin='fallback', sourceInfo=info, **output)
                except (ValueError, OSError, CommandError):
                    pass
            if failure.is_file() and not request.get('retry'):
                try:
                    negative = json.loads(failure.read_text())
                    if negative['capability'] == fingerprint:
                        return dict(url='', status='unavailable', code=negative['code'], reason=negative['reason'])
                except (OSError, ValueError, KeyError):
                    pass
            try:
                output_path, output, decoder = await self.decode(prepared, request, info)
                if not prepared['current']():
                    raise SourceError('source-changed', 'Image source changed before publication')
                atomic_write(target, output_path.read_bytes(), self.root)
                return dict(url=target.as_uri(), status='generated', origin='fallback', decoder=decoder, sourceInfo=info, **output)
            except SourceError as error:
                if error.code != 'source-changed':
                    atomic_write(failure, json.dumps(dict(capability=fingerprint, code=error.code, reason=str(error))).encode(), self.root)
                raise
