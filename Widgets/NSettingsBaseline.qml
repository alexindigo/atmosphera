import QtQuick
import "../Helpers/SettingsValues.js" as SettingsValues

// Consumers declare readonly typed display fields here. The native QML property
// owns coercion; edit initialization and comparison use that same projected value.
// This object has no preference copy, persistence handle or consumer reference.
QtObject {
  id: root

  function differs(currentValues) {
    var names = Object.keys(currentValues);
    for (var i = 0; i < names.length; ++i) {
      var name = names[i];
      if (!(name in root))
        throw new Error("Undeclared settings display baseline: " + name);
      if (!SettingsValues.equal(root[name], currentValues[name]))
        return true;
    }
    return false;
  }
}
