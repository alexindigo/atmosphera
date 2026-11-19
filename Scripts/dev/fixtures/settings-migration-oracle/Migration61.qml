import QtQuick

QtObject {
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v61 (add inputMethod section)");

    // Seed only what the file lacks; the adapter defaults in Settings.qml are the same values.
    var section = (rawJson && typeof rawJson.inputMethod === "object" && rawJson.inputMethod !== null) ? rawJson.inputMethod : {};

    if (!Array.isArray(section.switches))
      adapter.inputMethod.switches = [];
    if (!Array.isArray(section.nextKeys))
      adapter.inputMethod.nextKeys = [];
    if (typeof section.launchFcitx5 !== "boolean")
      adapter.inputMethod.launchFcitx5 = true;
    if (typeof section.legacyI18nChecked !== "boolean")
      adapter.inputMethod.legacyI18nChecked = false;

    return true;
  }
}
