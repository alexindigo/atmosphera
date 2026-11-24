"""Deliver a disposable fixture tree without requiring a shared filesystem."""
import errno
import os
import shutil


def link_or_copy(source, destination):
    try:
        os.link(source, destination)
    except OSError as error:
        if error.errno != errno.EXDEV:
            raise
        return shutil.copy2(source, destination)
    return destination
