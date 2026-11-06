import QtQuick
import "../Helpers/SettingsValues.js" as SettingsValues

// Consumers declare readonly typed inputs here. Native QML owns scalar coercion;
// optional control ranges are applied once for both initialization and comparison.
// This object has no preference copy, persistence handle or consumer reference.
QtObject {
  id: root
  property list<NSettingsRange> ranges

  function project(name) {
    if (!(name in root))
      throw new Error("Undeclared settings display baseline: " + name);
    var value = root[name];
    var range = null;
    for (var candidate of ranges) {
      if (candidate.field === name) {
        range = candidate;
        break;
      }
    }
    if (!range)
      return value;
    return range.project(value);
  }

  function differs(currentValues) {
    var names = Object.keys(currentValues);
    for (var i = 0; i < names.length; ++i) {
      var name = names[i];
      if (!SettingsValues.equal(root.project(name), currentValues[name]))
        return true;
    }
    return false;
  }
}
