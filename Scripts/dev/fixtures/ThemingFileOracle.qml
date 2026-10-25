import QtQuick
import Quickshell
import "../../../Helpers/OwnedProcess.js" as OwnedProcess
import qs.Commons

// Test-only file observation owner. A new process opens the file for each
// request; neither cached FileView text nor a timer defines read completion.
Scope {
  id: root
  property string path: ""
  property int _requested: 0
  property int _completed: 0
  property bool _running: false
  property string _error: ""
  property string _text: ""
  readonly property bool running: _running
  readonly property bool finished: _requested > 0 && _completed === _requested && !_running
  readonly property bool ready: finished && _error === ""
  readonly property string error: _error

  function reload() {
    const version = ++_requested;
    const selectedPath = path;
    _running = true;
    _error = "";
    _text = "";
    OwnedProcess.run(root, ["timeout", "5", "python3", "-c", "from pathlib import Path; import sys; sys.stdout.buffer.write(Path(sys.argv[1]).read_bytes())", selectedPath], null, function (result) {
      if (version !== root._requested)
        return;
      root._text = result.stdout;
      root._error = result.success ? "" : (result.stderr || result.error);
      root._completed = version;
      root._running = false;
      Logger.i("ThemingFileOracle", "THEMING_FILE_READ|" + JSON.stringify({
                                                                            request: version,
                                                                            path: selectedPath,
                                                                            success: result.success,
                                                                            text: result.stdout,
                                                                            error: root._error
                                                                          }));
    });
  }

  function text() {
    if (!ready)
      throw new Error("File oracle read has not completed successfully: " + path);
    return _text;
  }
}
