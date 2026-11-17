#!/usr/bin/env python3
"""Static NetworkManager ownership gate, with positive/negative canaries."""
import argparse
from pathlib import Path
import re

ADAPTERS = {"NmState.qml", "NmDevice.qml", "NmProfile.qml", "NmActiveConnection.qml", "NmAccessPoint.qml", "NmIpConfig.qml"}
FACADES = {"NetworkService.qml", "VPNService.qml"}
NETWORK = Path("Services/Networking")


def violations(sources):
    errors = []
    for path, text in sources.items():
        adapter = path.parent == NETWORK and path.name in ADAPTERS
        facade = path.parent == NETWORK and path.name in FACADES
        # NM transport is literal in production; fixtures deliberately construct
        # controlled transports and are checked by their separate runtime suite.
        if "org.freedesktop.NetworkManager" in text and not adapter:
            errors.append((str(path), "NM transport outside named backend adapters"))
        if facade and re.search(r"\bimport\s+DBus\b|\bDBus\s*\{|\.(?:asyncCall|getProperty|setProperty|call)\s*\(", text):
            errors.append((str(path), "facade constructs/uses D-Bus transport"))
        if adapter:
            if re.search(r"\b(?:Item|Loader)\s*\{", text):
                errors.append((str(path), "graphical object in non-visual NM backend"))
            proxy_count = len(re.findall(r"\bDBus\s*\{", text))
            if proxy_count > (1 if path.name == "NmDevice.qml" else 0):
                errors.append((str(path), "duplicate transport factory outside retained interface"))
            if path.name in ADAPTERS - {"NmDevice.qml", "NmState.qml"} and len(re.findall(r"\bNmDevice\.Interface\s*\{", text)) != 1:
                errors.append((str(path), "record must own exactly one retained interface"))
        if re.search(r"\._(?:refreshCore|refreshDetails|readIpConfig|readApDetails)\s*\(", text):
            errors.append((str(path), "private device refresh access"))
        if (adapter or facade) and re.search(r"\brepeat\s*:\s*true\b", text):
            errors.append((str(path), "repeating NM timer"))
        if (adapter or facade) and re.search(r"\b(?:refreshTimer|delayedScanTimer|profileReadComponent|acUuidComponent|wifiScanComponent|wifiListComponent|apReadComponent)\b", text):
            errors.append((str(path), "legacy polling/transient factory"))
        if not adapter and "NmDevice" in text and re.search(r"\bNmDevice\s*\{|\bNmDevice\.[A-Z]\w*\s*\{", text):
            errors.append((str(path), "device transport constructed outside backend"))
    return errors


def canaries():
    safe = {NETWORK / "VPNService.qml": "pragma Singleton\nSingleton { function refresh() { NmState.reconcileProfiles(); } }",
            NETWORK / "NmDevice.qml": 'Scope { DBus { service: "org.freedesktop.NetworkManager" } }'}
    assert not violations(safe), "positive ownership canary"
    cases = [
        (Path("Modules/Bad.qml"), 'DBus { service: "org.freedesktop.NetworkManager" }', "NM transport outside"),
        (NETWORK / "VPNService.qml", "import DBus 1.0\nSingleton {}", "facade constructs"),
        (NETWORK / "NetworkService.qml", "Singleton { function refresh() { device._refreshCore(); } }", "private device refresh"),
        (NETWORK / "NmState.qml", "Singleton { Timer { repeat: true; onTriggered: refresh() } }", "repeating NM timer"),
        (NETWORK / "NmProfile.qml", "Item { property var profileReadComponent: null }", "legacy polling"),
        (NETWORK / "NmDevice.qml", "Item { DBus {} DBus {} }", "duplicate transport factory"),
        (Path("Modules/Bad.qml"), "NmDevice {}", "device transport constructed"),
        (NETWORK / "NmState.qml", "Singleton { Component { Item {} } }", "graphical object"),
        (NETWORK / "NmDevice.qml", "Scope { Loader {} }", "graphical object"),
    ]
    for path, text, expected in cases:
        result = violations({**safe, path: text})
        assert any(expected in reason for _, reason in result), (path, expected, result)
    return len(cases) + 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    sources = {path.relative_to(args.root): path.read_text() for path in args.root.rglob("*.qml")
               if ".git" not in path.parts and "Scripts" not in path.relative_to(args.root).parts}
    for name in ADAPTERS | FACADES:
        assert NETWORK / name in sources, f"missing backend/facade: {name}"
    count = canaries()
    errors = violations(sources)
    for path, reason in errors:
        print(f"{path}: {reason}")
    assert not errors, f"{len(errors)} NetworkManager ownership violations"
    print(f"NetworkManager ownership: {len(sources)} files, {count} canaries, 0 violations")


if __name__ == "__main__":
    main()
