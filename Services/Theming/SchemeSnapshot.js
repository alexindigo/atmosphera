.pragma library

// Structural shell-snapshot contract, shared by all QML consumers. This does
// not derive colours: missing standout fields still belong to Python's rule.
var roleKeys = ["mPrimary", "mOnPrimary", "mSecondary", "mOnSecondary", "mTertiary", "mOnTertiary", "mStandout", "mOnStandout", "mError", "mOnError", "mSurface", "mOnSurface", "mSurfaceVariant", "mOnSurfaceVariant", "mOutline", "mShadow", "mHover", "mOnHover"];
// These two roles were optional in the14-core format. Match the historical
// shell defaults explicitly, rather than inheriting another scheme's values.
var legacyDefaults = {mShadow: "#000000", mOnHover: "#ffffff"};

function object(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function prepare(data) {
    if (!object(data))
        return {error: "Expected a shell scheme object"};
    var input = JSON.parse(JSON.stringify(data));
    var multi = !!(input.dark || input.light);
    var result = multi ? input : {};
    var complete = true;
    for (var mode of ["dark", "light"]) {
        var variant = multi ? (input[mode] || input[mode === "dark" ? "light" : "dark"]) : input;
        if (!object(variant))
            return {error: "Expected an object for " + mode};
        variant = JSON.parse(JSON.stringify(variant));
        for (var key of roleKeys) {
            var alias = key[1].toLowerCase() + key.slice(2);
            var snake = alias.replace(/[A-Z]/g, c => "_" + c.toLowerCase());
            if (variant[key] === undefined)
                variant[key] = variant[alias] !== undefined ? variant[alias] : variant[snake];
            if (variant[key] === undefined && key in legacyDefaults)
                variant[key] = legacyDefaults[key];
            if (variant[key] === undefined) {
                if (key === "mStandout" || key === "mOnStandout") {
                    complete = false;
                    continue;
                }
                return {error: "Missing shell colour " + mode + "." + key};
            }
            if (typeof variant[key] !== "string" || !/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(variant[key]))
                return {error: "Invalid shell colour " + mode + "." + key};
        }
        result[mode] = variant;
    }
    return {data: result, complete: complete, error: ""};
}
