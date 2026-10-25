import QtQuick
import QtQuick.Layouts
import "batteryOrder.js" as BatteryOrder
import "batteryData.js" as BatteryData
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Modules.Settings.Widgets
import qs.DCommon.Widgets as DCommon
import qs.Services
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "zmkBattery"

    readonly property string zmkBatteryGuideUrl: "https://v0-3-branch.zmk.dev/docs/config/battery"
    readonly property string scriptPath: pluginService ? pluginService.getPluginPath(pluginId) + "/getBattery.sh" : ""
    property string keyboardName: String(loadValue("keyboardName", "Corne-ish Zen"))
    property string selectedWidgetIcon: String(loadValue("widgetIcon",
        loadValue("showIcon", true) === false ? "" : "keyboard"))
    property var discoveredBatteries: []
    property var batteryOrder: loadValue("batteryOrder", [])
    readonly property var orderedBatteries: BatteryOrder.ordered(discoveredBatteries, batteryOrder)

    function saveBatteryOrder(indices) {
        var next = indices.map(index => orderedBatteries[index].id);
        // Retain disconnected devices so their preferences survive reconnecting.
        if (Array.isArray(batteryOrder))
            next = next.concat(batteryOrder.filter(value => next.indexOf(value) < 0));
        batteryOrder = next;
        saveValue("batteryOrder", next);
    }

    property var hiddenBatteryIds: loadValue("hiddenBatteryIds", [])

    function setBatteryVisible(id, shown) {
        var next = Array.isArray(hiddenBatteryIds) ? hiddenBatteryIds.filter(value => value !== id) : [];
        if (!shown)
            next.push(id);
        hiddenBatteryIds = next;
        saveValue("hiddenBatteryIds", next);
    }

    property var labelOverrides: BatteryData.parseLabelOverrides(loadValue("batteryLabels", "{}"))
    property bool batteryDiscoveryLoading: false
    property bool batteryDiscoveryPending: false
    property string batteryDiscoveryBuffer: ""
    property string batteryDiscoveryError: ""

    function hasOverride(id) {
        return Object.prototype.hasOwnProperty.call(labelOverrides, id);
    }

    function defaultLabel(battery) {
        var legacy;

        if (battery.legacyId && hasOverride(battery.legacyId))
            return String(labelOverrides[battery.legacyId]).trim();

        if ((battery.legacyId || battery.id) === "central") {
            legacy = loadValue("centralLabel", null);
            if (legacy !== null && legacy !== undefined)
                return String(legacy).trim();
        }

        if ((battery.legacyId || battery.id) === "peripheral:0") {
            legacy = loadValue("peripheralLabel", null);
            if (legacy !== null && legacy !== undefined)
                return String(legacy).trim();
        }

        return String(battery.name || battery.id).trim();
    }

    function resolvedLabel(battery) {
        return hasOverride(battery.id)
            ? String(labelOverrides[battery.id]).trim()
            : defaultLabel(battery);
    }

    function saveBatteryLabel(id, label) {
        var next = {};
        var keys = Object.keys(labelOverrides);
        for (var i = 0; i < keys.length; i++)
            next[keys[i]] = labelOverrides[keys[i]];

        next[id] = String(label).trim();
        labelOverrides = next;
        saveValue("batteryLabels", JSON.stringify(next));
    }

    function resetBatteryLabel(id) {
        var battery = discoveredBatteries.find(item => item.id === id);
        if (battery)
            saveBatteryLabel(id, battery.name);
    }

    function testLowBatteryNotification() {
        Proc.runCommand("zmkBattery.testNotification", [
            "dms", "notify", "-a", "ZmkBattery", "-i", "battery-low",
            "-u", "normal", "-t", "8000", "Low battery (test)",
            "Example device: 15% remaining. This is a test notification."
        ], (stdout, exitCode) => {
            if (exitCode !== 0)
                ToastService.showError("Could not send the test notification");
        });
    }

    function discoverBatteries() {
        if (!scriptPath)
            return;

        if (batteryDiscoveryProcess.running) {
            batteryDiscoveryPending = true;
            return;
        }

        batteryDiscoveryBuffer = "";
        batteryDiscoveryError = "";
        batteryDiscoveryLoading = true;
        batteryDiscoveryProcess.running = true;
    }

    Process {
        id: batteryDiscoveryProcess

        command: ["bash", root.scriptPath, root.keyboardName]
        running: false

        stdout: SplitParser {
            onRead: data => root.batteryDiscoveryBuffer += data + "\n"
        }

        stderr: SplitParser {
            onRead: data => {
                if (data.trim())
                    console.warn("[zmkBattery settings]", data.trim());
            }
        }

        onExited: (exitCode, exitStatus) => {
            var parsed = exitCode === 0
                ? BatteryData.parseBatteryOutput(root.batteryDiscoveryBuffer.trim())
                : null;

            root.batteryDiscoveryLoading = false;
            if (parsed === null) {
                root.discoveredBatteries = [];
                root.batteryDiscoveryError = "Battery discovery failed";
            } else {
                root.discoveredBatteries = parsed;
                if (parsed.length === 0)
                    root.batteryDiscoveryError = "Connect a device with a supported battery service to discover batteries";
            }

            if (root.batteryDiscoveryPending) {
                root.batteryDiscoveryPending = false;
                Qt.callLater(root.discoverBatteries);
            }
        }
    }

    Component.onCompleted: discoverBatteries()

    Connections {
        target: root

        function onPluginServiceChanged() {
            if (!root.pluginService)
                return;

            root.batteryOrder = root.loadValue("batteryOrder", []);
            root.hiddenBatteryIds = root.loadValue("hiddenBatteryIds", []);
            root.keyboardName = String(root.loadValue("keyboardName", "Corne-ish Zen"));
            root.labelOverrides = BatteryData.parseLabelOverrides(root.loadValue("batteryLabels", "{}"));
            Qt.callLater(root.discoverBatteries);
        }
    }

    DCommon.DCollapsibleSection {
        width: parent.width
        title: "Setup and requirements"
        expanded: false

        SettingsLinkRow {
            Layout.fillWidth: true
            title: "ZMK battery setup"
            subtitle: "Enable peripheral battery fetching and proxying to see both keyboard halves."
            url: root.zmkBatteryGuideUrl
        }

        SettingsNoteRow {
            Layout.fillWidth: true
            noteIconName: "info"
            tint: Theme.primary
            tintBackground: Theme.surfaceContainerHigh
            text: "Batteries are discovered automatically for connected Bluetooth devices, including ZMK keyboards (follow the setup above to show both halves). USB battery levels are read through Linux or the built-in Keychron reader.\n\nRequires bash, busctl, and jq, plus python3 for USB support. The Keychron reader also requires access to the receiver’s HID device."
        }
    }

    SettingsSectionLabel { text: "Devices and battery labels" }

    StyledText {
        width: parent.width
        text: "Drag to reorder, edit labels, or hide batteries. Leave a label empty to show only the percentage."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SettingsSectionLabel {
        visible: root.batteryDiscoveryLoading
        text: "Discovering batteries…"
    }

    SettingsNoteRow {
        visible: !root.batteryDiscoveryLoading && root.batteryDiscoveryError.length > 0
        text: root.batteryDiscoveryError
        noteIconName: "info"
    }

    SettingsReorderList {
        id: batteryList
        visible: !root.batteryDiscoveryLoading && root.discoveredBatteries.length > 0
        width: parent.width
        model: root.orderedBatteries
        onReordered: indices => root.saveBatteryOrder(indices)

        delegate: SettingsReorderRow {
            id: batteryRow
            required property var modelData
            reorderList: batteryList
            title: modelData.name
            singleLineTitle: true
            reorderEnabled: batteryList.count > 1
            modified: Array.isArray(root.hiddenBatteryIds) && root.hiddenBatteryIds.indexOf(modelData.id) >= 0
            resetByKeys: false
            onResetRequested: root.setBatteryVisible(modelData.id, true)

            DCommon.DTooltipV2 { id: deviceTooltip }
            HoverHandler {
                onHoveredChanged: {
                    if (hovered)
                        deviceTooltip.show(batteryRow.modelData.name + "\n" + batteryRow.modelData.id, batteryRow, 0, 0);
                    else
                        deviceTooltip.hide();
                }
            }

            SettingsTextFieldRow {
                id: batteryLabelField
                width: Math.min(batteryRow.width * 0.45,
                    Math.max(Theme.iconButtonSize * 3,
                        labelMetrics.advanceWidth + Theme.iconButtonSize * 2 + Theme.spacingL * 2))
                anchors.verticalCenter: parent.verticalCenter
                paddingH: 0
                paddingV: 0
                paintBackground: false
                text: "Label"
                value: root.resolvedLabel(batteryRow.modelData)
                leftIconName: "label"
                modified: root.resolvedLabel(batteryRow.modelData) !== batteryRow.modelData.name
                resetKeys: []
                onResetRequested: {
                    batteryLabelField.value = batteryRow.modelData.name;
                    root.resetBatteryLabel(batteryRow.modelData.id);
                }
                onEditingFinished: value => root.saveBatteryLabel(batteryRow.modelData.id, value)

                TextMetrics {
                    id: labelMetrics
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    text: batteryLabelField.value || batteryLabelField.text
                }

                Connections {
                    target: root
                    function onLabelOverridesChanged() {
                        if (!batteryLabelField.focusWithin)
                            batteryLabelField.value = root.resolvedLabel(batteryRow.modelData);
                    }
                }
            }

            DCommon.DToggle {
                anchors.verticalCenter: parent.verticalCenter
                text: "Show " + batteryRow.modelData.name + " in widget"
                hideText: true
                checked: !Array.isArray(root.hiddenBatteryIds) || root.hiddenBatteryIds.indexOf(batteryRow.modelData.id) < 0
                onToggled: checked => root.setBatteryVisible(batteryRow.modelData.id, checked)
            }
        }
    }

    SettingsSectionLabel { text: "Display" }

    SettingsGroup {
        SettingsToggleRow {
            text: "Hide % symbol"
            description: "Keep battery values visible without the percent sign"
            checked: root.loadValue("hidePercentages", false) === true
            modified: checked
            resetByKeys: false
            onResetRequested: root.saveValue("hidePercentages", false)
            onToggled: checked => root.saveValue("hidePercentages", checked)
        }

        SettingsTextFieldRow {
            id: separatorField
            text: "Separator"
            description: "Between readings on horizontal bars. Leave empty for no separator."
            value: String(root.loadValue("separator", "·"))
            placeholderText: "None"
            modified: value !== "·"
            resetKeys: []
            onResetRequested: {
                separatorField.value = "·";
                root.saveValue("separator", "·");
            }
            onEditingFinished: value => root.saveValue("separator", value)
        }

        SettingsRow {
            title: "Widget icon"
            resetKeys: []
            resetByKeys: false
            modified: root.selectedWidgetIcon !== "keyboard"
            onResetRequested: root.saveValue("widgetIcon", "keyboard")

            DCommon.DIconPicker {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(240, batteryList.width * 0.45)
                currentIcon: root.selectedWidgetIcon
                onIconSelected: (iconName, iconType) => root.saveValue("widgetIcon", iconName)
            }

            DCommon.DActionButton {
                buttonSize: Theme.iconButtonSize
                iconName: "close"
                Accessible.name: "Clear icon"
                tooltipText: "Clear icon"
                iconSize: Theme.iconSizeMedium
                iconColor: Theme.error
                anchors.verticalCenter: parent.verticalCenter
                enabled: root.selectedWidgetIcon.length > 0
                onClicked: root.saveValue("widgetIcon", "")
            }
        }

        SettingsSliderRow {
            text: "Refresh interval"
            modified: value !== 60
            resetByKeys: false
            onResetRequested: root.saveValue("refreshInterval", 60)
            description: "How often to query every battery"
            value: Number(root.loadValue("refreshInterval", 60))
            minimum: 10
            maximum: 600
            step: 1
            unit: "sec"
            onSliderValueChanged: newValue => root.saveValue("refreshInterval", newValue)
        }

        SettingsSliderRow {
            text: "Low battery warning"
            modified: value !== 20
            resetByKeys: false
            onResetRequested: root.saveValue("warningThreshold", 20)
            description: "Use the warning color at or below this percentage"
            value: Number(root.loadValue("warningThreshold", 20))
            minimum: 5
            maximum: 50
            step: 1
            unit: "%"
            onSliderValueChanged: newValue => root.saveValue("warningThreshold", newValue)
        }
        SettingsRow {
            title: "Test low battery notification"
            subtitle: "Send a sample notification without changing battery levels"
            DCommon.DButton {
                text: "Test"
                iconName: "notifications_active"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.testLowBatteryNotification()
            }
        }
    }
}
