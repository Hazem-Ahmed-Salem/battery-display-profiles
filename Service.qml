import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Item {
    id: root

    property string shellConfigPath:
        Quickshell.env("HOME") + "/.config/omarchy/shell.json"

    property bool configLoaded: false
    property bool configValid: false
    property string monitorName: ""
    property string acMode: ""
    property string batteryMode: ""

    // Reactive power state from Quickshell UPower. No polling.
    property bool onBattery: UPower.onBattery

    // Remember the exact profile that was last handled.
    // Power state alone is not enough because a user can change the
    // profile while remaining on the same power state.
    property string lastAppliedPowerState: ""
    property string lastAppliedMode: ""
    property bool applyPending: false

    DisplayController {
        id: displayController

        onDiscoveryCompleted: function(monitors) {
            console.log(
                "[Battery Display Profiles] Service monitor discovery completed"
            )
            root.tryApplyProfile()
        }

        onDiscoveryFailed: function(error) {
            console.warn(
                "[Battery Display Profiles] Service monitor discovery failed:",
                error
            )
        }

        onModeApplied: function(monitorName, mode) {
            console.log(
                "[Battery Display Profiles] Automatic profile applied:",
                monitorName,
                mode
            )

            root.lastAppliedPowerState = root.desiredPowerState()
            root.lastAppliedMode = mode
            root.applyPending = false
        }

        onModeApplyFailed: function(monitorName, mode) {
            console.warn(
                "[Battery Display Profiles] Automatic profile failed:",
                monitorName,
                mode
            )
            root.applyPending = false
        }
    }

    FileView {
        id: shellConfig

        path: root.shellConfigPath
        watchChanges: true
        printErrors: true

        onLoaded: {
            root.loadConfiguration()
        }

        onFileChanged: {
            console.log(
                "[Battery Display Profiles] shell.json changed; reloading configuration"
            )
            reload()
        }

        onLoadFailed: function(error) {
            console.warn(
                "[Battery Display Profiles] Failed to load shell.json:",
                error
            )
            root.configLoaded = false
            root.configValid = false
        }
    }

    function loadConfiguration() {
        var raw = shellConfig.text()

        if (typeof raw !== "string" || raw.trim() === "") {
            console.warn(
                "[Battery Display Profiles] shell.json is empty"
            )
            root.configLoaded = false
            root.configValid = false
            return
        }

        var parsed

        try {
            parsed = JSON.parse(raw)
        } catch (error) {
            console.warn(
                "[Battery Display Profiles] Invalid shell.json:",
                error
            )
            root.configLoaded = false
            root.configValid = false
            return
        }

        var entry = root.findPluginBarEntry(parsed)

        if (!entry) {
            console.warn(
                "[Battery Display Profiles] Plugin is not configured in shell.json"
            )

            root.monitorName = ""
            root.acMode = ""
            root.batteryMode = ""
            root.configLoaded = true
            root.configValid = false
            root.lastAppliedPowerState = ""
            root.lastAppliedMode = ""
            return
        }

        var configuredMonitor = String(entry.monitor || "").trim()
        var configuredAcMode = String(entry.acMode || "").trim()
        var configuredBatteryMode = String(entry.batteryMode || "").trim()

        if (
            configuredMonitor === "" ||
            configuredAcMode === "" ||
            configuredBatteryMode === ""
        ) {
            console.warn(
                "[Battery Display Profiles] Incomplete plugin configuration"
            )
            console.warn(
                "[Battery Display Profiles] monitor =",
                configuredMonitor
            )
            console.warn(
                "[Battery Display Profiles] acMode =",
                configuredAcMode
            )
            console.warn(
                "[Battery Display Profiles] batteryMode =",
                configuredBatteryMode
            )

            root.monitorName = configuredMonitor
            root.acMode = configuredAcMode
            root.batteryMode = configuredBatteryMode
            root.configLoaded = true
            root.configValid = false
            root.lastAppliedPowerState = ""
            root.lastAppliedMode = ""
            return
        }

        // Detect an actual profile/configuration change. This is the key
        // part that lets a changed battery profile take effect immediately
        // without requiring a power-state transition.
        var configurationChanged =
            root.monitorName !== configuredMonitor ||
            root.acMode !== configuredAcMode ||
            root.batteryMode !== configuredBatteryMode

        root.monitorName = configuredMonitor
        root.acMode = configuredAcMode
        root.batteryMode = configuredBatteryMode
        root.configLoaded = true
        root.configValid = true

        if (configurationChanged) {
            root.lastAppliedPowerState = ""
            root.lastAppliedMode = ""
            root.applyPending = false

            console.log(
                "[Battery Display Profiles] Active configuration changed; re-evaluating profile"
            )
        }

        console.log(
            "[Battery Display Profiles] Configuration loaded:"
        )
        console.log(
            "[Battery Display Profiles] Monitor:",
            root.monitorName
        )
        console.log(
            "[Battery Display Profiles] AC mode:",
            root.acMode
        )
        console.log(
            "[Battery Display Profiles] Battery mode:",
            root.batteryMode
        )

        // Re-read monitor information whenever configuration changes.
        // This validates the requested mode against the live monitor state.
        displayController.discoverMonitors()
    }

    function findPluginBarEntry(config) {
        if (!config || typeof config !== "object") {
            return null
        }

        if (config.bar && config.bar.layout) {
            var sections = ["left", "center", "right"]

            for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
                var section = config.bar.layout[sections[sectionIndex]]

                if (!Array.isArray(section)) {
                    continue
                }

                for (var i = 0; i < section.length; i++) {
                    var entry = section[i]

                    if (!entry || typeof entry !== "object") {
                        continue
                    }

                    if (String(entry.id || "") === "battery-display-profiles") {
                        return entry
                    }
                }
            }
        }

        if (Array.isArray(config.plugins)) {
            for (var p = 0; p < config.plugins.length; p++) {
                var plug = config.plugins[p]
                if (plug && typeof plug === "object" && String(plug.id || "") === "battery-display-profiles") {
                    return plug
                }
            }
        }

        return null
    }

    function desiredMode() {
        return root.onBattery ? root.batteryMode : root.acMode
    }

    function desiredPowerState() {
        return root.onBattery ? "battery" : "ac"
    }

    function tryApplyProfile() {
        if (!root.configLoaded || !root.configValid) {
            return
        }

        if (root.monitorName === "") {
            return
        }

        var powerState = root.desiredPowerState()
        var mode = root.desiredMode()

        if (mode === "") {
            return
        }

        // IMPORTANT: do not skip solely because the power state matches.
        // The configured mode may have changed while still on AC/battery.
        if (
            root.lastAppliedPowerState === powerState &&
            displayController.modesEquivalent(root.lastAppliedMode, mode)
        ) {
            return
        }

        var monitor = displayController.findMonitor(root.monitorName)

        if (!monitor) {
            console.warn(
                "[Battery Display Profiles] Configured monitor is not currently available:",
                root.monitorName
            )
            return
        }

        if (!displayController.validateMode(root.monitorName, mode)) {
            console.warn(
                "[Battery Display Profiles] Refusing automatic profile because the requested mode is unavailable:",
                mode
            )
            return
        }

        var currentMode = displayController.currentMode(monitor)

        if (displayController.modesEquivalent(currentMode, mode)) {
            console.log(
                "[Battery Display Profiles] Desired profile is already active:",
                "powerState =",
                powerState,
                "onBattery =",
                root.onBattery,
                "mode =",
                mode
            )

            root.lastAppliedPowerState = powerState
            root.lastAppliedMode = mode
            root.applyPending = false
            return
        }

        console.log(
            "[Battery Display Profiles] Applying automatic profile:",
            "powerState =",
            powerState,
            "onBattery =",
            root.onBattery,
            "mode =",
            mode
        )

        root.applyPending = true

        displayController.applyMode(
            root.monitorName,
            mode
        )
    }

    onOnBatteryChanged: {
        console.log(
            "[Battery Display Profiles] Power state changed. onBattery =",
            root.onBattery
        )

        root.lastAppliedPowerState = ""
        root.lastAppliedMode = ""
        root.applyPending = false

        displayController.discoverMonitors()
    }

    Component.onCompleted: {
        console.log(
            "[Battery Display Profiles] Service started."
        )
        console.log(
            "[Battery Display Profiles] Initial onBattery =",
            root.onBattery
        )
        console.log(
            "[Battery Display Profiles] Reading:",
            root.shellConfigPath
        )
    }
}
