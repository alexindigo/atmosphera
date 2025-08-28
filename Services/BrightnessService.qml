pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
    id: root

    property list<var> ddcMonitors: []
    readonly property list<Monitor> monitors: variants.instances
    property bool appleDisplayPresent: false
    // Blacklist DDC buses that error or hang
    property var ddcBlacklist: []

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.modelData === screen);
    }

    function getAvailableMethods(): list<string> {
        var methods = [];
        if (monitors.some(m => m.isDdc))
            methods.push("ddcutil");
        if (monitors.some(m => !m.isDdc))
            methods.push("internal");
        if (appleDisplayPresent)
            methods.push("apple");
        return methods;
    }

    // Global helpers for IPC and shortcuts
    function increaseBrightness(): void {
        monitors.forEach(m => m.increaseBrightness());
    }

    function decreaseBrightness(): void {
        monitors.forEach(m => m.decreaseBrightness());
    }

    function getDetectedDisplays(): list<var> {
        return detectedDisplays;
    }

    reloadableId: "brightness"

    Component.onCompleted: {
        Logger.log("Brightness", "Service started");
    }

    onMonitorsChanged: {
        ddcMonitors = [];
        ddcProc.running = true;
    }

    Variants {
        id: variants
        model: Quickshell.screens
        Monitor {}
    }

    // Check for Apple Display support
    Process {
        running: true
        command: ["sh", "-c", "which asdbctl >/dev/null 2>&1 && asdbctl get || echo ''"]
        stdout: StdioCollector {
            onStreamFinished: root.appleDisplayPresent = text.trim().length > 0
        }
    }

    // Detect DDC monitors
    Process {
        id: ddcProc
        // Add a timeout so detect can't hang the UI
        command: ["sh", "-c", "timeout 3s ddcutil detect --brief || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Do not filter out invalid displays. For some reason --brief returns some invalid which works fine
                var displays = text.trim().split("\n\n");
                root.ddcMonitors = displays.map(d => {
                    var modelMatch = d.match(/Monitor:.*:(.*):.*/);
                    var busMatch = d.match(/I2C bus:[ ]*\/dev\/i2c-([0-9]+)/);
                    return {
                        "model": modelMatch ? modelMatch[1] : "",
                        "busNum": busMatch ? busMatch[1] : ""
                    };
                });
            }
        }
    }

    component Monitor: QtObject {
        id: monitor

        required property ShellScreen modelData
        readonly property string busNum: root.ddcMonitors.find(m => m.model === modelData.model)?.busNum ?? ""
        // Treat embedded panels as internal only
        readonly property bool isInternalPanel: modelData.name.startsWith("eDP") || modelData.name.startsWith("LVDS") || modelData.name.startsWith("DSI")
        // Only use DDC if not internal and not blacklisted
        readonly property bool isDdc: busNum !== "" && !isInternalPanel && root.ddcBlacklist.indexOf(busNum) === -1
        readonly property bool isAppleDisplay: root.appleDisplayPresent && modelData.model.startsWith("StudioDisplay")
        readonly property string method: isAppleDisplay ? "apple" : (isDdc ? "ddcutil" : "internal")

        property real brightness
        property real lastBrightness: 0
        property real queuedBrightness: NaN

        // Signal for brightness changes
        signal brightnessUpdated(real newBrightness)

        // Initialize brightness
        readonly property Process initProc: Process {
            stdout: StdioCollector {
                onStreamFinished: {
                    var dataText = text.trim();
                    if (dataText === "") {
                        return;
                    }

                    // If DDC responded with an error, blacklist this bus and fall back to internal
                    if (monitor.isDdc && dataText.indexOf("ERR") !== -1) {
                        if (root.ddcBlacklist.indexOf(monitor.busNum) === -1) {
                            Logger.warn("Brightness", "Blacklisting DDC bus", monitor.busNum);
                            root.ddcBlacklist = root.ddcBlacklist.concat([monitor.busNum]);
                        }
                        // Re-init using the new method (will now be 'internal')
                        monitor.initBrightness();
                        return;
                    }

                    Logger.log("Brightness", "Raw brightness data for", monitor.modelData.name + ":", dataText);

                    if (monitor.isAppleDisplay) {
                        var val = parseInt(dataText);
                        if (!isNaN(val)) {
                            monitor.brightness = val / 101;
                            Logger.log("Brightness", "Apple display brightness:", monitor.brightness);
                        }
                    } else if (monitor.isDdc) {
                        var parts = dataText.split(" ");
                        if (parts.length >= 4) {
                            var current = parseInt(parts[3]);
                            var max = parseInt(parts[4]);
                            if (!isNaN(current) && !isNaN(max) && max > 0) {
                                monitor.brightness = current / max;
                                Logger.log("Brightness", "DDC brightness:", current + "/" + max + " =", monitor.brightness);
                            }
                        }
                    } else {
                        // Internal backlight
                        var parts = dataText.split(" ");
                        if (parts.length >= 2) {
                            var current = parseInt(parts[0]);
                            var max = parseInt(parts[1]);
                            if (!isNaN(current) && !isNaN(max) && max > 0) {
                                monitor.brightness = current / max;
                                Logger.log("Brightness", "Internal brightness:", current + "/" + max + " =", monitor.brightness);
                            }
                        }
                    }

                    // Always update
                    monitor.brightnessUpdated(monitor.brightness);
                }
            }
        }

        // Timer for debouncing rapid changes
        readonly property Timer timer: Timer {
            interval: 200
            onTriggered: {
                if (!isNaN(monitor.queuedBrightness)) {
                    monitor.setBrightness(monitor.queuedBrightness);
                    monitor.queuedBrightness = NaN;
                }
            }
        }

        function increaseBrightness(): void {
            var stepSize = Settings.data.brightness.brightnessStep / 100.0;
            setBrightnessDebounced(brightness + stepSize);
        }

        function decreaseBrightness(): void {
            var stepSize = Settings.data.brightness.brightnessStep / 100.0;
            setBrightnessDebounced(monitor.brightness - stepSize);
        }

        function setBrightness(value: real): void {
            value = Math.max(0, Math.min(1, value));
            var rounded = Math.round(value * 100);

            if (Math.round(brightness * 100) === rounded)
                return;
            if (isDdc && timer.running) {
                queuedBrightness = value;
                return;
            }

            brightness = value;
            brightnessUpdated(brightness);

            if (isAppleDisplay) {
                Quickshell.execDetached(["asdbctl", "set", rounded]);
            } else if (isDdc) {
                // Add timeout so ddcutil can't hang
                Quickshell.execDetached(["sh", "-c", "timeout 1s ddcutil -b " + busNum + " setvcp 10 " + rounded + " >/dev/null 2>&1 || true"]);
            } else {
                Quickshell.execDetached(["brightnessctl", "s", rounded + "%"]);
            }

            if (isDdc) {
                timer.restart();
            }
        }

        function setBrightnessDebounced(value: real): void {
            queuedBrightness = value;
            timer.restart();
        }

        function initBrightness(): void {
            if (isAppleDisplay) {
                initProc.command = ["asdbctl", "get"];
            } else if (isDdc) {
                // Add timeout and a fallback ERR marker to trigger blacklist
                initProc.command = ["sh", "-c", "timeout 1s ddcutil -b " + busNum + " getvcp 10 --brief || echo 'VCP 10 ERR'"];
            } else {
                // Internal backlight - try to find the first available backlight device
                initProc.command = ["sh", "-c", "for dev in /sys/class/backlight/*; do if [ -f \"$dev/brightness\" ] && [ -f \"$dev/max_brightness\" ]; then echo \"$(cat $dev/brightness) $(cat $dev/max_brightness)\"; break; fi; done"];
            }
            initProc.running = true;
        }

        onBusNumChanged: initBrightness()
        Component.onCompleted: initBrightness()
    }
}
