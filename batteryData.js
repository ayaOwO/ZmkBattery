.pragma library

function validLevel(level) {
    return typeof level === "number"
        && isFinite(level)
        && Math.floor(level) === level
        && level >= 0
        && level <= 100;
}

function parseLabelOverrides(value) {
    if (!value)
        return {};

    try {
        var parsed = typeof value === "string" ? JSON.parse(value) : value;
        return parsed && typeof parsed === "object" && !Array.isArray(parsed)
            ? parsed
            : {};
    } catch (error) {
        console.warn("[zmkBattery] Invalid battery label overrides:", error);
        return {};
    }
}

function parseBatteryOutput(output) {
    var parsed;

    try {
        parsed = JSON.parse(output);
    } catch (error) {
        return null;
    }

    if (!Array.isArray(parsed))
        return null;

    var normalized = [];
    var seenIds = {};
    for (var i = 0; i < parsed.length; i++) {
        var item = parsed[i];
        if (!item || typeof item.id !== "string" || !item.id.length
                || typeof item.name !== "string" || !item.name.length
                || Object.prototype.hasOwnProperty.call(seenIds, item.id)
                || (item.level !== null && !validLevel(item.level))) {
            return null;
        }

        seenIds[item.id] = true;
        normalized.push({
            id: item.id,
            name: item.name,
            legacyId: item.legacyId || "",
            supported: item.supported !== false,
            level: item.level
        });
    }

    return normalized;
}
