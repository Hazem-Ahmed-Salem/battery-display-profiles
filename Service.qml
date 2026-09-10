import QtQuick
import Quickshell
import Quickshell.Services.UPower

Item {
    id: root

    property var shell: null
    property string omarchyPath: Quickshell.env("OMARCHY_PATH")

    Component.onCompleted: {
        console.log(
            "[Battery Display Profiles] Service started. " +
            "onBattery =", UPower.onBattery
        )
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