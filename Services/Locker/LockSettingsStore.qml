import QtQuick
import Quickshell
import ConfigQml 1.0
import qs.Commons

// A native read-only consumer of one generation's published effective values.
// It has no user-preference routes, persistence effects or evidence writer.
ConfigStore {
  id: root
  required property string viewPath
  required property string session
  required property string generation
  readonly property var inputPaths: mainSchema.valuePaths
  autoSave: false
  schema: SettingsSchema {
    id: mainSchema
    homeDirectory: Quickshell.env("HOME")
    defaultFont: Application.font.family
    fixedFont: "monospace"
  }
  sources: [JsonFileSource {
    layerId: "published"
    sourceId: "published"
    path: root.viewPath
    writable: false
    optional: false
    watchMode: JsonFileSource.Live
  }]
  projections: [ConfigProjection {
    projectionId: "locker-generation-input"
    sourceIds: ["published"]
    metadata: ({session: root.session, generation: root.generation})
    transform: `function(input) {
      var raw = input.raw;
      var version = typeof raw.schema === "number" ? raw.schema : Number(raw.schema && raw.schema.decimal);
      if (version !== 1 || raw.session !== input.metadata.session ||
          raw.generation !== input.metadata.generation || !raw.values ||
          typeof raw.values !== "object" || Array.isArray(raw.values))
        throw new Error("locker-settings-generation");
      return {values: raw.values, compatibilityRaw: input.compatibilityRaw,
              effects: [], diagnostics: []};
    }`
  }]
}
