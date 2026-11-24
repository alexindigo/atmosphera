"""Source-byte admission derived from Qt's image allocation budget."""
import os


# QImageReaderPrivate::maxAlloc in Qt 6 qimagereader.cpp (MiB). Respect the
# same positive runtime override as QImageReader::allocationLimit(). A disabled
# Qt allocation check does not make a network download unbounded: retain Qt's
# normal finite default in that case.
QT_DEFAULT_ALLOCATION_MIB = 256


def source_byte_budget():
    try:
        allocation_mib = int(os.environ.get('QT_IMAGEIO_MAXALLOC', ''))
    except ValueError:
        allocation_mib = QT_DEFAULT_ALLOCATION_MIB
    if allocation_mib <= 0 or allocation_mib > 2147483647:
        allocation_mib = QT_DEFAULT_ALLOCATION_MIB
    return allocation_mib * 1024 * 1024
