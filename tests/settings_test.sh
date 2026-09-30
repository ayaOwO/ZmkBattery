#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

node - "$plugin_dir" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const pluginDir = process.argv[2];
const widget = fs.readFileSync(path.join(pluginDir, "ZmkBatteryWidget.qml"), "utf8");
const helperSource = widget.match(/    function normalizeNumericSetting\([\s\S]*?\n    }/);
assert.ok(helperSource, "normalization helper is present");
const normalizeNumericSetting = Function(`return (${helperSource[0].trim()})`)();

for (const value of [undefined, null, "", "   ", "not-a-number", "NaN", NaN, Infinity, -Infinity]) {
    assert.equal(normalizeNumericSetting(value, 60, 10, 600), 60, `refresh default for ${String(value)}`);
    assert.equal(normalizeNumericSetting(value, 20, 1, 99), 20, `warning default for ${String(value)}`);
}

assert.equal(normalizeNumericSetting(0, 60, 10, 600), 10);
assert.equal(normalizeNumericSetting("10.4", 60, 10, 600), 10);
assert.equal(normalizeNumericSetting("10.6", 60, 10, 600), 11);
assert.equal(normalizeNumericSetting(601, 60, 10), 601);
assert.equal(normalizeNumericSetting(0, 20, 1, 99), 1);
assert.equal(normalizeNumericSetting(42, 20, 1, 99), 42);
assert.equal(normalizeNumericSetting(100, 20, 1, 99), 99);

const expectedUrl = "https://v0-3-branch.zmk.dev/docs/config/battery";
const settings = fs.readFileSync(path.join(pluginDir, "ZmkBatterySettings.qml"), "utf8");
const readme = fs.readFileSync(path.join(pluginDir, "README.md"), "utf8");
assert.equal((settings.match(new RegExp(expectedUrl, "g")) || []).length, 1);
assert.equal((readme.match(new RegExp(expectedUrl, "g")) || []).length, 1);
assert.equal((settings + readme).includes("https://zmk.dev/docs/config/battery"), false);
NODE

printf 'settings tests passed\n'
