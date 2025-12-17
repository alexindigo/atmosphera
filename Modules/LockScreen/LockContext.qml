import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs.Commons
import qs.Services.System

Scope {
  id: root
  signal unlocked
  signal failed

  property string currentText: ""
  property bool unlockInProgress: false
  property bool showFailure: false
  property string errorMessage: ""
  property string infoMessage: ""
  property bool pamAvailable: typeof PamContext !== "undefined"
  property string pamConfigDirectory: Settings.configDir + "pam"
  property string pamConfig: "password.conf"
  property bool pamConfigChecked: false

  Component.onCompleted: {
    // Check if /etc/pam.d/quickshell exists (typically provided by NixOS module)
    // If it exists, use it; otherwise fall back to generated config in configDir
    checkSystemPamConfig();
  }

  function checkSystemPamConfig() {
    // Check if /etc/pam.d/quickshell exists
    // On NixOS, this is typically provided by the NixOS module
    // On other systems, it can be manually created
    // If it doesn't exist, fall back to generated config in configDir
    if (!pamConfigChecked) {
      Logger.i("LockContext", "Checking for system PAM config: /etc/pam.d/quickshell");
      systemPamCheckProcess.command = ["test", "-f", "/etc/pam.d/quickshell"];
      systemPamCheckProcess.running = true;
    } else {
      Logger.d("LockContext", "PAM config already checked, skipping");
    }
  }

  onCurrentTextChanged: {
    if (currentText !== "") {
      showFailure = false;
      errorMessage = "";
    }
  }

  function tryUnlock() {
    if (!pamAvailable) {
      errorMessage = "PAM not available";
      showFailure = true;
      return;
    }

    if (root.unlockInProgress) {
      Logger.i("LockContext", "Unlock already in progress, ignoring duplicate attempt");
      return;
    }

    root.unlockInProgress = true;
    errorMessage = "";
    showFailure = false;

    Logger.i("LockContext", "Starting PAM authentication for user:", pam.user);
    pam.start();
  }

  // Process to check if system PAM config exists
  Process {
    id: systemPamCheckProcess
    running: false

    onRunningChanged: {
      if (running) {
        Logger.i("LockContext", "Started checking for system PAM config");
      }
    }

    onExited: function (exitCode) {
      Logger.d("LockContext", "PAM config check completed with exit code:", exitCode);
      pamConfigChecked = true;
      if (exitCode === 0) {
        // /etc/pam.d/quickshell exists, use it
        root.pamConfigDirectory = "/etc/pam.d";
        root.pamConfig = "quickshell";
        Logger.i("LockContext", "System PAM config found, using: /etc/pam.d/quickshell");
      } else {
        // Use generated config in configDir
        root.pamConfigDirectory = Settings.configDir + "pam";
        root.pamConfig = "password.conf";
        Logger.i("LockContext", "System PAM config not found, using generated config:", root.pamConfigDirectory + "/" + root.pamConfig);
      }
    }
  }

  PamContext {
    id: pam
    // Use custom PAM config to ensure predictable password-only authentication
    // Prefers /etc/pam.d/quickshell if it exists (especially on NixOS)
    // Otherwise uses config created in Settings.qml and stored in configDir/pam/
    configDirectory: root.pamConfigDirectory
    config: root.pamConfig
    user: HostService.username

    onPamMessage: {
      Logger.i("LockContext", "PAM message:", message, "isError:", messageIsError, "responseRequired:", responseRequired);

      if (messageIsError) {
        errorMessage = message;
      } else {
        infoMessage = message;
      }

      if (this.responseRequired) {
        Logger.i("LockContext", "Responding to PAM with password");
        this.respond(root.currentText);
      }
    }

    onCompleted: result => {
                   Logger.i("LockContext", "PAM completed with result:", result);
                   if (result === PamResult.Success) {
                     Logger.i("LockContext", "Authentication successful");
                     root.unlocked();
                   } else {
                     Logger.i("LockContext", "Authentication failed");
                     root.currentText = "";
                     errorMessage = I18n.tr("lock-screen.authentication-failed");
                     showFailure = true;
                     root.failed();
                   }
                   root.unlockInProgress = false;
                 }

    onError: {
      Logger.i("LockContext", "PAM error:", error, "message:", message);
      errorMessage = message || "Authentication error";
      showFailure = true;
      root.unlockInProgress = false;
      root.failed();
    }
  }
}
