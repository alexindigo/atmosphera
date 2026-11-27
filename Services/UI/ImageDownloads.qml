pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// One acquisition owner for every remote ImageInput in this shell process.
// A successful request remains leased until its own caller retires it.
Singleton {
  id: root

  property double _sequence: 0
  property bool _started: false
  property var _requests: new Map()

  function acquire(url, callback) {
    const ticket = ++_sequence;
    const request = {
      url: url,
      callback: callback,
      delivered: false
    };
    _requests.set(ticket, request);
    if (_started)
      _send({
              action: "get",
              id: ticket,
              url: url
            });
    else if (!worker.running)
      worker.running = true;

    return () => {
      if (_requests.delete(ticket) && _started)
        _send({
                action: "release",
                id: ticket
              });
    };
  }

  function _send(packet) {
    worker.write(JSON.stringify(packet) + "\n");
  }

  function _receive(line) {
    const reply = JSON.parse(line);
    const request = _requests.get(reply.id);
    if (!request || request.delivered)
      return;
    if (reply.source)
      request.delivered = true;
    else
      _requests.delete(reply.id);
    request.callback(reply);
  }

  function _failed() {
    _started = false;
    const lost = _requests;
    _requests = new Map();
    for (const request of lost.values())
      request.callback({
                         code: "download-failed",
                         reason: "The image download owner stopped"
                       });
  }

  Process {
    id: worker
    workingDirectory: Quickshell.shellDir + "/Scripts/python/src"
    command: ["python3", "-B", "-m", "images.download", "--serve", Settings.cacheDir]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: line => root._receive(line)
    }
    onStarted: {
      root._started = true;
      for (const [ticket, request] of root._requests)
        root._send({
                     action: "get",
                     id: ticket,
                     url: request.url
                   });
    }
    onRunningChanged: if (!running && !root._started)
                        root._failed()
    onExited: root._failed()
  }
  Component.onDestruction: worker.stdinEnabled = false
}
