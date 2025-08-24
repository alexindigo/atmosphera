import QtQuick
import Quickshell
import Quickshell.Services.Pam

Scope {
  id: root
  signal unlocked
  signal failed

  property string currentText: ""
  property bool unlockInProgress: false
  property bool showFailure: false
  property string errorMessage: ""
  property bool pamAvailable: typeof PamContext !== "undefined"

  onCurrentTextChanged: {
    if (currentText !== "") {
      showFailure = false
      errorMessage = ""
    }
  }

  function tryUnlock() {
    if (!pamAvailable) {
      errorMessage = "PAM not available"
      showFailure = true
      return
    }

    if (currentText === "") {
      errorMessage = "Password required"
      showFailure = true
      return
    }

    root.unlockInProgress = true
    errorMessage = ""
    showFailure = false

    console.log("Starting PAM authentication for user:", pam.user)
    pam.start()
  }

  PamContext {
    id: pam
    config: "login"
    user: Quickshell.env("USER")

    onPamMessage: {
      console.log("PAM message:", message, "isError:", messageIsError, "responseRequired:", responseRequired)

      if (messageIsError) {
        errorMessage = message
      }

      if (responseRequired) {
        console.log("Responding to PAM with password")
        respond(root.currentText)
      }
    }

    onResponseRequiredChanged: {
      console.log("Response required changed:", responseRequired)
      if (responseRequired && root.unlockInProgress) {
        console.log("Automatically responding to PAM")
        respond(root.currentText)
      }
    }

    onCompleted: {
      console.log("PAM completed with result:", result)
      if (result === PamResult.Success) {
        console.log("Authentication successful")
        root.unlocked()
      } else {
        console.log("Authentication failed")
        errorMessage = "Authentication failed"
        showFailure = true
        root.failed()
      }
      root.unlockInProgress = false
    }

    onError: {
      console.log("PAM error:", error, "message:", message)
      errorMessage = message || "Authentication error"
      showFailure = true
      root.unlockInProgress = false
      root.failed()
    }
  }
}
