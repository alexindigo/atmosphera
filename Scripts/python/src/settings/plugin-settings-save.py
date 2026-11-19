#!/usr/bin/env python3
"""Acknowledged transport for the pre-configqml plugin owner.

Reuse section-io's preimage/prepare/promote/readback protocol. This is removed
with the old owner at cutover; it is not an alternative settings backend.
Only a value-free outcome leaves this process. Settings enter on stdin.
"""
import json
from pathlib import Path
import subprocess
import sys
import uuid


def publish(configured, conflicts, value):
    if not isinstance(value, dict):
        return {"status": "failed", "error": {"code": "plugin-settings-input"}}
    target = configured.resolve()
    helper = Path(__file__).with_name("section-io.py")
    temporary = target.with_name(target.name + ".prepare-" + uuid.uuid4().hex)

    def step(mode, payload=None):
        if configured.resolve() != target:
            raise RuntimeError("target changed")
        args = [sys.executable, str(helper), mode, str(target)]
        if mode != "inspect":
            args.append(str(temporary))
        result = subprocess.run(args, input=None if payload is None else json.dumps(payload),
                                capture_output=True, text=True, timeout=20, check=False)
        response = json.loads(result.stdout)
        if result.returncode or not response.get("ok"):
            raise RuntimeError("publication failed")
        return response

    raw = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    base = step("inspect")["state"]
    if base["exists"] and base["raw"] == raw:
        return {"status": "nothing_to_save", "error": {}}
    prepared = step("prepare", {"base": base, "raw": raw, "conflicts": str(conflicts)})
    prepared["conflicts"] = str(conflicts)
    step("promote", prepared)
    return {"status": "saved", "error": {}}


def main():
    try:
        configured, conflicts = map(Path, sys.argv[1:3])
        if not configured.is_absolute() or not conflicts.is_absolute():
            raise ValueError("absolute paths required")
        # Parent creation is off the GUI thread, including fresh installs.
        configured.parent.mkdir(parents=True, exist_ok=True)
        result = publish(configured, conflicts, json.load(sys.stdin))
    except Exception:
        # section-io retains its private conflict/prepare artifacts. No values,
        # parser text or user paths are copied into diagnostics or receipts.
        result = {"status": "failed", "error": {"code": "plugin-settings-save"}}
    print(json.dumps(result))
    return 1 if result["status"] == "failed" else 0


if __name__ == "__main__":
    sys.exit(main())
