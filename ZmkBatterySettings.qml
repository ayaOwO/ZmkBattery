import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "zmkBattery"

    readonly property string discoverCommand: "bluetoothctl devices"
    readonly property string zmkBatteryGuideUrl: "https://v0-3-branch.zmk.dev/docs/config/battery"
    readonly property string scriptPath: PluginService.pluginDirectory + "/ZmkBattery/getBattery.sh"
    property bool discoverCommandCopied: false
    property string keyboardName: String(loadValue("keyboardName", "Corne-ish Zen"))
    property var discoveredBatteries: []
    property var labelOverrides: parseLabelOverrides(loadValue("batteryLabels", "{}"))
    property bool batteryDiscoveryLoading: false
    property bool batteryDiscoveryPending: false
    property string batteryDiscoveryBuffer: ""
    property string batteryDiscoveryError: ""

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

    function defaultLabel(battery) {
        var legacy;

        if (battery.id === "central") {
            legacy = loadValue("centralLabel", null);
            if (legacy !== null && legacy !== undefined)
                return String(legacy).trim();
        }

        if (battery.id === "peripheral:0") {
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
        var next = {};
        var keys = Object.keys(labelOverrides);
        for (var i = 0; i < keys.length; i++) {
            if (keys[i] !== id)
                next[keys[i]] = labelOverrides[keys[i]];
        }

        labelOverrides = next;
        saveValue("batteryLabels", JSON.stringify(next));
    }

    function validLevel(level) {
        return typeof level === "number"
            && isFinite(level)
            && Math.floor(level) === level
            && level >= 0
            && level <= 100;
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
                level: item.level
            });
        }

        return normalized;
    }

    function discoverBatteries() {
        if (batteryDiscoveryProcess.running) {
            batteryDiscoveryPending = true;
            return;
        }

        batteryDiscoveryBuffer = "";
        batteryDiscoveryError = "";
        batteryDiscoveryLoading = true;
        batteryDiscoveryProcess.running = true;
    }

    Timer {
        id: copiedReset
        interval: 1600
        onTriggered: root.discoverCommandCopied = false
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
                ? root.parseBatteryOutput(root.batteryDiscoveryBuffer.trim())
                : null;

            root.batteryDiscoveryLoading = false;
            if (parsed === null) {
                root.discoveredBatteries = [];
                root.batteryDiscoveryError = "Battery discovery failed";
            } else {
                root.discoveredBatteries = parsed;
                if (parsed.length === 0)
                    root.batteryDiscoveryError = "Connect the keyboard to discover its batteries";
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

            root.keyboardName = String(root.loadValue("keyboardName", "Corne-ish Zen"));
            root.labelOverrides = root.parseLabelOverrides(root.loadValue("batteryLabels", "{}"));
            Qt.callLater(root.discoverBatteries);
        }
    }

    StyledText {
        width: parent.width
        text: "ZmkBattery"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Displays the central battery and every ZMK peripheral battery proxy. Click the bar widget to refresh immediately."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: "GATT setup required"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        textFormat: Text.RichText
        text: "The keyboard must be connected with its GATT services resolved. To expose peripheral batteries, enable peripheral battery fetching and proxying in ZMK. <a href=\"" + root.zmkBatteryGuideUrl + "\">Open the ZMK battery configuration guide</a>."
        linkColor: Theme.primary
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
        onLinkActivated: link => Qt.openUrlExternally(link)
    }

    StyledText {
        width: parent.width
        text: "Keyboard name"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Exact Bluetooth name or alias shown by bluetoothctl"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS

        DankTextField {
            id: keyboardNameField
            width: parent.width - refreshBatteriesButton.width - parent.spacing
            text: root.keyboardName
            placeholderText: "Corne-ish Zen"
            leftIconName: "keyboard"
            onEditingFinished: {
                var nextName = text.trim() || "Corne-ish Zen";
                text = nextName;
                root.keyboardName = nextName;
                root.saveValue("keyboardName", nextName);
                root.discoverBatteries();
            }
        }

        DankActionButton {
            id: refreshBatteriesButton
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: 36
            iconName: root.batteryDiscoveryLoading ? "sync" : "refresh"
            iconColor: Theme.surfaceVariantText
            backgroundColor: "transparent"
            tooltipText: "Discover batteries"
            enabled: !root.batteryDiscoveryLoading
            onClicked: root.discoverBatteries()
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outline
        opacity: 0.3
    }

    StyledText {
        width: parent.width
        text: "Battery labels"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Rename each discovered battery. An empty label shows only its percentage."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        visible: root.batteryDiscoveryLoading
        width: parent.width
        text: "Discovering batteries…"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    StyledText {
        visible: !root.batteryDiscoveryLoading && root.batteryDiscoveryError.length > 0
        width: parent.width
        text: root.batteryDiscoveryError
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.warning
        wrapMode: Text.WordWrap
    }

    Column {
        visible: !root.batteryDiscoveryLoading && root.discoveredBatteries.length > 0
        width: parent.width
        spacing: Theme.spacingS

        Repeater {
            model: root.discoveredBatteries

            Column {
                required property var modelData
                width: parent.width
                spacing: Theme.spacingXS

                StyledText {
                    width: parent.width
                    text: modelData.name
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DankTextField {
                        id: batteryLabelField
                        width: parent.width - resetLabelButton.width - parent.spacing
                        text: root.resolvedLabel(modelData)
                        placeholderText: modelData.name
                        leftIconName: "label"
                        onEditingFinished: root.saveBatteryLabel(modelData.id, text)

                        Connections {
                            target: root

                            function onLabelOverridesChanged() {
                                if (!batteryLabelField.getActiveFocus())
                                    batteryLabelField.text = root.resolvedLabel(modelData);
                            }
                        }
                    }

                    DankActionButton {
                        id: resetLabelButton
                        anchors.verticalCenter: parent.verticalCenter
                        buttonSize: 36
                        iconName: "restart_alt"
                        iconColor: Theme.surfaceVariantText
                        backgroundColor: "transparent"
                        tooltipText: "Reset label"
                        enabled: root.hasOverride(modelData.id)
                        onClicked: root.resetBatteryLabel(modelData.id)
                    }
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outline
        opacity: 0.3
    }

    StyledText {
        width: parent.width
        text: "Find your keyboard name"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Copy and paste this command into a terminal, then copy the name shown after your keyboard's Bluetooth address into the Keyboard name field above."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        implicitHeight: Math.max(discoverCommandText.implicitHeight, copyDiscoverCommandButton.height) + Theme.spacingS * 2

        StyledText {
            id: discoverCommandText
            anchors.left: parent.left
            anchors.right: copyDiscoverCommandButton.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.spacingS
            anchors.rightMargin: Theme.spacingXS
            text: root.discoverCommand
            wrapMode: Text.WrapAnywhere
            color: Theme.primary
            font.pixelSize: Theme.fontSizeSmall - 1
            font.family: "monospace"
        }

        DankActionButton {
            id: copyDiscoverCommandButton
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: 28
            iconName: root.discoverCommandCopied ? "check" : "content_copy"
            iconColor: root.discoverCommandCopied ? Theme.success : Theme.surfaceVariantText
            backgroundColor: "transparent"
            tooltipText: root.discoverCommandCopied ? "Command copied" : "Copy command"
            onClicked: {
                Quickshell.execDetached([
                    "sh",
                    "-c",
                    "printf %s \"$1\" | wl-copy",
                    "_",
                    root.discoverCommand
                ]);
                root.discoverCommandCopied = true;
                copiedReset.restart();
            }
        }
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh interval"
        description: "How often to query every keyboard battery"
        defaultValue: 60
        minimum: 10
        maximum: 600
        unit: "sec"
        leftIcon: "schedule"
    }

    SliderSetting {
        settingKey: "warningThreshold"
        label: "Low battery warning"
        description: "Use the warning color at or below this percentage"
        defaultValue: 20
        minimum: 5
        maximum: 50
        unit: "%"
        leftIcon: "battery_alert"
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outline
        opacity: 0.3
    }

    StyledText {
        width: parent.width
        text: "Requirements"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "The plugin uses BlueZ through busctl and requires bash and jq."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
