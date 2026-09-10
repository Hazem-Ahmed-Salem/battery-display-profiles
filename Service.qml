import QtQuick
import Quickshell
import Quickshell.Services.UPower

Item {
    id: root

    property var shell: null
    property string omarchyPath: Quickshell.env("OMARCHY_PATH")

    DisplayController {
        id: displayController

        onDiscoveryCompleted: function(monitors) {
            console.log(
                "[Battery Display Profiles] Testing monitor validation..."
            )

            console.log(
                "[Battery Display Profiles] Lookup eDP-1:",
                findMonitor("eDP-1") !== null
            )

            console.log(
                "[Battery Display Profiles] 165Hz exists:",
                validateMode(
                    "eDP-1",
                    "2560x1600@165"
                )
            )

            console.log(
                "[Battery Display Profiles] 60Hz exists:",
                validateMode(
                    "eDP-1",
                    "2560x1600@60"
                )
            )

            console.log(
                "[Battery Display Profiles] Invalid mode exists:",
                validateMode(
                    "eDP-1",
                    "2560x1600@999"
                )
            )
        }

        onDiscoveryFailed: function(error) {
            console.warn(
                "[Battery Display Profiles] Monitor discovery failed:",
                error
            )
        }
    }

    Component.onCompleted: {
        console.log(
            "[Battery Display Profiles] Service started. " +
            "onBattery =", UPower.onBattery
        )

        displayController.discoverMonitors()
    }

    Connections {
        target: UPower

        function onOnBatteryChanged() {
            console.log(
                "[Battery Display Profiles] Power state changed. " +
                "onBattery =", UPower.onBattery
            )
        }
    }
}

