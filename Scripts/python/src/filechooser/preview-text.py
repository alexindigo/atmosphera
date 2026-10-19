#!/usr/bin/env python3
"""Return a bounded, strictly decoded UTF-8 prefix; never modify the source."""

import codecs
import json
import sys

LIMIT = 262_144


def preview(path):
    try:
        with open(path, "rb") as source:
            data = source.read(LIMIT + 1)
        truncated = len(data) > LIMIT
        # Incremental strict decoding permits only an incomplete final sequence
        # at the truncation boundary, not malformed bytes elsewhere in the prefix.
        text = codecs.getincrementaldecoder("utf-8")("strict").decode(
            data[:LIMIT], final=not truncated
        )
        if "\x00" in text:
            return {"ok": False, "error": "binary"}
        return {"ok": True, "text": text, "truncated": truncated}
    except FileNotFoundError:
        return {"ok": False, "error": "missing"}
    except UnicodeDecodeError:
        return {"ok": False, "error": "binary"}
    except (OSError, ValueError, TypeError):
        return {"ok": False, "error": "unreadable"}


if __name__ == "__main__":
    print(json.dumps(preview(sys.argv[1] if len(sys.argv) == 2 else None)))
