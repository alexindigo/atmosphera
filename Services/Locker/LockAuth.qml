import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// Lock-only authentication. Presentation and preferences are supplied by the
// consumer; this component never imports the shell, its settings or plugins.
Scope {
  id: root

  required property string username
  property string pamConfig: Quickshell.env("ATMOSPHERA_PAM_SERVICE") || "login"
  readonly property string pamConfigDirectory: "/etc/pam.d"
  property bool autoStartAuth: false
  property bool allowPasswordWithFingerprint: false
  property string passwordPrompt: "Password"
  property string failureMessage: "Authentication failed"
  property bool enabled: true
  property bool pamReady: false

  property string passwordText: ""
  property bool waitingForPassword: false
  property bool unlockInProgress: false
  property bool showFailure: false
  property bool showInfo: false
  property string errorMessage: ""
  property string infoMessage: ""

  signal unlocked
  signal failed
  signal diagnostic(string message)

  function startAutomaticAuth() {
    if (enabled && pamReady && autoStartAuth && passwordText === "")
      pam.start();
  }

  // Revocation precedes teardown/handover. Clearing text cannot restart PAM
  // after revocation, and a queued completion cannot authorize an unlock.
  function retire() {
    enabled = false;
    pam.abort();
    detectPamServiceProc.running = false;
    occupyFingerprintSensorProc.running = false;
    passwordText = "";
    waitingForPassword = false;
    unlockInProgress = false;
  }

  onEnabledChanged: {
    if (enabled)
      startAutomaticAuth();
    else {
      pam.abort();
      occupyFingerprintSensorProc.running = false;
      waitingForPassword = false;
      unlockInProgress = false;
    }
  }
  onPamReadyChanged: startAutomaticAuth()
  onShowInfoChanged: if (showInfo) showFailure = false
  onShowFailureChanged: if (showFailure) showInfo = false

  Component.onCompleted: {
    if (Quickshell.env("ATMOSPHERA_PAM_SERVICE"))
      pamReady = true;
    else
      detectPamServiceProc.running = true;
  }

  Process {
    id: detectPamServiceProc
    command: ["sh", "-c", "if [ -f /etc/pam.d/login ]; then echo login; elif [ -f /etc/pam.d/system-auth ]; then echo system-auth; elif [ -f /etc/pam.d/common-auth ]; then echo common-auth; else echo login; fi"]
    stdout: StdioCollector { id: pamServiceOutput }
    onExited: function (code) {
      const service = String(pamServiceOutput.text || "").trim();
      if (code === 0 && service !== "")
        root.pamConfig = service;
      root.pamReady = true;
      root.diagnostic("PAM service: " + root.pamConfig);
    }
  }

  onPasswordTextChanged: {
    if (!enabled)
      return;
    if (passwordText !== "") {
      showInfo = false;
      showFailure = false;
      if (!waitingForPassword)
        pam.abort();
      if (allowPasswordWithFingerprint)
        occupyFingerprintSensorProc.running = true;
    } else {
      occupyFingerprintSensorProc.running = false;
      startAutomaticAuth();
    }
  }

  function tryUnlock() {
    if (!enabled || !pamReady || unlockInProgress)
      return;
    if (waitingForPassword) {
      pam.respond(passwordText);
      unlockInProgress = true;
      waitingForPassword = false;
      showInfo = false;
      return;
    }
    root.diagnostic("Starting PAM authentication");
    pam.start();
  }

  Process {
    id: occupyFingerprintSensorProc
    command: ["fprintd-verify"]
  }

  PamContext {
    id: pam
    configDirectory: root.pamConfigDirectory
    config: root.pamConfig
    user: root.username

    onPamMessage: {
      if (!root.enabled)
        return;
      if (responseRequired) {
        if (root.passwordText !== "") {
          respond(root.passwordText);
          root.unlockInProgress = true;
        } else {
          root.waitingForPassword = true;
          root.infoMessage = root.passwordPrompt;
          root.showInfo = true;
        }
      } else if (messageIsError) {
        root.errorMessage = message;
        root.showFailure = true;
      } else {
        root.infoMessage = message;
        root.showInfo = true;
      }
    }

    onCompleted: result => {
      if (!root.enabled)
        return;
      root.waitingForPassword = false;
      root.unlockInProgress = false;
      if (result === PamResult.Success) {
        root.diagnostic("Authentication successful");
        root.unlocked();
      } else {
        root.passwordText = "";
        root.errorMessage = root.failureMessage;
        root.showFailure = true;
        root.failed();
      }
    }

    onError: {
      if (!root.enabled)
        return;
      root.errorMessage = message || "Authentication error";
      root.showFailure = true;
      root.unlockInProgress = false;
    }
  }
}
