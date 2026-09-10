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
            console.log(
                "[Battery Display Profiles] Monitor discovery already running"
            )
            return
        }

        console.log(
            "[Battery Display Profiles] Discovering monitors..."
        )

        monitorProcess.running = true
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

            root.discoveryFailed(message)
            return
        }

        if (!Array.isArray(parsed)) {
            var typeError =
                "hyprctl monitors -j returned an unexpected format"

            console.warn(
                "[Battery Display Profiles]",
                typeError
            )

            root.discoveryFailed(typeError)
            return
        }

        root.monitors = parsed

        console.log(
            "[Battery Display Profiles] Discovered",
            parsed.length,
            "monitor(s)"
        )

        for (var i = 0; i < parsed.length; i++) {
            var monitor = parsed[i]

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

        root.discoveryCompleted(parsed)
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

            console.log(
                "[Battery Display Profiles] stdout:",
                stdoutCollector.text
            )

            console.log(
                "[Battery Display Profiles] stderr:",
                stderrCollector.text
            )

            if (exitCode !== 0) {
                var error = stderrCollector.text

                if (error.length === 0) {
                    error =
                        "hyprctl exited with code " + exitCode
                }

                console.warn(
                    "[Battery Display Profiles] Monitor discovery failed:",
                    error
                )

                root.discoveryFailed(error)
            }
        }
    }
}