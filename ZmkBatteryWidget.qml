import QtQuick
import "batteryOrder.js" as BatteryOrder
import "batteryData.js" as BatteryData
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

PluginComponent {
    id: root

    function normalizeNumericSetting(value, defaultValue, minimum, maximum) {
        if (value === undefined || value === null
                || (typeof value === "string" && value.trim() === "")
                || (typeof value !== "number" && typeof value !== "string")) {
            return defaultValue;
        }

        var numericValue = Number(value);
        if (!isFinite(numericValue))
            return defaultValue;

        numericValue = Math.round(numericValue);
        numericValue = Math.max(minimum, numericValue);
        return maximum === undefined ? numericValue : Math.min(maximum, numericValue);
    }

    property bool hidePercentages: pluginData.hidePercentages === true
    property string separator: typeof pluginData.separator === "string" ? pluginData.separator : "·"
    property string widgetIcon: typeof pluginData.widgetIcon === "string"
        ? pluginData.widgetIcon.trim() : (pluginData.showIcon === false ? "" : "keyboard")
    readonly property bool showIcon: widgetIcon.length > 0
    property string keyboardName: pluginData.keyboardName || "Corne-ish Zen"
    property int refreshSeconds: normalizeNumericSetting(pluginData.refreshInterval, 60, 10)
    property int warningThreshold: normalizeNumericSetting(pluginData.warningThreshold, 20, 1, 99)
    property var labelOverrides: BatteryData.parseLabelOverrides(pluginData.batteryLabels)

    property var allBatteries: []
    property var hiddenBatteryIds: {
        try {
            var value = pluginData.hiddenBatteryIds || [];
            return typeof value === "string" ? JSON.parse(value) : value;
        } catch (error) {
            return [];
        }
    }
    readonly property var orderedBatteries: BatteryOrder.ordered(allBatteries, pluginData.batteryOrder)
    readonly property var batteries: orderedBatteries.filter(battery =>
        battery.supported && (!Array.isArray(hiddenBatteryIds) || hiddenBatteryIds.indexOf(battery.id) < 0))
    property bool isLoading: true
    property bool parsedOutput: false
    property string outputBuffer: ""
    property string lastUpdated: ""
    property string errorText: ""
    property string scriptPath: pluginService ? pluginService.getPluginPath(pluginId) + "/getBattery.sh" : ""

    readonly property bool hasBattery: batteries.length > 0
    visible: hasBattery

    onHasBatteryChanged: root.setVisibilityOverride(hasBattery)
    Component.onCompleted: root.setVisibilityOverride(hasBattery)

    readonly property int lowestLevel: {
        var lowest = 101;
        for (var i = 0; i < batteries.length; i++) {
            var level = batteries[i].level;
            if (BatteryData.validLevel(level))
                lowest = Math.min(lowest, level);
        }
        return lowest <= 100 ? lowest : -1;
    }
    readonly property color statusColor: batteryColor(lowestLevel)

    pillClickAction: () => refreshBattery()

    function hasOverride(id) {
        return Object.prototype.hasOwnProperty.call(labelOverrides, id);
    }

    function batteryLabel(battery) {
        if (hasOverride(battery.id))
            return String(labelOverrides[battery.id]).trim();

        if (battery.legacyId && hasOverride(battery.legacyId))
            return String(labelOverrides[battery.legacyId]).trim();

        if ((battery.legacyId || battery.id) === "central" && pluginData.centralLabel !== undefined)
            return String(pluginData.centralLabel).trim();

        if ((battery.legacyId || battery.id) === "peripheral:0" && pluginData.peripheralLabel !== undefined)
            return String(pluginData.peripheralLabel).trim();

        return String(battery.name || battery.id).trim();
    }

    function levelText(level) {
        return (BatteryData.validLevel(level) ? String(level) : "--") + (hidePercentages ? "" : "%");
    }

    function batteryColor(level) {
        if (!BatteryData.validLevel(level))
            return Theme.surfaceVariantText;
        if (level <= 10)
            return Theme.error;
        if (level <= warningThreshold)
            return Theme.warning;
        return Theme.primary;
    }

    function parseOutput(output) {
        var parsed = BatteryData.parseBatteryOutput(output);
        if (parsed === null)
            return false;

        allBatteries = parsed;
        return true;
    }

    function refreshBattery() {
        if (!scriptPath)
            return;

        if (batteryProcess.running)
            return;

        parsedOutput = false;
        outputBuffer = "";
        errorText = "";
        isLoading = true;
        batteryProcess.running = true;
    }

    Process {
        id: batteryProcess

        command: ["bash", root.scriptPath, root.keyboardName]
        running: false

        stdout: SplitParser {
            onRead: data => root.outputBuffer += data + "\n"
        }

        stderr: SplitParser {
            onRead: data => {
                if (data.trim())
                    console.warn("[zmkBattery]", data.trim());
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.isLoading = false;
            root.parsedOutput = exitCode === 0 && root.parseOutput(root.outputBuffer.trim());

            if (!root.parsedOutput) {
                root.allBatteries = [];
                root.errorText = "Battery query failed";
                return;
            }

            if (!root.hasBattery)
                root.errorText = "Devices disconnected or battery services unavailable";

            root.lastUpdated = new Date().toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
        }
    }

    Timer {
        id: refreshTimer

        interval: root.refreshSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshBattery()
    }

    Timer {
        id: settingsRefreshTimer

        interval: 100
        repeat: false
        onTriggered: root.refreshBattery()
    }

    Connections {
        target: pluginService
        enabled: pluginService !== null

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                settingsRefreshTimer.restart();
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            DankIcon {
                visible: root.showIcon
                name: root.isLoading ? "sync" : (root.hasBattery ? root.widgetIcon : "keyboard_off")
                size: root.iconSize
                color: root.isLoading ? Theme.surfaceVariantText : root.statusColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Row {
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    visible: root.batteries.length === 0
                    text: root.isLoading ? "…" : root.levelText(null)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }

                Repeater {
                    model: root.batteries

                    Row {
                        required property int index
                        required property var modelData
                        readonly property string displayLabel: root.batteryLabel(modelData)
                        spacing: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            visible: index > 0 && root.separator.length > 0
                            text: root.separator
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.outline
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            visible: parent.displayLabel.length > 0
                            text: parent.displayLabel
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: root.levelText(modelData.level)
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: root.batteryColor(modelData.level)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                visible: root.showIcon
                name: root.isLoading ? "sync" : (root.hasBattery ? root.widgetIcon : "keyboard_off")
                size: root.iconSize
                color: root.isLoading ? Theme.surfaceVariantText : root.statusColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Column {
                spacing: 1
                anchors.horizontalCenter: parent.horizontalCenter

                StyledText {
                    visible: root.batteries.length === 0
                    text: root.isLoading ? "…" : root.levelText(null)
                    font.pixelSize: Math.max(8, Math.round(Theme.fontSizeSmall * 0.8))
                    font.weight: Font.DemiBold
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Repeater {
                    model: root.batteries

                    StyledText {
                        required property var modelData
                        readonly property string displayLabel: root.batteryLabel(modelData)
                        text: (displayLabel.length > 0 ? displayLabel + " " : "") + root.levelText(modelData.level)
                        font.pixelSize: Math.max(8, Math.round(Theme.fontSizeSmall * 0.8))
                        font.weight: Font.DemiBold
                        color: root.batteryColor(modelData.level)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }
}
