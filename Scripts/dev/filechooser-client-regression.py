#!/usr/bin/env python3
"""Actual PortalFilePicker/settings consumer cases using a private bus."""

import argparse
import json
from pathlib import Path
import sys
import time

from filechooser_regression import Run


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--label", required=True)
    a = p.parse_args()
    r = Run(a.source, a.label)
    try:
        r.start()
        r.ipc("settingsOpen")
        r.wait(lambda s: len(s["requests"]) == 1 and s["requests"][0]["status"] == "ready")
        r.check("icon-unchanged-before-accept", r.state()["icon"] == "/original.svg" and r.state()["iconType"] == "icons" and r.state()["saved"]["iconSource"] == "/original.svg" and r.state()["saved"]["iconType"] == "icons", r.state())
        r.command(["ydotool", "type", "Icon"]); time.sleep(.3); r.key(28)
        s = r.wait(lambda s: s["accepts"] == 1 and not s["requests"])
        icon = str(r.fixtures / "Icon.png")
        r.check("PortalFilePicker-consumer-path", s["saved"]["iconSource"] == icon and s["saved"]["iconType"] == "file" and s["icon"] == icon, s)
        r.ipc("settingsOpen"); r.wait(lambda s: bool(s["requests"]))
        r.ipc("settingsClose"); r.ipc("settingsClose")
        s = r.wait(lambda s: s["cancels"] == 1 and not s["requests"])
        r.check("close-once-preserves-icon", s["accepts"] == 1 and s["icon"] == icon, s)
        r.ipc("settingsOpen"); r.wait(lambda s: bool(s["requests"]))
        r.portal.terminate(); r.portal.wait(timeout=5)
        s = r.wait(lambda s: s["cancels"] == 2 and not s["requests"])
        r.check("service-loss-settles-once", s["accepts"] == 1 and s["icon"] == icon, s)
        r.check("frontend-name-missing", r.bus("NameHasOwner", "s", "org.freedesktop.portal.Desktop") == "b false")
        # The owned private bus has no activation directories, so this really
        # exercises a missing service rather than silently starting a daemon.
        r.ipc("settingsOpen")
        s = r.wait(lambda s: s["cancels"] == 3)
        r.check("missing-portal-settles-once", s["accepts"] == 1 and s["icon"] == icon and not s["requests"], s)
        time.sleep(.7)
        r.check("no-late-second-settlement", r.state()["accepts"] == 1 and r.state()["cancels"] == 3, r.state())
        wire = [json.loads(l) for l in (r.output / "wire.jsonl").read_text().splitlines() if l.startswith("{")]
        calls = [(i, x) for i, x in enumerate(wire) if x.get("type") == "method_call" and x.get("interface") == "org.freedesktop.portal.FileChooser" and x.get("member") == "OpenFile"]
        r.check("internal-correct-Desktop-service", len(calls) == 4 and all(x["destination"] == "org.freedesktop.portal.Desktop" for _, x in calls), calls)
        order = []
        for i, call in calls:
            token = call["payload"]["data"][2]["handle_token"]["data"]
            matches = [j for j, x in enumerate(wire) if x.get("member") == "AddMatch" and x.get("sender") == call["sender"] and token in str(x.get("payload")) and "Response" in str(x.get("payload"))]
            order.append({"call": i, "matches": matches})
        r.check("Response-watch-before-every-OpenFile", all(x["matches"] and max(x["matches"]) < x["call"] for x in order), order)
        r.finish()
    except Exception as error:
        r.failure = repr(error)
        raise
    finally:
        r.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
