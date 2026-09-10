import Quickshell
import Quickshell.Services.UPower
import QtQml

Singleton {
    id: root

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