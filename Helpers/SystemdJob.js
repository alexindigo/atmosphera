.pragma library

function replyOnce(reply, complete) {
    if (!reply) { complete(false, null, "Could not construct D-Bus reply", ""); return; }
    var handled = false;
    function received() {
        if (handled) return;
        handled = true;
        complete(!reply.isError, reply.isError ? null : reply.value,
                 reply.isError ? reply.error.message : "", reply.isError ? reply.error.name : "");
    }
    reply.finished.connect(received);
    if (reply.isFinished) received();
}

function unitState(parent, manager, unit, complete) {
    try {
        replyOnce(manager.call("LoadUnit", [unit]), function (success, path, error, name) {
            if (!success) { complete(false, "", error, name === "org.freedesktop.systemd1.NoSuchUnit"); return; }
            var proxy = Qt.createQmlObject('import DBus 1.0; DBus { service: "org.freedesktop.systemd1"; iface: "org.freedesktop.systemd1.Unit" }', parent, "UnitStateRead");
            proxy.connection = manager.connection;
            proxy.path = String(path);
            replyOnce(proxy.getProperty("ActiveState"), function (ok, value, failure) {
                proxy.destroy();
                complete(ok, ok ? String(value) : "", failure, false);
            });
        });
    } catch (error) {
        complete(false, "", "Could not read systemd unit state", false);
    }
}

// Observe the existing Manager job, including removal before method reply.
// No service initialization or automatic retry policy lives in this helper.
function run(parent, manager, method, unit, complete) {
    var terminal = false;
    var path = "";
    var removals = {};
    var watcher = null;
    var timeout = null;
    function finish(success, error) {
        if (terminal) return;
        terminal = true;
        if (watcher) watcher.destroy();
        if (timeout) timeout.destroy();
        complete(success, error || "");
    }
    function result() {
        if (path && removals[path] !== undefined)
            finish(removals[path] === "done", removals[path] === "done" ? "" : "systemd job failed: " + removals[path]);
    }
    function action() {
        var reply = manager.call(method, [unit, "replace"]);
        if (!reply) { finish(false, "Could not create systemd operation"); return; }
        var handled = false;
        function received() {
            if (handled || terminal) return;
            handled = true;
            if (reply.isError) { finish(false, reply.error.message); return; }
            path = String(reply.value);
            result();
        }
        reply.finished.connect(received);
        if (reply.isFinished) received();
    }
    try {
        watcher = Qt.createQmlObject('import DBus 1.0; DBusSignalWatcher { service: "org.freedesktop.systemd1"; path: "/org/freedesktop/systemd1"; iface: "org.freedesktop.systemd1.Manager"; member: "JobRemoved" }', parent, "OwnedSystemdJob");
        watcher.connection = manager.connection;
        watcher.received.connect(function (member, args) {
            if (terminal || args.length < 4 || String(args[2]) !== unit) return;
            removals[String(args[1])] = String(args[3]);
            result();
        });
        timeout = Qt.createQmlObject("import QtQuick; Timer { interval: 90000; repeat: false }", parent, "SystemdJobDeadline");
        timeout.triggered.connect(function () { finish(false, "systemd job completion timed out"); });
        timeout.start();
        var subscription = manager.call("Subscribe", []);
        if (!subscription) { finish(false, "Could not subscribe to systemd jobs"); return; }
        var subscribed = false;
        function subscriptionReady() {
            if (subscribed || terminal) return;
            subscribed = true;
            if (subscription.isError && subscription.error.name !== "org.freedesktop.systemd1.AlreadySubscribed") {
                finish(false, subscription.error.message);
                return;
            }
            action();
        }
        subscription.finished.connect(subscriptionReady);
        if (subscription.isFinished) subscriptionReady();
    } catch (error) {
        finish(false, "systemd job observation failed");
    }
}
