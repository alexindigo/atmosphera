import QtQuick
import qs.Commons
import qs.Services.UI

// MangoService — mangowc compositor integration via mangoqml (mmsg IPC).
// The backend (MangoServiceBackend.qml) is loaded via Loader so systems
// without qt6-mangowcqml installed degrade gracefully (empty workspaces,
// no windows) instead of failing to load.
Item {
  id: root

  // ===== PUBLIC INTERFACE (CompositorService compatibility) =====

  // Forwarded from the loaded backend, never copied: a copy would keep
  // the state of the moment it was taken.
  readonly property var _backend: backendLoader.status === Loader.Ready ? backendLoader.item : null
  readonly property ListModel workspaces: _backend ? _backend.workspaces : _emptyWorkspaces
  readonly property var windows: _backend ? _backend.windows : []
  readonly property var focusedWindowId: _backend ? _backend.focusedWindowId : null
  property bool initialized: false

  property ListModel _emptyWorkspaces: ListModel {}

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  // ===== MANGOSERVICE-SPECIFIC PROPERTIES =====

  readonly property string selectedMonitor: _backend ? _backend.selectedMonitor : ""
  readonly property string currentLayoutSymbol: _backend ? _backend.currentLayoutSymbol : ""

  // ===== BACKEND LOADER =====

  property bool _toastShown: false

  Loader {
    id: backendLoader
    active: false
    source: "MangoServiceBackend.qml"
    onStatusChanged: {
      if (status === Loader.Error) {
        Logger.w("MangoService", "mangowcqml unavailable — mangowc integration will not activate");
        if (!root._toastShown) {
          root._toastShown = true;
          ToastService.showWarning(I18n.tr("toast.mangowcqml-missing") || "Degraded mangowc experience", I18n.tr("toast.mangowcqml-missing-desc") || "Install qt6-mangowcqml to enable mangowc integration (workspaces, windows, session config).", 8000);
        }
      } else if (status === Loader.Ready) {
        // Forward signals
        backendLoader.item.workspaceChanged.connect(root.workspaceChanged);
        backendLoader.item.activeWindowChanged.connect(root.activeWindowChanged);
        backendLoader.item.windowListChanged.connect(root.windowListChanged);
        backendLoader.item.displayScalesChanged.connect(root.displayScalesChanged);

        root.initialized = true;
        Logger.i("MangoService", "mangowcqml backend loaded and initialized");
      }
    }
  }

  // Activate the backend when the service is initialized
  Component.onCompleted: {
    backendLoader.active = true;
  }

  // ===== PUBLIC API =====

  function initialize() {
    // Handled by Component.onCompleted
  }

  function switchToWorkspace(workspace) {
    if (backendLoader.item) {
      backendLoader.item.switchToWorkspace(workspace);
    }
  }

  function focusWindow(window) {
    if (backendLoader.item) {
      backendLoader.item.focusWindow(window);
    }
  }

  function closeWindow(window) {
    if (backendLoader.item) {
      backendLoader.item.closeWindow(window);
    }
  }

  function turnOffMonitors() {
    if (backendLoader.item) {
      backendLoader.item.turnOffMonitors();
    }
  }

  function turnOnMonitors() {
    if (backendLoader.item) {
      backendLoader.item.turnOnMonitors();
    }
  }

  function logout() {
    if (backendLoader.item) {
      backendLoader.item.logout();
    }
  }

  function spawn(command) {
    if (backendLoader.item) {
      backendLoader.item.spawn(command);
    }
  }

  function cycleKeyboardLayout() {
    if (backendLoader.item) {
      backendLoader.item.cycleKeyboardLayout();
    }
  }

  function getFocusedScreen() {
    if (backendLoader.item) {
      return backendLoader.item.getFocusedScreen();
    }
    return null;
  }
}
