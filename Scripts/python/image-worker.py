#!/usr/bin/env python3
"""JSON-lines entry point for the shell's single image representation worker."""
import asyncio
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / 'src'))
from images.worker import serve

if __name__ == '__main__':
    asyncio.run(serve())
