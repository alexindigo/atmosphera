import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Files
import "../../../Helpers/OwnedProcess.js" as OwnedProcess

ShellRoot {
  id: root
  property var results: ({})
  property var current: null
  property var owner: null
  property int completed: 0
  property int pending: 0
  property int failures: 0
  property int streamed: 0
  property string streamText: ""
  property string lastOperation: ""

  Component { id: ownerFactory; QtObject {} }

  function record(name, result) {
    var next = Object.assign({}, results);
    next[name] = {calls: (next[name] ? next[name].calls : 0) + 1, result: result};
    results = next;
    current = null;
  }

  function nextChild() {
    if (pending === 0) return;
    OwnedProcess.run(root, ["/usr/bin/true"], null, function(result) {
      if (!result.success) ++root.failures;
      --root.pending;
      ++root.completed;
      Qt.callLater(root.nextChild);
    });
  }

  IpcHandler {
    target: "ownedProcessTest"
    function state(): string {
      return JSON.stringify({results: root.results, completed: root.completed, pending: root.pending,
        failures: root.failures, streamed: root.streamed, streamText: root.streamText, lastOperation: root.lastOperation,
        childPid: root.current ? root.current.processId : 0,
        childRunning: root.current ? root.current.running : false,
        childStdout: root.current ? root.current.stdout.text : "",
        childStderr: root.current ? root.current.stderr.text : "",
        pid: Quickshell.processId});
    }
    function start(encoded: string): void {
      var request = JSON.parse(decodeURIComponent(encoded));
      root.lastOperation = "start:" + request.name;
      root.current = OwnedProcess.run(root, request.argv, request.input,
        function(result) { root.record(request.name, result); });
    }
    function streaming(argv: string): void {
      root.current = OwnedProcess.run(root, JSON.parse(decodeURIComponent(argv)), null,
        function(result) { root.record("stream", result); });
      root.current.stdinEnabled = true;
      root.current.stdout.waitForEnd = false;
      root.current.stdout.dataChanged.connect(function() {
        if (root.current) {
          root.streamText = root.current.stdout.text;
          ++root.streamed;
        }
      });
    }
    function write(text: string): void { root.current.write(JSON.parse(decodeURIComponent(text))); }
    function closeInput(): void { root.current.stdinEnabled = false; }
    function stop(): void { root.current.running = false; }
    function kill(): void { root.current.signal(9); }
    function owned(argv: string): void {
      root.owner = ownerFactory.createObject(root);
      root.current = OwnedProcess.run(root.owner, JSON.parse(decodeURIComponent(argv)), null,
        function(result) { root.record("owner", result); });
    }
    function destroyOwner(): void { root.current = null; root.owner.destroy(); root.owner = null; }
    function chain(argv: string): void {
      OwnedProcess.run(root, JSON.parse(decodeURIComponent(argv)), null, function(first) {
        root.record("chain-first", first);
        OwnedProcess.run(root, JSON.parse(decodeURIComponent(argv)), null,
          function(second) { root.record("chain-second", second); });
      });
    }
    function batch(count: int): void { root.pending = count; root.nextChild(); }
    function collect(): void { gc(); }
    function quit(): void { Qt.quit(); }
  }
}
