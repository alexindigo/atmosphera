"""Resolve the launcher test workspace across isolated runner re-execution.

The shared isolated runner intentionally forwards a restricted environment.
Source deliveries already encode their owning workspace in sources/<label>,
so an environment override must not be the only way to retain that ownership.
"""
import os
from pathlib import Path

source = Path(__file__).resolve().parents[2]
default = source.parent.parent if source.parent.name == 'sources' else source
ROOT = Path(os.environ.get('ATMOSPHERA_LAUNCHER_WORKSPACE', str(default)))
