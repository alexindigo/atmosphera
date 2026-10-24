pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.Keyboard

// Committed work contains data, never a callback owned by a launcher/provider.
// The singleton owns the deferred dispatch, including when the host unloads
// the launcher synchronously (overlay mode and immediate panel close).
Singleton {
  id: root
  property var pending: []

  function enqueue(action) {
    pending.push(action);
    Qt.callLater(root.drain);
  }

  function launchApplication(app) {
    enqueue({
              kind: "application",
              entry: app,
              name: String(app.name || ""),
              command: app.command && app.command.length !== undefined ? Array.from(app.command) : [],
              exec: String(app.exec || ""),
              terminal: !!app.runInTerminal,
              terminalCommand: Settings.data.appLauncher.terminalCommand.trim(),
              prefix: Settings.data.appLauncher.customLaunchPrefixEnabled ? Settings.data.appLauncher.customLaunchPrefix.trim() : ""
            });
  }

  function runCommand(expression) {
    enqueue({
              kind: "command",
              expression: String(expression)
            });
  }
  function pasteText(text) {
    enqueue({
              kind: "text",
              text: String(text)
            });
  }
  function pasteClipboard(id, mime) {
    enqueue({
              kind: "clipboard",
              id: String(id),
              mime: String(mime || "")
            });
  }
  function openSettings(entry, screen) {
    enqueue({
              kind: "settings",
              entry: JSON.parse(JSON.stringify(entry)),
              screen: screen
            });
  }
  function focusWindow(id) {
    enqueue({
              kind: "window",
              id: id
            });
  }
  function sessionAction(action) {
    enqueue({
              kind: "session",
              action: String(action)
            });
  }

  function drain() {
    const actions = pending;
    pending = [];
    for (const action of actions) {
      switch (action.kind) {
      case "application":
        executeApplication(action);
        break;
      case "command":
        Quickshell.execDetached(["sh", "-c", action.expression]);
        break;
      case "text":
        ClipboardService.pasteText(action.text);
        break;
      case "clipboard":
        ClipboardService.pasteFromClipboard(action.id, action.mime);
        break;
      case "settings":
        SettingsPanelService.openToEntry(action.entry, action.screen);
        break;
      case "window":
        for (var i = 0; i < CompositorService.windows.count; i++) {
          const win = CompositorService.windows.get(i);
          if (win.id === action.id) {
            CompositorService.focusWindow(win);
            break;
          }
        }
        break;
      case "session":
        executeSession(action.action);
        break;
      }
    }
  }

  function executeApplication(action) {
    const app = action.entry; // canonical DesktopEntries object, not UI-owned
    const args = action.command;
    const nativeArguments = action.exec.includes('"') || action.exec.includes("'") || args.some(arg => /["' ]/.test(String(arg)));
    if (app && app.execute && nativeArguments) {
      app.execute();
      return;
    }
    const terminal = action.terminal && action.terminalCommand ? action.terminalCommand.split(" ") : [];
    const command = terminal.concat(args);
    if (action.prefix) {
      Quickshell.execDetached(action.prefix.split(" ").concat(command));
    } else if (command.length > 0) {
      CompositorService.spawn(command);
    } else if (app && app.execute) {
      app.execute();
    } else {
      Logger.w("LauncherActionService", "No launch method for", action.name);
    }
  }

  function executeSession(action) {
    switch (action) {
    case "lock":
      CompositorService.lock();
      break;
    case "suspend":
      if (Settings.data.general.lockOnSuspend)
        CompositorService.lockAndSuspend();
      else
        CompositorService.suspend();
      break;
    case "hibernate":
      CompositorService.hibernate();
      break;
    case "reboot":
      CompositorService.reboot();
      break;
    case "rebootToUefi":
      CompositorService.rebootToUefi();
      break;
    case "userspaceReboot":
      CompositorService.userspaceReboot();
      break;
    case "logout":
      CompositorService.logout();
      break;
    case "shutdown":
      CompositorService.shutdown();
      break;
    }
  }
}
