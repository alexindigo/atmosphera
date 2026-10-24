pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.Keyboard

// Committed work contains data, never a callback owned by a launcher/provider.
Singleton {
  id: root
  property var pending: []
  property var pasteSessions: []
  property var releasingSessions: []
  // A committed paste never fires late: a job whose destination has not
  // regained the keyboard within this time after the launcher released it
  // (or when a new launcher session starts) only copies its payload.
  readonly property int pasteDeadlineMs: 2000

  Timer {
    id: deadlineTimer
    repeat: false
    onTriggered: root.drain()
  }

  Component {
    id: pasteSession
    LauncherPasteSession {
      id: lease
      onKeyboardReleased: {
        root.releaseRetention(lease);
        root.settle(lease);
        Qt.callLater(root.drain);
      }
    }
  }

  function beginSession(screen) {
    // A new launcher session ends every earlier committed paste copy-only.
    let superseded = false;
    for (const action of pending) {
      if (action.session && !action.expired) {
        action.expired = true;
        superseded = true;
      }
    }
    if (superseded)
      Qt.callLater(root.drain);
    const target = CompositorService.getFocusedWindow();
    const session = pasteSession.createObject(root, {screen: screen, targetId: target ? target.id : null});
    pasteSessions = pasteSessions.concat([session]);
    return session;
  }
  function attachWindow(session, window, screen) {
    if (session && !session.retired) {
      if (screen !== undefined)
        session.screen = screen;
      session.sourceWindow = window;
    }
  }
  // Close, queue completion (paste, copy-only, deadline, cancellation,
  // closed destination) and native release all end here; nothing else
  // retires a session.
  function finishSession(session) {
    if (!session || session.retired)
      return;
    session.closeRequested = true;
    session.checkRelease();
    settle(session);
  }
  // The one retirement rule: a closed session retires only when it has no
  // queued job and owes no native release. A source that committed a paste
  // keeps its window (retainsScreen) until the compositor acknowledges the
  // keyboard release, however its jobs ended and however often it is finished.
  function settle(session) {
    if (!session || session.retired || !session.closeRequested || session.queued !== 0 || owesRelease(session))
      return;
    session.retired = true;
    pasteSessions = pasteSessions.filter(item => item !== session);
    session.destroy();
  }
  function owesRelease(session) {
    return releasingSessions.indexOf(session) !== -1;
  }
  function deadlineOf(action) {
    const session = action.session;
    return session && session.released ? Math.max(session.releasedAt, action.enqueuedAt) + pasteDeadlineMs : Infinity;
  }
  function expireDue(now) {
    for (const action of pending) {
      if (action.session && !action.expired && now >= deadlineOf(action))
        action.expired = true;
    }
  }
  // One timer, armed for the earliest outstanding deadline.
  function scheduleDeadline() {
    let next = Infinity;
    for (const action of pending) {
      if (action.session && !action.expired)
        next = Math.min(next, deadlineOf(action));
    }
    deadlineTimer.stop();
    if (next !== Infinity) {
      deadlineTimer.interval = Math.max(1, next - Date.now());
      deadlineTimer.start();
    }
  }
  function retainsScreen(screen) {
    return releasingSessions.some(session => session.screen === screen);
  }
  function releaseRetention(session) {
    if (releasingSessions.indexOf(session) !== -1)
      releasingSessions = releasingSessions.filter(item => item !== session);
  }
  function pasteReady(action) {
    const session = action.session;
    const target = CompositorService.getFocusedWindow();
    return session && session.released && Qt.application.state !== Qt.ApplicationActive
        && (!destinationExists(session) || (target && target.id === session.targetId)) && !ClipboardService.pasting;
  }
  function destinationExists(session) {
    for (let i = 0; i < CompositorService.windows.count; i++) {
      if (CompositorService.windows.get(i).id === session.targetId)
        return true;
    }
    return false;
  }

  Connections {
    target: Qt.application
    function onStateChanged() { Qt.callLater(root.drain); }
  }
  Connections {
    target: CompositorService
    function onActiveWindowChanged() { Qt.callLater(root.drain); }
    function onWindowListChanged() { Qt.callLater(root.drain); }
  }
  Connections {
    target: ClipboardService
    function onPastingChanged() {
      if (!ClipboardService.pasting)
        Qt.callLater(root.drain);
    }
  }

  function enqueue(action) {
    pending = pending.concat([action]);
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
    enqueue({kind: "command", expression: String(expression)});
  }
  function pasteText(text, session) {
    enqueuePaste({kind: "text", text: String(text)}, session);
  }
  function pasteClipboard(id, mime, session) {
    enqueuePaste({kind: "clipboard", id: String(id), mime: String(mime || "")}, session);
  }
  function enqueuePaste(action, session) {
    if (!session || session.retired)
      throw new Error("A committed launcher paste requires its focus session");
    session.queued++;
    if (!session.released && releasingSessions.indexOf(session) === -1)
      releasingSessions = releasingSessions.concat([session]);
    action.session = session;
    action.enqueuedAt = Date.now();
    action.expired = false;
    enqueue(action);
  }
  function openSettings(entry, screen) {
    enqueue({kind: "settings", entry: JSON.parse(JSON.stringify(entry)), screen: screen});
  }
  function focusWindow(id) {
    enqueue({kind: "window", id: id});
  }
  function sessionAction(action) {
    enqueue({kind: "session", action: String(action)});
  }

  function drain() {
    expireDue(Date.now());
    const actions = pending;
    pending = [];
    for (const action of actions) {
      const paste = action.kind === "text" || action.kind === "clipboard";
      // An expired job only copies; it still waits for the clipboard process.
      if (paste && (action.expired ? ClipboardService.pasting : !pasteReady(action))) {
        pending = pending.concat([action]);
        continue;
      }
      const copyOnly = paste && (action.expired || !destinationExists(action.session));
      switch (action.kind) {
      case "application":
        executeApplication(action);
        break;
      case "command":
        Quickshell.execDetached(["sh", "-c", action.expression]);
        break;
      case "text":
        if (copyOnly)
          ClipboardService.copyText(action.text);
        else
          ClipboardService.pasteText(action.text);
        break;
      case "clipboard":
        if (copyOnly)
          ClipboardService.copyToClipboard(action.id, action.mime);
        else
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
      if (paste) {
        action.session.queued--;
        settle(action.session);
      }
    }
    scheduleDeadline();
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
