"""Fail before publishing any image file whose payload was not fully written."""
import errno


def write_exact(stream, data):
    if stream.write(data) != len(data):
        raise OSError(errno.EIO, 'Short image file write')
