import QtQuick
import ConfigQml 1.0
import "Migrations/SettingsMigrationSource.js" as MigrationSource
import "Migrations/SettingsDiagnosticsSource.js" as DiagnosticsSource

// The sole main preference owner. All declarations are complete before the
// worker starts; registry updates change projections, never persistence intent.
ConfigStore {
  readonly property var inputPaths: mainSchema.valuePaths
  id: root
  required property string legacyFile
  required property string overridesDirectory
  required property string evidencePath
  required property string homeDirectory
  required property string defaultFont
  required property string fixedFont
  autoSave: true
  autoSaveInterval: 500
  evidenceDirectory: evidencePath
  observedPaths: [["bindings", "environment"]]
  schema: SettingsSchema {
    id: mainSchema
    homeDirectory: root.homeDirectory
    defaultFont: root.defaultFont
    fixedFont: root.fixedFont
  }
  property SettingsSources declarations: SettingsSources {
    settingsFile: root.legacyFile
    overridesDirectory: root.overridesDirectory
  }
  property SettingsRecordListPolicies policies: SettingsRecordListPolicies {}
  sources: declarations.sources
  recordListPolicies: policies.policies
  projections: [
    ConfigProjection {
      projectionId: "settings-migrations"
      sourceIds: ["legacy"]
      transform: MigrationSource.transform
    },
    ConfigProjection {
      projectionId: "settings-diagnostics"
      sourceIds: mainSchema.sourceIds
      metadata: ({groups: mainSchema.groupFields})
      transform: DiagnosticsSource.transform
    }
  ]
}
