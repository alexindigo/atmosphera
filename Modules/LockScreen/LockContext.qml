import QtQuick
import qs.Commons
import qs.Services.Locker
import qs.Services.System

// Existing lock UI contract, adapted to the shared lock-only PAM owner.
LockAuth {
  username: HostService.username
  autoStartAuth: Settings.data.general.autoStartAuth
  allowPasswordWithFingerprint: Settings.data.general.allowPasswordWithFprintd
  passwordPrompt: I18n.tr("lock-screen.password")
  failureMessage: I18n.tr("authentication.failed")
  onDiagnostic: message => Logger.i("LockContext", message)
}
