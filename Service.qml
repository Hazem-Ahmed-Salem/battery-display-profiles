import QtQuick
import Quickshell
import Quickshell.Services.UPower

Item {
    id: root

    property var shell: null
    property string omarchyPath: Quickshell.env("OMARCHY_PATH")

    DisplayController {
        id: displayController
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