.pragma library

// Static schema metadata selects group boundaries. Unknown values stay raw and
// are never stringified or sent to the GUI; only bounded value-free paths leave
// this worker transform. Atomic records/lists/maps are deliberately not walked.
var transform = `function(input) {
  var groups = input.metadata.groups;
  var diagnostics = [];
  var truncated = false;
  function visit(value, path) {
    var fields = groups[JSON.stringify(path)];
    if (!fields || !value || typeof value !== "object" || Array.isArray(value)) return;
    Object.keys(value).forEach(function(key) {
      var next = path.concat([key]);
      if (fields.indexOf(key) === -1) {
        if (diagnostics.length < 64) diagnostics.push({code: "unknown-setting", path: next.slice(input.source.prefix.length), severity: "warning"});
        else truncated = true;
      } else if (Object.prototype.hasOwnProperty.call(groups, JSON.stringify(next))) visit(value[key], next);
    });
  }
  visit(input.raw, input.source.prefix);
  if (truncated) diagnostics.push({code: "unknown-setting-truncated", path: [], severity: "warning"});
  return {values: input.values, compatibilityRaw: input.compatibilityRaw, effects: [], diagnostics: diagnostics};
}`;
