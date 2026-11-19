import QtQuick

QtObject {
  // Move only the old default. Explicit custom bindings (including an empty
  // list) retain their meaning and take precedence over launcher text editing.
  function migrate(adapter, logger, rawJson) {
    const remove = rawJson?.general?.keybinds?.keyRemove;
    if (Array.isArray(remove) && remove.length === 1 && remove[0] === "Del") {
      adapter.general.keybinds.keyRemove = ["Shift+Del"];
      logger.i("Settings", "Moved default Remove binding to Shift+Delete");
    }
    return true;
  }
}
