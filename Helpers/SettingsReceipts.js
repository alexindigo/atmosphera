.pragma library

// Ordinary persistence has no editor refresh contract (native QString is empty).
// When an editor supplies one, only an explicitly current receipt is accepted.
function acknowledged(result) {
    return !!result && (result.status === "saved" || result.status === "nothing_to_save")
            && (result.refreshState === undefined || result.refreshState === "" || result.refreshState === "current");
}
