pragma Singleton

import QtQuick
import Quickshell
import qs.Services.UI

Singleton {
  id: root

  function alert(question: string, replyPath: string) {
    var panel = PanelService.getPanel("dialogPanel", Quickshell.screens[0]);
    if (panel) {
      panel.showFor(0, question, "", replyPath);
    } else {
      Logger.w("IPC", "Dialog panel not available, sending empty reply");
      Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "dialog-reply", "", replyPath]);
    }
  }

  function confirm(question: string, replyPath: string) {
    var panel = PanelService.getPanel("dialogPanel", Quickshell.screens[0]);
    if (panel) {
      panel.showFor(1, question, "", replyPath);
    } else {
      Logger.w("IPC", "Dialog panel not available, sending empty reply");
      Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "dialog-reply", "", replyPath]);
    }
  }

  function prompt(question: string, replyPath: string, defaultText: string) {
    var panel = PanelService.getPanel("dialogPanel", Quickshell.screens[0]);
    if (panel) {
      panel.showFor(2, question, defaultText || "", replyPath);
    } else {
      Logger.w("IPC", "Dialog panel not available, sending empty reply");
      Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "dialog-reply", "", replyPath]);
    }
  }

  function survey(question: string, b64fields: string, replyPath: string) {
    var fields = b64fields;
    try {
      fields = Qt.atob(b64fields);
    } catch (e) {}
    var panel = PanelService.getPanel("dialogPanel", Quickshell.screens[0]);
    if (panel) {
      panel.showFor(3, question, fields, replyPath);
    } else {
      Logger.w("IPC", "Dialog panel not available, sending empty reply");
      Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "dialog-reply", "", replyPath]);
    }
  }
}
