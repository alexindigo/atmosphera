import QtQuick

QtObject {
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v60 (add bindings.environment default)");

    // Only set if not already present — a fresh install will already have "none"
    // via Settings.qml defaults; upgrades from v59 need it seeded.
    if (!rawJson || !rawJson.bindings || typeof rawJson.bindings.environment !== "string") {
      adapter.bindings.environment = "none";
      logger.i("Settings", "Set bindings.environment = \"none\"");
    }

    return true;
  }
}
