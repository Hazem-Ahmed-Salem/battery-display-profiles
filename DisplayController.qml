import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var monitors: []
    readonly property bool discovering: monitorProcess.running

    signal discoveryCompleted(var monitors)
    signal discoveryFailed(string error)

    function discoverMonitors() {
        if (monitorProcess.running) {
            return
        }

        console.log(
            "[Battery Display Profiles] Discovering monitors..."
        )

        monitorProcess.running = true
    }

    function findMonitor(name) {
        for (var i = 0; i < monitors.length; i++) {
            if (monitors[i].name === name) {
                return monitors[i]
            }
        }

        return null
    }

    function normalizeMode(mode) {
        if (typeof mode !== "string") {
            return ""
        }

        var result = mode.trim()

        result = result.replace(/Hz$/i, "")

        var parts = result.split("@")

        if (parts.length !== 2) {
            return result
        }

        var refreshRate = Number(parts[1])

        if (isNaN(refreshRate)) {
            return result
        }

        return parts[0] + "@" + refreshRate
    }

    function modeExists(monitor, requestedMode) {
        if (!monitor) {
            return false
        }

        if (!Array.isArray(monitor.availableModes)) {
            return false
        }

        var requested = normalizeMode(requestedMode)

        for (var i = 0; i < monitor.availableModes.length; i++) {
            if (
                normalizeMode(monitor.availableModes[i]) ===
                requested
            ) {
                return true
            }
        }

        return false
    }

    function validateMode(monitorName, requestedMode) {
        var monitor = findMonitor(monitorName)

        if (!monitor) {
            console.warn(
                "[Battery Display Profiles] Monitor not found:",
                monitorName
            )

            return false
        }

        if (!modeExists(monitor, requestedMode)) {
            console.warn(
                "[Battery Display Profiles] Mode not available:",
                requestedMode,
                "on",
                monitorName
            )

            return false
        }

        console.log(
            "[Battery Display Profiles] Mode validated:",
            monitorName,
            requestedMode
        )

        return true
    }

    function handleMonitorData(data) {
        var parsed

        try {
            parsed = JSON.parse(data)
        } catch (error) {
            var message =
                "Failed to parse hyprctl monitor JSON: " + error

            console.warn(
                "[Battery Display Profiles]",
                message
            )

            discoveryFailed(message)
            return
        }

        if (!Array.isArray(parsed)) {
            var message =
                "Unexpected monitor data from hyprctl"

            console.warn(
                "[Battery Display Profiles]",
                message
            )

            discoveryFailed(message)
            return
        }

        monitors = parsed

        console.log(
            "[Battery Display Profiles] Discovered",
            monitors.length,
            "monitor(s)"
        )

        for (var i = 0; i < monitors.length; i++) {
            var monitor = monitors[i]

            console.log(
                "[Battery Display Profiles] Monitor:",
                monitor.name,
                monitor.width + "x" + monitor.height,
                "@" + monitor.refreshRate + "Hz",
                "scale=" + monitor.scale
            )

            if (Array.isArray(monitor.availableModes)) {
                console.log(
                    "[Battery Display Profiles] Available modes:",
                    monitor.availableModes.join(", ")
                )
            }
        }

        discoveryCompleted(monitors)
    }

    Process {
        id: monitorProcess

        command: [
            "hyprctl",
            "monitors",
            "-j"
        ]

        stdout: StdioCollector {
            id: stdoutCollector

            onStreamFinished: {
                console.log(
                    "[Battery Display Profiles] stdout stream finished"
                )

                root.handleMonitorData(text)
            }
        }

        stderr: StdioCollector {
            id: stderrCollector
        }

        onExited: function(exitCode, exitStatus) {
            console.log(
                "[Battery Display Profiles] hyprctl exited:",
                "code =", exitCode,
                "status =", exitStatus
            )

            if (exitCode !== 0) {
                var error = stderrCollector.text

                if (error.length === 0) {
                    error =
                        "hyprctl exited with code " + exitCode
                }

                console.warn(
                    "[Battery Display Profiles] Discovery failed:",
                    error
                )

                discoveryFailed(error)
            }
        }
    }
}
