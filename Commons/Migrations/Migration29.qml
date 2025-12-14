import QtQuick

QtObject {
  id: root

  // Migrate bar.backgroundOpacity to ui.panelBackgroundOpacity
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v29");

    // Check rawJson for old property (adapter doesn't expose removed properties)
    if (rawJson?.bar?.backgroundOpacity !== undefined) {
      adapter.ui.panelBackgroundOpacity = Math.max(0.4, rawJson.bar.backgroundOpacity);
      adapter.bar.transparent = (rawJson.bar.backgroundOpacity < 0.1);
      logger.i("Settings", "Migrated bar.backgroundOpacity to ui.panelBackgroundOpacity: " + adapter.ui.panelBackgroundOpacity);
    }

    return true;
  }
}
