.pragma library

// A fresh child/collectors per invocation. No queue, retries, caller state or
// settings payload in command construction. The parent owns stage settlement.
function run(parent, command, input, complete) {
    var process = null;
    var terminal = false;
    var started = false;
    var armed = false;

    function finish(success, error, code, status) {
        if (terminal)
            return;
        terminal = true;
        var result = {
            "success": success, "error": error, "exitCode": code,
            "exitStatus": status, "stdout": process ? String(process.stdout.text || "") : "",
            "stderr": process ? String(process.stderr.text || "") : ""
        };
        if (process)
            process.destroy();
        complete(result);
    }

    try {
        if (!command || command.length === 0 || !command[0]) {
            finish(false, "Empty child command", null, null);
            return null;
        }
        process = Qt.createQmlObject("import QtQuick\nimport Quickshell.Io\nProcess { stdout: StdioCollector {} stderr: StdioCollector {} }", parent, "OwnedChild");
        process.command = command;
        process.stdinEnabled = input !== undefined && input !== null;
        process.started.connect(function () {
            started = true;
            if (input !== undefined && input !== null) {
                process.write(input);
                process.stdinEnabled = false;
            }
        });
        process.exited.connect(function (code, status) {
            finish(status === 0 && code === 0,
                   status === 0 && code === 0 ? "" : "Child failed (exit " + code + ", status " + status + ")", code, status);
        });
        process.runningChanged.connect(function () {
            // Official 0.3.1 emits no runningChanged for post-reload deferral.
            // FailedToStart clears running without an exited signal.
            if (armed && !started && !process.running && !terminal)
                finish(false, "Child failed to start", null, null);
        });
        armed = true;
        process.running = true;
    } catch (error) {
        if (!terminal)
            finish(false, "Could not create/start child", null, null);
        else
            throw error;
    }
    return process;
}
