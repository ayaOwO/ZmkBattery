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

const vm = require("node:vm");
const batteryData = { console };
vm.createContext(batteryData);
vm.runInContext(fs.readFileSync(path.join(pluginDir, "batteryData.js"), "utf8").replace(/^\.pragma library\s*/, ""), batteryData);
const context = { allBatteries: [], console, BatteryData: batteryData };
vm.createContext(context);
for (const name of ["parseOutput"]) {
    const source = widget.match(new RegExp(`    function ${name}\\([\\s\\S]*?\\n    }`));
    assert.ok(source);
    vm.runInContext(source[0], context);
}
const sample = [{ id: "bluetooth:test:central", name: "Board", legacyId: "central", level: 75 },
                { id: "usb:test:mouse:port", name: "Mouse", level: 96 }];
assert.equal(context.parseOutput(JSON.stringify(sample)), true);
assert.equal(context.allBatteries[0].legacyId, "central");
assert.equal(context.allBatteries[1].supported, true);
for (const invalid of ["not json", "{}", "null", JSON.stringify([...sample, sample[0]]),
        ...[-1, 101, 1.5, "42", undefined].map(level => JSON.stringify([{id: "x", name: "X", level}])),
        JSON.stringify([{id: "", name: "X", level: 50}])]) {
    assert.equal(batteryData.parseBatteryOutput(invalid), null);
    assert.equal(context.parseOutput(invalid), false);
    assert.equal(context.allBatteries.length, sample.length, "invalid output leaves state untouched");
}
assert.equal(batteryData.parseBatteryOutput("[]").length, 0);
assert.equal(batteryData.parseBatteryOutput('[{"id":"x","name":"X","level":null}]')[0].level, null);
assert.equal(batteryData.parseLabelOverrides('{"central":"Left"}').central, "Left");
for (const value of [null, "[]", "null", "42"])
    assert.equal(Object.keys(batteryData.parseLabelOverrides(value)).length, 0);
const filter = widget.match(/orderedBatteries\.filter\(battery =>\n[^\n]+/)[0].trim();
Object.defineProperty(context, "orderedBatteries", { get: () => context.allBatteries });
context.hiddenBatteryIds = [sample[0].id];
assert.equal(vm.runInContext(filter, context).length, 1);
assert.equal(vm.runInContext(filter, context)[0].name, "Mouse");
context.hiddenBatteryIds = sample.map(item => item.id);
assert.equal(vm.runInContext(filter, context).length, 0);
context.hiddenBatteryIds = [];
assert.equal(vm.runInContext(filter, context).length, 2);
context.parseOutput(JSON.stringify([...sample, {id: "usb:audio", name: "USB audio", level: null, supported: false}]));
assert.equal(vm.runInContext(filter, context).length, 2);

const expectedUrl = "https://v0-3-branch.zmk.dev/docs/config/battery";
const settings = fs.readFileSync(path.join(pluginDir, "ZmkBatterySettings.qml"), "utf8");
assert.ok(settings.includes("BatteryData.parseBatteryOutput(root.batteryDiscoveryBuffer.trim())"));
assert.ok(settings.includes('BatteryData.parseLabelOverrides(root.loadValue("batteryLabels", "{}"))'));
const readme = fs.readFileSync(path.join(pluginDir, "README.md"), "utf8");
const visibilitySource = settings.match(/    function setBatteryVisible\([\s\S]*?\n    }/)[0];
const settingsContext = { hiddenBatteryIds: [], saveValue: (key, value) => { assert.equal(key, "hiddenBatteryIds"); } };
vm.createContext(settingsContext);
vm.runInContext(visibilitySource, settingsContext);
settingsContext.setBatteryVisible("mouse", false);
assert.equal(settingsContext.hiddenBatteryIds[0], "mouse");
settingsContext.setBatteryVisible("mouse", false);
assert.equal(settingsContext.hiddenBatteryIds.length, 1);
settingsContext.setBatteryVisible("mouse", true);
assert.equal(settingsContext.hiddenBatteryIds.length, 0);
const orderContext = {};
vm.createContext(orderContext);
vm.runInContext(fs.readFileSync(path.join(pluginDir, "batteryOrder.js"), "utf8").replace(/^\.pragma library\s*/, ""), orderContext);
const list = [{id: "a"}, {id: "b"}, {id: "c"}];
const ids = value => Array.from(value, item => item.id);
assert.deepEqual(ids(orderContext.ordered(list, ["b", "a"])), ["b", "a", "c"]);
assert.deepEqual(ids(orderContext.ordered(list, undefined)), ["a", "b", "c"]);
assert.deepEqual(ids(orderContext.ordered([list[0], list[2]], ["b", "a"])), ["a", "c"]);
assert.deepEqual(ids(list), ["a", "b", "c"]);
const saveOrderSource = settings.match(/    function saveBatteryOrder\([\s\S]*?\n    }/)[0];
const reorderContext = { batteryOrder: ["offline"], orderedBatteries: list, saveValue: (key, value) => { assert.equal(key, "batteryOrder"); } };
vm.createContext(reorderContext);
vm.runInContext(saveOrderSource, reorderContext);
reorderContext.saveBatteryOrder([2, 0, 1]);
assert.deepEqual(Array.from(reorderContext.batteryOrder), ["c", "a", "b", "offline"]);
assert.deepEqual(ids(orderContext.ordered(list, reorderContext.batteryOrder)), ["c", "a", "b"]);
reorderContext.orderedBatteries = orderContext.ordered(list, reorderContext.batteryOrder);
reorderContext.saveBatteryOrder([0, 2, 1]);
assert.deepEqual(Array.from(reorderContext.batteryOrder), ["c", "b", "a", "offline"]);
const resetLabelSource = settings.match(/    function resetBatteryLabel\([\s\S]*?\n    }/)[0];
let resetLabel;
const resetContext = { discoveredBatteries: [{id: "board", name: "Original name"}],
    saveBatteryLabel: (id, label) => { resetLabel = [id, label]; } };
vm.createContext(resetContext);
vm.runInContext(resetLabelSource, resetContext);
resetContext.resetBatteryLabel("board");
assert.deepEqual(resetLabel, ["board", "Original name"]);
let notificationCommand;
const notificationContext = { Proc: { runCommand: (id, command, callback) => {
    notificationCommand = Array.from(command);
    callback("", 0);
} }, ToastService: { showError: () => assert.fail("notification should succeed") } };
vm.createContext(notificationContext);
vm.runInContext(settings.match(/    function testLowBatteryNotification\([\s\S]*?\n    }/)[0], notificationContext);
notificationContext.testLowBatteryNotification();
assert.deepEqual(notificationCommand.slice(0, 2), ["dms", "notify"]);
assert.ok(notificationCommand.includes("Low battery (test)"));
vm.runInContext(widget.match(/    function levelText\([\s\S]*?\n    }/)[0], context);
context.hidePercentages = false;
assert.equal(context.levelText(96), "96%");
assert.equal(context.levelText(null), "--%");
context.hidePercentages = true;
assert.equal(context.levelText(96), "96");
assert.equal(context.levelText(0), "0");
assert.equal(context.levelText(100), "100");
assert.equal(context.levelText(null), "--");
assert.equal((settings.match(new RegExp(expectedUrl, "g")) || []).length, 1);
assert.equal((readme.match(new RegExp(expectedUrl, "g")) || []).length, 1);
assert.equal((settings + readme).includes("https://zmk.dev/docs/config/battery"), false);
NODE

printf 'settings tests passed\n'
