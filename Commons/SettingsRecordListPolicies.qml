import ConfigQml 1.0
import QtQml

// Immutable declarations. Registry metadata is supplied to the worker separately.
QtObject {
  property list<ConfigRecordListPolicy> policies: [
    ConfigRecordListPolicy {
      policyId: "bar-left"
      path: ["bar", "widgets", "left"]
      keyField: "id"
      preservedFields: ["instanceSettings"]
      pruneUnknown: true
      normalizeFields: true
    },
    ConfigRecordListPolicy {
      policyId: "bar-center"
      path: ["bar", "widgets", "center"]
      keyField: "id"
      preservedFields: ["instanceSettings"]
      pruneUnknown: true
      normalizeFields: true
    },
    ConfigRecordListPolicy {
      policyId: "bar-right"
      path: ["bar", "widgets", "right"]
      keyField: "id"
      preservedFields: ["instanceSettings"]
      pruneUnknown: true
      normalizeFields: true
    },
    ConfigRecordListPolicy {
      policyId: "shortcuts-left"
      path: ["controlCenter", "shortcuts", "left"]
      keyField: "id"
      pruneUnknown: true
    },
    ConfigRecordListPolicy {
      policyId: "shortcuts-right"
      path: ["controlCenter", "shortcuts", "right"]
      keyField: "id"
      pruneUnknown: true
    },
    ConfigRecordListPolicy {
      policyId: "bar-screens"
      path: ["bar", "screenOverrides"]
      keyField: "name"
    },
    ConfigRecordListPolicy {
      policyId: "screen-left"
      path: ["bar", "screenOverrides"]
      keyField: "id"
      listPath: [
        {
          each: true
        },
        {
          key: "widgets"
        },
        {
          key: "left"
        }
      ]
    },
    ConfigRecordListPolicy {
      policyId: "screen-center"
      path: ["bar", "screenOverrides"]
      keyField: "id"
      listPath: [
        {
          each: true
        },
        {
          key: "widgets"
        },
        {
          key: "center"
        }
      ]
    },
    ConfigRecordListPolicy {
      policyId: "screen-right"
      path: ["bar", "screenOverrides"]
      keyField: "id"
      listPath: [
        {
          each: true
        },
        {
          key: "widgets"
        },
        {
          key: "right"
        }
      ]
    },
    ConfigRecordListPolicy {
      policyId: "desktop-monitors"
      path: ["desktopWidgets", "monitorWidgets"]
      keyField: "name"
    },
    ConfigRecordListPolicy {
      policyId: "desktop-widgets"
      path: ["desktopWidgets", "monitorWidgets"]
      keyField: "id"
      listPath: [
        {
          each: true
        },
        {
          key: "widgets"
        }
      ]
      pruneUnknown: true
    }
  ]
}
