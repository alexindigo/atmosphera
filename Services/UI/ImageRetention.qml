pragma ComponentBehavior: Bound
import ImvQml

import QtQuick
import Quickshell
import "../../Helpers/PortalPaths.js" as PortalPaths

Scope {
  id: root
  required property ImageOriginalStore store
  required property string source
  required property string destinationDirectory
  required property bool notification
  required property string key
  required property var completed
  property bool videoFrame: false
  property string _stageDirectory: ""
  property string _stage: key + ".png"
  property bool _retainOriginal: false
  property string _inputSource: ""
  property int _ticket: 0
  property int _backoff: 25
  property bool _closed: false
  property bool _writing: false

  function begin() {
    if (!source) {
      fail("invalid-source", "The original image source is empty");
      return;
    }
    if (videoFrame) {
      const local = source.startsWith("/") ? PortalPaths.pathToUri(source) : PortalPaths.uriToPath(source);
      if (!local.ok) {
        fail("invalid-source", "Video wallpaper must be a local file");
        return;
      }
      _inputSource = local.uri || PortalPaths.pathToUri(local.path).uri;
      _writing = true;
      store.ensureStage(ok => {
        _writing = false;
        if (_closed) {
          destroy();
          return;
        }
        if (!ok) {
          fail("retention-unavailable", "The video frame store is not ready");
          return;
        }
        _stageDirectory = store.stageDirectory;
        validate();
      });
      return;
    }
    if (source.startsWith("image://")) {
      // render() snapshots a synchronous provider before returning. Do not
      // move this admission to a timer, or retry by rereading the provider.
      _stageDirectory = store.stageDirectory;
      if (!_stageDirectory) {
        // Warm the stage for subsequent events; this producer must never be
        // read after the current callback returns.
        store.ensureStage();
        fail("retention-unavailable", "The provider snapshot store is not ready");
        return;
      }
      _ticket = job.render(source, 8192, 8192, _stageDirectory + "/" + _stage);
      if (_ticket <= 0)
        fail("provider-unavailable", "Could not admit the provider snapshot");
      return;
    }
    if (source.startsWith("/") || /^file:/i.test(source)) {
      const local = source.startsWith("/") ? PortalPaths.pathToUri(source) : PortalPaths.uriToPath(source);
      if (!local.ok) {
        finish({
                 ok: false,
                 code: "invalid-source",
                 reason: "The original image path is invalid"
               });
        return;
      }
      _stageDirectory = store.stageDirectory;
      if (!_stageDirectory) {
        store.ensureStage();
        fail("retention-unavailable", "The original image store is not ready");
        return;
      }
      // Admission opens the bounded descriptor now; copy and decode happen
      // off-thread. Never retry by reopening a producer-owned pathname.
      _retainOriginal = true;
      _ticket = job.retainOriginal(local.uri || PortalPaths.pathToUri(local.path).uri, _stageDirectory);
      if (_ticket <= 0)
        fail("admission-rejected", "Could not admit the original image");
    } else {
      _inputSource = source;
    }
  }

  function validate() {
    if (_closed || _ticket > 0 || _writing || !(videoFrame ? _stageDirectory : input.url))
      return;
    if (videoFrame && _stageDirectory !== store.stageDirectory) {
      fail("retention-unavailable", "The video frame store was retired");
      return;
    }
    _ticket = videoFrame ? job.render(_inputSource, 1024, 1024, _stageDirectory + "/" + _stage, "png", 0.1) : job.sample(input.url, 1, 1, 0.1);
    if (_ticket === -2) {
      retry.interval = _backoff;
      _backoff = Math.min(500, _backoff * 2);
      retry.restart();
    } else if (_ticket <= 0) {
      fail("admission-rejected", "Could not admit the original image");
    }
  }

  function fail(code, reason) {
    laterFailure.code = code;
    laterFailure.reason = reason;
    laterFailure.restart();
  }

  function publish(format, sha256) {
    if (_stageDirectory && _stageDirectory !== store.stageDirectory) {
      fail("retention-unavailable", "The provider snapshot store was retired");
      return;
    }
    _writing = true;
    const packet = {
      key: key,
      directory: destinationDirectory,
      notification: notification,
      format: format,
      frame: videoFrame
    };
    if (_stageDirectory)
      packet.stage = _stage;
    else
      packet.source = input.url;
    if (_retainOriginal)
      packet.sha256 = sha256;
    store.publish(packet, reply => {
      _writing = false;
      if (!_closed)
        finish(reply);
      else
        destroy();
    });
  }

  function finish(reply) {
    if (_closed)
      return;
    _closed = true;
    try {
      completed(reply.originalPath || "", reply.ok, reply);
    } finally {
      // The callback publishes its model/live claim before we release pending.
      store.release(key);
      destroy();
    }
  }

  function cancel() {
    if (_closed)
      return;
    _closed = true;
    retry.stop();
    laterFailure.stop();
    store.release(key);
    if (_ticket > 0) {
      job.cancel(_ticket);
      // A publication may already have started. Await its receipt, then
      // discard the stage, rather than orphaning a finished file.
    } else if (!_writing) {
      destroy();
    }
  }

  ImageInput {
    id: input
    source: root.videoFrame ? "" : root._inputSource
    onUrlChanged: root.validate()
    onStateChanged: {
      if (state === "unavailable")
        root.fail(errorCode, errorReason);
    }
  }
  ImvImageJob {
    id: job
    onFinished: (id, result) => {
      if (id !== root._ticket)
        return;
      root._ticket = 0;
      if (result.stage === "complete" && root._retainOriginal)
        root._stage = result.path.slice(root._stageDirectory.length + 1);
      if (root._closed) {
        if (result.stage === "complete")
          root.store.discard(root._stageDirectory, root._stage);
        root.destroy();
      } else if (result.stage === "complete") {
        root.publish(root._retainOriginal ? result.format : result.sourceInfo.format, result.sha256);
      } else {
        root.fail(result.code, result.detail || result.code);
      }
    }
  }
  Timer {
    id: retry
    onTriggered: root.validate()
  }
  Timer {
    id: laterFailure
    property string code
    property string reason
    onTriggered: root.finish({
                               ok: false,
                               code: code,
                               reason: reason
                             })
  }
}
