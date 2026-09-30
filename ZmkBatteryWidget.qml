import QtQuick
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

    property string keyboardName: pluginData.keyboardName || "Corne-ish Zen"
    property int refreshSeconds: normalizeNumericSetting(pluginData.refreshInterval, 60, 10)
    property int warningThreshold: normalizeNumericSetting(pluginData.warningThreshold, 20, 1, 99)
    property var labelOverrides: parseLabelOverrides(pluginData.batteryLabels)

    property var batteries: []
    property bool isLoading: true
    property bool parsedOutput: false
    property string outputBuffer: ""
    property string lastUpdated: ""
    property string errorText: ""
    property string scriptPath: PluginService.pluginDirectory + "/ZmkBattery/getBattery.sh"

    readonly property bool hasBattery: batteries.length > 0
    readonly property int lowestLevel: {
        var lowest = 101;
        for (var i = 0; i < batteries.length; i++) {
            var level = batteries[i].level;
            if (root.validLevel(level))
                lowest = Math.min(lowest, level);
        }
        return lowest <= 100 ? lowest : -1;
    }
    readonly property color statusColor: batteryColor(lowestLevel)

    pillClickAction: () => refreshBattery()

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

    function hasOverride(id) {
        return Object.prototype.hasOwnProperty.call(labelOverrides, id);
    }

    function batteryLabel(battery) {
        if (hasOverride(battery.id))
            return String(labelOverrides[battery.id]).trim();

        if (battery.id === "central" && pluginData.centralLabel !== undefined)
            return String(pluginData.centralLabel).trim();

        if (battery.id === "peripheral:0" && pluginData.peripheralLabel !== undefined)
            return String(pluginData.peripheralLabel).trim();

        return String(battery.name || battery.id).trim();
    }

    function validLevel(level) {
        return typeof level === "number"
            && isFinite(level)
            && Math.floor(level) === level
            && level >= 0
            && level <= 100;
    }

    function levelText(level) {
        return validLevel(level) ? level + "%" : "--%";
    }

    function batteryColor(level) {
        if (!validLevel(level))
            return Theme.surfaceVariantText;
        if (level <= 10)
            return Theme.error;
        if (level <= warningThreshold)
            return Theme.warning;
        return Theme.primary;
    }

    function parseOutput(output) {
        var parsed;

        try {
            parsed = JSON.parse(output);
        } catch (error) {
            console.warn("[zmkBattery] Invalid battery JSON:", error);
            return false;
        }

        if (!Array.isArray(parsed))
            return false;

        var normalized = [];
        var seenIds = {};

        for (var i = 0; i < parsed.length; i++) {
            var item = parsed[i];
            if (!item || typeof item.id !== "string" || !item.id.length
                    || typeof item.name !== "string" || !item.name.length
                    || Object.prototype.hasOwnProperty.call(seenIds, item.id)
                    || (item.level !== null && !validLevel(item.level))) {
                return false;
            }

            seenIds[item.id] = true;
            normalized.push({
                id: item.id,
                name: item.name,
                level: item.level
            });
        }

        batteries = normalized;
        return true;
    }

    function refreshBattery() {
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
                root.batteries = [];
                root.errorText = "Battery query failed";
                return;
            }

            if (!root.hasBattery)
                root.errorText = "Keyboard disconnected or battery services unavailable";

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
                name: root.isLoading ? "sync" : (root.hasBattery ? "keyboard" : "keyboard_off")
                size: root.iconSize
                color: root.isLoading ? Theme.surfaceVariantText : root.statusColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Row {
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    visible: root.batteries.length === 0
                    text: root.isLoading ? "…" : "--%"
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
                            visible: index > 0
                            text: "·"
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
                name: root.isLoading ? "sync" : (root.hasBattery ? "keyboard" : "keyboard_off")
                size: root.iconSize
                color: root.isLoading ? Theme.surfaceVariantText : root.statusColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Column {
                spacing: 1
                anchors.horizontalCenter: parent.horizontalCenter

                StyledText {
                    visible: root.batteries.length === 0
                    text: root.isLoading ? "…" : "--%"
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
                        text: (displayLabel.length > 0 ? displayLabel + " " : "")
                            + root.levelText(modelData.level)
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
