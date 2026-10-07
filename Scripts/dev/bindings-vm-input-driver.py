#!/usr/bin/env python3
"""Scoped host-side physical driver, adapted from the retained historical recipe."""
import argparse
import json
from pathlib import PurePosixPath
import shlex
import subprocess
import time
import xml.etree.ElementTree as ET

URI = "qemu+ssh://ark-dom/system"
VM = "arch-atmosphera-gtkfree"


def identity():
    dom = ET.fromstring(subprocess.check_output(["virsh", "-c", URI, "dumpxml", VM]))
    assert dom.findtext("uuid") == "2c790f00-3a2f-4042-962d-fede17fec400"
    assert dom.find("devices/interface/mac").attrib["address"] == "52:54:00:cd:ea:a0"
    assert dom.find("devices/disk/source").attrib["file"] == "/var/lib/libvirt/images/arch-atmosphera-gtkfree.bindings-fifo-handoff-20261003-2204"
    rows = subprocess.check_output(["virsh", "-c", URI, "domifaddr", VM, "--source", "agent"]).decode().splitlines()
    return next(l for l in rows if "52:54:00:cd:ea:a0" in l and "ipv4" in l).split()[-1].split("/")[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output", required=True, help="fresh guest root journal directory")
    ap.add_argument("--deadline", type=int, default=900)
    a = ap.parse_args()
    root = PurePosixPath(a.output)
    assert str(root).startswith("/home/tester/post-071/bindings-fifo-handoff/recovery-journals/")
    ip = identity()
    ssh = ["ssh", "-J", "ark-dom", "-i", "/home/user/.ssh/id_vm-agent", "-o", "IdentitiesOnly=yes",
           "-o", "IdentityAgent=none", "-o", "BatchMode=yes", "tester@" + ip]
    script = ("from pathlib import Path; import json; root=Path(" + repr(str(root)) + "); "
              "paths=list(root.rglob('AWAITING-*')) if root.exists() else []; "
              "result=root/'result.json'; terminal=json.loads(result.read_text()) if result.exists() else None; "
              "print(json.dumps({'terminal':terminal,'requests':[[str(p),p.stat().st_mtime_ns,p.read_text()] for p in paths]}))")
    seen = set()
    end = time.monotonic() + a.deadline
    while time.monotonic() < end:
        p = subprocess.run(ssh + ["python3 -c " + shlex.quote(script)], capture_output=True, text=True, check=True)
        state = json.loads(p.stdout)
        if state["terminal"] is not None:
            print("DRIVER: terminal " + state["terminal"]["status"], flush=True)
            return 0  # Runner result, not a driver exit, determines case acceptance.
        for path, revision, text in state["requests"]:
            if (path, revision) in seen:
                continue
            assert root in PurePosixPath(path).parents
            assert identity() == ip
            for line in text.splitlines():
                cmd = shlex.split(line)
                assert len(cmd) == 6 and cmd[:5] == ["virsh", "-c", URI, "qemu-monitor-command", VM]
                assert json.loads(cmd[5])["execute"] in ("send-key", "input-send-event")
                subprocess.run(cmd, check=True)
                time.sleep(.4)
            go = path.replace("/AWAITING-", "/GO-")
            subprocess.run(ssh + ["python3 -c " + shlex.quote("from pathlib import Path; Path(" + repr(go) + ").touch(exist_ok=False)")], check=True)
            seen.add((path, revision))
            print("INJECTED " + path, flush=True)
        time.sleep(.4)
    raise SystemExit("driver deadline; preserve and inspect runner/owned lifecycle")


if __name__ == "__main__":
    raise SystemExit(main())
