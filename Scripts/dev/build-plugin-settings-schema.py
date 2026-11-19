#!/usr/bin/env python3
"""Development entry point for the shipped descriptor compiler."""
from pathlib import Path
import runpy

globals().update({name: value for name, value in runpy.run_path(
    str(Path(__file__).resolve().parents[2]/'Scripts/python/src/settings/plugin-schema.py'),
    run_name=__name__).items() if not name.startswith('__')})
