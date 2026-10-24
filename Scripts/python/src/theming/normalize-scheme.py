#!/usr/bin/env python3
"""Shell loading boundary: normalize one JSON scheme from stdin, without I/O."""

import json
import sys
import os
from pathlib import Path
import tempfile

from lib.scheme import normalize_scheme


if __name__ == '__main__':
    try:
        data = normalize_scheme(json.load(sys.stdin))
        if len(sys.argv) == 3 and sys.argv[1] == '--save':
            path = Path(sys.argv[2])
            path.parent.mkdir(parents=True, exist_ok=True)
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.scheme-', delete=False) as output:
                    temporary = Path(output.name)
                    json.dump(data, output, indent=2)
                    output.write('\n')
                os.replace(temporary, path)
            finally:
                if temporary is not None:
                    temporary.unlink(missing_ok=True)
        print(json.dumps(data))
    except (ValueError, KeyError, TypeError) as error:
        print(f'Invalid colour scheme: {error}', file=sys.stderr)
        sys.exit(1)
