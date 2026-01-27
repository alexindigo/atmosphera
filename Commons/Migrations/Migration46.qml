import QtQuick
import Quickshell

QtObject {
  id: root

  function migrate(adapter, logger, rawJson) {
    logger.i("Migration46", "Removing legacy PAM configuration file");

    const shellName = "noctalia";
    const configDir = Quickshell.env("NOCTALIA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/" + shellName + "/";
    const pamConfigDir = configDir + "pam";
    const pamConfigFile = pamConfigDir + "/password.conf";

    // Remove the file if it exists
    const script = `rm -f '${pamConfigFile}'`;
    Quickshell.execDetached(["sh", "-c", script]);

    // Attempt to remove the directory if empty (ignore errors)
    const rmdirScript = `rmdir '${pamConfigDir}' 2>/dev/null || true`;
    Quickshell.execDetached(["sh", "-c", rmdirScript]);

    logger.d("Migration46", "Cleaned up legacy PAM config");

    return true;
  }
}
