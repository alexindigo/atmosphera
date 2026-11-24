.pragma library

// The only table that lists what each plugin entry point receives besides
// `pluginApi` (shared-loader design, section 3.1). Order is the contract order.
var ENTRY_POINTS = [
    "main",
    "barWidget",
    "controlCenterWidget",
    "desktopWidget",
    "panel",
    "settings",
    "desktopWidgetSettings",
    "launcherProvider"
];

var CONTEXT_NAMES = {
    "main": [],
    "barWidget": ["screen", "widgetId", "section", "sectionWidgetIndex", "sectionWidgetsCount"],
    "controlCenterWidget": ["screen", "widgetId", "section", "sectionWidgetIndex", "sectionWidgetsCount", "widgetSettings"],
    "desktopWidget": ["screen", "widgetData", "widgetIndex"],
    "panel": ["screen"],
    "settings": [],
    "desktopWidgetSettings": ["widgetSettings"],
    "launcherProvider": []
};

function entryPoints() {
    return ENTRY_POINTS.slice();
}

// A generic Settings page is an editor consumer, never a runtime writer.
function apiRole(entryPoint) {
    return entryPoint === "settings" ? "settings-editor" : "runtime";
}

function acceptsApi(entryPoint, api) {
    return apiRole(entryPoint) !== "settings-editor" ||
        (api !== null && api !== undefined && api.apiRole === "settings-editor" &&
         typeof api.field === "function" && typeof api.contentField === "function");
}

// Unknown entry points (including inherited Object.prototype keys) give [].
function contextNames(entryPoint) {
    if (typeof entryPoint !== "string" || !Object.prototype.hasOwnProperty.call(CONTEXT_NAMES, entryPoint))
        return [];
    return CONTEXT_NAMES[entryPoint].slice();
}
