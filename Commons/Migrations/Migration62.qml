import QtQuick
import "SettingsMigrationSource.js" as MigrationSource

// Launcher regression compatibility wrapper, not a production migration owner.
// Execute the shared resource in test context with only the final step selected.
QtObject {
  function migrate(adapter, logger, rawJson) {
    var transform = eval("(" + MigrationSource.transform + ")");
    var result = transform({raw: {settingsVersion: 61, general: rawJson?.general},
      values: {}, compatibilityRaw: {}, lowerValues: {}, source: {presence: "present"}});
    var remove = result.values.general?.keybinds?.keyRemove;
    if (remove !== undefined) {
      adapter.general.keybinds.keyRemove = remove;
      logger.i("Settings", "Moved default Remove binding to Shift+Delete");
    }
    return true;
  }
}
