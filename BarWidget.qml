import QtQuick
import QtQuick.Controls

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

import qs.Ui
import qs.Commons

Item {
    id: root

    property var bar: null
    property string moduleName: ""
    property var settings: ({})
    property bool opened: false

    property string configuredMonitor:
        settings ? (settings.monitor || "") : ""
    property string selectedMonitor: ""

    readonly property string autoDetectedMonitor: {
        var mons = displayController.monitors
        if (!mons || mons.length === 0) return ""
        var mon = displayController.autoDetectMonitor()
        return mon ? mon.name : ""
    }

    readonly property string monitorName: {
        if (selectedMonitor !== "") return selectedMonitor
        if (configuredMonitor !== "") return configuredMonitor
        return autoDetectedMonitor
    }

    property string configuredAcMode:
        settings ? (settings.acMode || "") : ""
    property string selectedAcMode: ""

    readonly property string acMode: {
        if (selectedAcMode !== "") return selectedAcMode
        if (configuredAcMode !== "") return configuredAcMode
        var mons = displayController.monitors
        return displayController.highestMode(currentMonitor)
    }

    property string configuredBatteryMode:
        settings ? (settings.batteryMode || "") : ""
    property string selectedBatteryMode: ""

    readonly property string batteryMode: {
        if (selectedBatteryMode !== "") return selectedBatteryMode
        if (configuredBatteryMode !== "") return configuredBatteryMode
        var mons = displayController.monitors
        return displayController.lowestMode(currentMonitor)
    }

    readonly property string powerState:
        UPower.onBattery
            ? "Battery"
            : "AC"

    readonly property var currentMonitor: {
        var mons = displayController.monitors
        return displayController.findMonitor(
            root.monitorName
        )
    }

    readonly property string currentMode: {
        var mons = displayController.monitors
        return displayController.currentMode(
            root.currentMonitor
        )
    }

    property string profileEditor: ""

    property bool savingProfile: false
    property string pendingProfileKey: ""
    property string pendingProfileMode: ""

    implicitWidth: iconButton.implicitWidth
    implicitHeight: iconButton.implicitHeight

    DisplayController {
        id: displayController

        onModeApplied: function(
            monitorName,
            mode
        ) {
            console.log(
                "[Battery Display Profiles] Mode applied:",
                monitorName,
                mode
            )
        }

        onModeApplyFailed: function(
            monitorName,
            mode
        ) {
            console.warn(
                "[Battery Display Profiles] Mode change failed:",
                monitorName,
                mode
            )
        }
    }

    onSettingsChanged: {
        if (settings && typeof settings === "object") {
            if (settings.monitor) {
                root.selectedMonitor = settings.monitor
            }
            if (settings.acMode) {
                root.selectedAcMode = settings.acMode
            }
            if (settings.batteryMode) {
                root.selectedBatteryMode = settings.batteryMode
            }
        }
    }

    Component.onCompleted: {
        if (settings && typeof settings === "object") {
            if (settings.monitor) {
                root.selectedMonitor = settings.monitor
            }
            if (settings.acMode) {
                root.selectedAcMode = settings.acMode
            }
            if (settings.batteryMode) {
                root.selectedBatteryMode = settings.batteryMode
            }
        }
        displayController.discoverMonitors()
    }

    Process {
        id: profileSaveProcess

        command: []

        onExited: function(exitCode, exitStatus) {
            root.savingProfile = false

            if (exitCode === 0) {
                console.log(
                    "[Battery Display Profiles] Profile saved:",
                    root.pendingProfileKey,
                    root.pendingProfileMode
                )
            } else {
                console.warn(
                    "[Battery Display Profiles] Failed to save profile via CLI. Exit code:",
                    exitCode
                )
            }

            root.pendingProfileKey = ""
            root.pendingProfileMode = ""
        }
    }

    /*
     * ---------------------------------------------------------
     * Helpers
     * ---------------------------------------------------------
     */

    function toggle() {
        if (root.opened) {
            root.close()
        } else {
            root.open()
        }
    }

    function open() {
        root.profileEditor = ""
        displayController.discoverMonitors()
        root.opened = true
    }

    function close() {
        root.profileEditor = ""
        root.opened = false
    }

    function modeLabel(mode) {
        var normalized =
            displayController.normalizeMode(
                mode
            )

        var parsed =
            displayController.parseMode(
                normalized
            )

        if (!parsed) {
            return mode
        }

        return (
            parsed.width +
            "×" +
            parsed.height +
            " · " +
            Math.round(
                parsed.refreshRate
            ) +
            " Hz"
        )
    }

    function isCurrentMode(mode) {
        return displayController.modesEquivalent(
            mode,
            root.currentMode
        )
    }

    function selectMode(mode) {
        if (
            isCurrentMode(mode)
        ) {
            return
        }

        displayController.applyMode(
            root.monitorName,
            mode
        )
    }

    function profileModeLabel(mode) {
        if (!mode) {
            return "Not configured"
        }

        return modeLabel(mode)
    }

    function profileKeyForEditor() {
        if (root.profileEditor === "AC") {
            return "acMode"
        }

        if (root.profileEditor === "Battery") {
            return "batteryMode"
        }

        return ""
    }

    function profileModeForEditor() {
        if (root.profileEditor === "AC") {
            return root.acMode
        }

        if (root.profileEditor === "Battery") {
            return root.batteryMode
        }

        return ""
    }

    function openProfileEditor(profile) {
        if (profile === "Monitor") {
            root.profileEditor = "Monitor"
            displayController.discoverMonitors()
            return
        }

        if (
            !root.currentMonitor
        ) {
            console.warn(
                "[Battery Display Profiles] Cannot edit profile: monitor is unavailable"
            )
            return
        }

        root.profileEditor = profile
        displayController.discoverMonitors()
    }

    function closeProfileEditor() {
        root.profileEditor = ""
    }

    function persistSettings(values) {
        var entry = {}
        if (root.settings && typeof root.settings === "object") {
            for (var key in root.settings) {
                if (key !== "id") entry[key] = root.settings[key]
            }
        }
        for (var k in values) {
            entry[k] = values[k]
        }
        root.settings = entry

        var modName = root.moduleName || "battery-display-profiles"
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
            root.bar.shell.updateEntryInline(modName, entry)
        }
    }

    function saveMonitor(name) {
        if (!name || name === "") return

        root.selectedMonitor = name
        root.selectedAcMode = ""
        root.selectedBatteryMode = ""
        root.closeProfileEditor()

        var mon = displayController.findMonitor(name)
        var autoAc = mon ? displayController.highestMode(mon) : ""
        var autoBat = mon ? displayController.lowestMode(mon) : ""

        var updates = { monitor: name }
        if (autoAc !== "") updates.acMode = autoAc
        if (autoBat !== "") updates.batteryMode = autoBat
        root.persistSettings(updates)

        root.pendingProfileKey = "monitor"
        root.pendingProfileMode = name
        root.savingProfile = true

        console.log(
            "[Battery Display Profiles] Saving monitor:",
            name
        )

        var modName = root.moduleName || "battery-display-profiles"
        if (profileSaveProcess.running) {
            profileSaveProcess.running = false
        }
        profileSaveProcess.command = [
            "omarchy",
            "bar",
            "set",
            modName,
            "monitor",
            name
        ]

        profileSaveProcess.running = true
    }

    function saveProfileMode(mode) {
        var key =
            root.profileKeyForEditor()

        if (
            key === "" ||
            !mode
        ) {
            return
        }

        if (
            !root.currentMonitor
        ) {
            console.warn(
                "[Battery Display Profiles] Cannot save profile: monitor is unavailable"
            )
            return
        }

        var normalizedMode =
            displayController.normalizeMode(mode)

        if (
            !displayController.validateMode(
                root.monitorName,
                normalizedMode
            )
        ) {
            console.warn(
                "[Battery Display Profiles] Refusing unavailable profile mode:",
                normalizedMode
            )
            return
        }

        if (key === "acMode") {
            root.selectedAcMode = normalizedMode
        } else if (key === "batteryMode") {
            root.selectedBatteryMode = normalizedMode
        }

        root.closeProfileEditor()

        var updates = {}
        updates[key] = normalizedMode
        root.persistSettings(updates)

        root.pendingProfileKey = key
        root.pendingProfileMode = normalizedMode
        root.savingProfile = true

        console.log(
            "[Battery Display Profiles] Saving profile:",
            key,
            normalizedMode
        )

        var modName = root.moduleName || "battery-display-profiles"
        if (profileSaveProcess.running) {
            profileSaveProcess.running = false
        }
        profileSaveProcess.command = [
            "omarchy",
            "bar",
            "set",
            modName,
            key,
            normalizedMode
        ]

        profileSaveProcess.running = true
    }

    /*
     * ---------------------------------------------------------
     * Bar button
     * ---------------------------------------------------------
     */

    BarIconButton {
        id: iconButton

        anchors.fill: parent

        bar: root.bar

        text:
            Quickshell.screens.length > 1
                ? "󰍺"
                : "󰍹"

        onPressed: {
            root.toggle()
        }
    }

    /*
     * ---------------------------------------------------------
     * Panel
     * ---------------------------------------------------------
     */

    KeyboardPanel {
        id: panel

        anchorItem: iconButton
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher

        contentWidth:
            panel.fittedContentWidth(
                Style.space(360)
            )

        contentHeight:
            panel.fittedContentHeight(
                panelColumn.implicitHeight,
                Style.space(520)
            )

        PanelKeyCatcher {
            id: keyCatcher

            anchors.fill: parent

            onCloseRequested: {
                root.close()
            }
        }

        ScrollView {
            id: scrollArea

            anchors.fill: parent

            clip: true

            ScrollBar.horizontal.policy:
                ScrollBar.AlwaysOff

            ScrollBar.vertical.policy:
                panelColumn.implicitHeight >
                height
                    ? ScrollBar.AsNeeded
                    : ScrollBar.AlwaysOff

            Column {
                id: panelColumn

                width:
                    scrollArea.availableWidth

                spacing:
                    Style.space(14)

                /*
                 * -------------------------------------------------
                 * Header
                 * -------------------------------------------------
                 */

                Item {
                    width: parent.width

                    implicitHeight:
                        Math.max(
                            headerIcon.implicitHeight,
                            headerText.implicitHeight
                        )

                    Text {
                        id: headerIcon

                        textFormat:
                            Text.PlainText

                        text:
                            Quickshell.screens.length > 1
                                ? "󰍺"
                                : "󰍹"

                        color:
                            root.bar.foreground

                        font.family:
                            root.bar.fontFamily

                        font.pixelSize:
                            Style.font.display

                        anchors.left:
                            parent.left

                        anchors.verticalCenter:
                            parent.verticalCenter
                    }

                    Item {
                        id: headerText

                        anchors.left:
                            headerIcon.right

                        anchors.leftMargin:
                            Style.space(14)

                        anchors.right:
                            parent.right

                        anchors.verticalCenter:
                            parent.verticalCenter

                        implicitHeight:
                            headerTextCol.implicitHeight

                        MouseArea {
                            anchors.fill: parent
                            cursorShape:
                                root.profileEditor === ""
                                    ? Qt.PointingHandCursor
                                    : Qt.ArrowCursor

                            onClicked: {
                                if (root.profileEditor === "") {
                                    root.openProfileEditor("Monitor")
                                }
                            }
                        }

                        Column {
                            id: headerTextCol

                            anchors.fill: parent

                            spacing:
                                Style.space(2)

                            Text {
                                width: parent.width

                                text:
                                    root.profileEditor === ""
                                        ? "Display"
                                        : (
                                            root.profileEditor === "Monitor"
                                                ? "Monitor Selection"
                                                : root.profileEditor + " Profile"
                                        )

                                color:
                                    root.bar.foreground

                                font.family:
                                    root.bar.fontFamily

                                font.pixelSize:
                                    Style.font.title

                                font.bold: true

                                elide:
                                    Text.ElideRight
                            }

                            Text {
                                width: parent.width

                                text:
                                    root.profileEditor === ""
                                        ? (
                                            root.monitorName !== ""
                                                ? root.monitorName + (displayController.monitors.length > 1 ? " ▾" : "")
                                                : "No monitor selected ▾"
                                        )
                                        : (
                                            root.profileEditor === "Monitor"
                                                ? "Choose an output"
                                                : "Select a display mode"
                                        )

                                color:
                                    Qt.darker(
                                        root.bar.foreground,
                                        1.4
                                    )

                                font.family:
                                    root.bar.fontFamily

                                font.pixelSize:
                                    Style.font.caption

                                font.bold: true

                                font.letterSpacing:
                                    1.0

                                elide:
                                    Text.ElideRight
                            }
                        }
                    }
                }

                /*
                 * =================================================
                 * MAIN VIEW
                 * =================================================
                 */

                Column {
                    width: parent.width

                    visible:
                        root.profileEditor === ""

                    spacing:
                        Style.space(14)

                    /*
                     * -------------------------------------------------
                     * Current mode
                     * -------------------------------------------------
                     */

                    CursorSurface {
                        visible: !root.currentMonitor
                        width: parent.width
                        implicitHeight:
                            Style.spacing.controlHeight +
                            Style.space(8)
                        foreground: root.bar.foreground
                        fill:
                            Style.hoverFillFor(
                                root.bar.foreground,
                                Color.accent
                            )
                        currentFill:
                            Style.selectedFillFor(
                                root.bar.foreground,
                                Color.accent
                            )

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.openProfileEditor("Monitor")
                            }
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Style.space(10)
                            anchors.rightMargin: Style.space(10)
                            spacing: Style.space(8)

                            Text {
                                text: "󰍹"
                                width: Style.space(20)
                                horizontalAlignment: Text.AlignHCenter
                                color: root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.body
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "Select a monitor..."
                                color: root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    PanelSeparator {
                        foreground:
                            root.bar.foreground
                    }

                    Column {
                        width: parent.width

                        spacing:
                            Style.space(6)

                        PanelSectionHeader {
                            text: "CURRENT"

                            foreground:
                                root.bar.foreground

                            fontFamily:
                                root.bar.fontFamily
                        }

                        Item {
                            width: parent.width

                            implicitHeight:
                                currentModeText.implicitHeight

                            Text {
                                id: currentModeText

                                width: parent.width

                                text:
                                    root.currentMode !== ""
                                        ? root.modeLabel(
                                            root.currentMode
                                        )
                                        : "Unknown"

                                color:
                                    root.bar.foreground

                                font.family:
                                    root.bar.fontFamily

                                font.pixelSize:
                                    Style.font.body

                                font.bold: true
                            }
                        }
                    }

                    /*
                     * -------------------------------------------------
                     * Refresh modes
                     * -------------------------------------------------
                     */

                    PanelSeparator {
                        foreground:
                            root.bar.foreground
                    }

                    Column {
                        width: parent.width

                        spacing:
                            Style.space(8)

                        PanelSectionHeader {
                            text: "REFRESH RATE"

                            foreground:
                                root.bar.foreground

                            fontFamily:
                                root.bar.fontFamily
                        }

                        Column {
                            width: parent.width

                            spacing:
                                Style.space(4)

                            Repeater {
                                model:
                                    root.currentMonitor &&
                                    Array.isArray(
                                        root.currentMonitor.availableModes
                                    )
                                        ? root.currentMonitor.availableModes
                                        : []

                                delegate:
                                    CursorSurface {
                                        id: modeRow

                                        required property var modelData
                                        required property int index

                                        width:
                                            panelColumn.width

                                        implicitHeight:
                                            Style.spacing.controlHeight +
                                            Style.space(8)

                                        foreground:
                                            root.bar.foreground

                                        fill:
                                            Style.hoverFillFor(
                                                root.bar.foreground,
                                                Color.accent
                                            )

                                        currentFill:
                                            Style.selectedFillFor(
                                                root.bar.foreground,
                                                Color.accent
                                            )

                                        current:
                                            root.isCurrentMode(
                                                modelData
                                            )

                                        MouseArea {
                                            anchors.fill:
                                                parent

                                            hoverEnabled: true

                                            cursorShape:
                                                Qt.PointingHandCursor

                                            onClicked: {
                                                root.selectMode(
                                                    modelData
                                                )
                                            }
                                        }

                                        Row {
                                            anchors.left:
                                                parent.left

                                            anchors.right:
                                                parent.right

                                            anchors.verticalCenter:
                                                parent.verticalCenter

                                            anchors.leftMargin:
                                                Style.space(10)

                                            anchors.rightMargin:
                                                Style.space(10)

                                            spacing:
                                                Style.space(8)

                                            Text {
                                                text:
                                                    root.isCurrentMode(
                                                        modelData
                                                    )
                                                        ? "󰄬"
                                                        : "󰍹"

                                                width:
                                                    Style.space(20)

                                                horizontalAlignment:
                                                    Text.AlignHCenter

                                                color:
                                                    root.bar.foreground

                                                font.family:
                                                    root.bar.fontFamily

                                                font.pixelSize:
                                                    Style.font.body

                                                anchors.verticalCenter:
                                                    parent.verticalCenter
                                            }

                                            Text {
                                                text:
                                                    root.modeLabel(
                                                        modelData
                                                    )

                                                color:
                                                    root.bar.foreground

                                                font.family:
                                                    root.bar.fontFamily

                                                font.pixelSize:
                                                    Style.font.body

                                                font.bold:
                                                    root.isCurrentMode(
                                                        modelData
                                                    )

                                                elide:
                                                    Text.ElideRight

                                                width:
                                                    parent.width -
                                                    Style.space(28)

                                                anchors.verticalCenter:
                                                    parent.verticalCenter
                                            }
                                        }
                                    }
                            }
                        }
                    }

                    /*
                     * -------------------------------------------------
                     * Profiles
                     * -------------------------------------------------
                     */

                    PanelSeparator {
                        foreground:
                            root.bar.foreground
                    }

                    Column {
                        width: parent.width

                        spacing:
                            Style.space(8)

                        PanelSectionHeader {
                            text: "POWER PROFILES"

                            foreground:
                                root.bar.foreground

                            fontFamily:
                                root.bar.fontFamily
                        }

                        Column {
                            width: parent.width

                            spacing:
                                Style.space(4)

                            /*
                             * AC profile
                             */

                            CursorSurface {
                                width: parent.width

                                implicitHeight:
                                    Style.spacing.controlHeight +
                                    Style.space(8)

                                foreground:
                                    root.bar.foreground

                                current:
                                    root.powerState === "AC"

                                fill:
                                    Style.hoverFillFor(
                                        root.bar.foreground,
                                        Color.accent
                                    )

                                currentFill:
                                    Style.selectedFillFor(
                                        root.bar.foreground,
                                        Color.accent
                                    )

                                MouseArea {
                                    anchors.fill: parent

                                    hoverEnabled: true

                                    cursorShape:
                                        Qt.PointingHandCursor

                                    onClicked: {
                                        root.openProfileEditor(
                                            "AC"
                                        )
                                    }
                                }

                                Row {
                                    anchors.left:
                                        parent.left

                                    anchors.right:
                                        parent.right

                                    anchors.verticalCenter:
                                        parent.verticalCenter

                                    anchors.leftMargin:
                                        Style.space(10)

                                    anchors.rightMargin:
                                        Style.space(10)

                                    spacing:
                                        Style.space(8)

                                    Text {
                                        text: "󰚥"

                                        width:
                                            Style.space(20)

                                        color:
                                            root.bar.foreground

                                        font.family:
                                            root.bar.fontFamily

                                        font.pixelSize:
                                            Style.font.body

                                        horizontalAlignment:
                                            Text.AlignHCenter
                                    }

                                    Column {
                                        width:
                                            parent.width -
                                            Style.space(28)

                                        spacing:
                                            Style.space(1)

                                        Text {
                                            text: "AC"

                                            color:
                                                root.bar.foreground

                                            font.family:
                                                root.bar.fontFamily

                                            font.pixelSize:
                                                Style.font.body

                                            font.bold: true
                                        }

                                        Text {
                                            text:
                                                root.profileModeLabel(
                                                    root.acMode
                                                )

                                            color:
                                                Qt.darker(
                                                    root.bar.foreground,
                                                    1.4
                                                )

                                            font.family:
                                                root.bar.fontFamily

                                            font.pixelSize:
                                                Style.font.caption
                                        }
                                    }

                                    Text {
                                        text: "›"

                                        color:
                                            root.bar.foreground

                                        font.family:
                                            root.bar.fontFamily

                                        font.pixelSize:
                                            Style.font.title
                                    }
                                }
                            }

                            /*
                             * Battery profile
                             */

                            CursorSurface {
                                width: parent.width

                                implicitHeight:
                                    Style.spacing.controlHeight +
                                    Style.space(8)

                                foreground:
                                    root.bar.foreground

                                current:
                                    root.powerState === "Battery"

                                fill:
                                    Style.hoverFillFor(
                                        root.bar.foreground,
                                        Color.accent
                                    )

                                currentFill:
                                    Style.selectedFillFor(
                                        root.bar.foreground,
                                        Color.accent
                                    )

                                MouseArea {
                                    anchors.fill: parent

                                    hoverEnabled: true

                                    cursorShape:
                                        Qt.PointingHandCursor

                                    onClicked: {
                                        root.openProfileEditor(
                                            "Battery"
                                        )
                                    }
                                }

                                Row {
                                    anchors.left:
                                        parent.left

                                    anchors.right:
                                        parent.right

                                    anchors.verticalCenter:
                                        parent.verticalCenter

                                    anchors.leftMargin:
                                        Style.space(10)

                                    anchors.rightMargin:
                                        Style.space(10)

                                    spacing:
                                        Style.space(8)

                                    Text {
                                        text: "󰁹"

                                        width:
                                            Style.space(20)

                                        color:
                                            root.bar.foreground

                                        font.family:
                                            root.bar.fontFamily

                                        font.pixelSize:
                                            Style.font.body

                                        horizontalAlignment:
                                            Text.AlignHCenter
                                    }

                                    Column {
                                        width:
                                            parent.width -
                                            Style.space(28)

                                        spacing:
                                            Style.space(1)

                                        Text {
                                            text: "Battery"

                                            color:
                                                root.bar.foreground

                                            font.family:
                                                root.bar.fontFamily

                                            font.pixelSize:
                                                Style.font.body

                                            font.bold: true
                                        }

                                        Text {
                                            text:
                                                root.profileModeLabel(
                                                    root.batteryMode
                                                )

                                            color:
                                                Qt.darker(
                                                    root.bar.foreground,
                                                    1.4
                                                )

                                            font.family:
                                                root.bar.fontFamily

                                            font.pixelSize:
                                                Style.font.caption
                                        }
                                    }

                                    Text {
                                        text: "›"

                                        color:
                                            root.bar.foreground

                                        font.family:
                                            root.bar.fontFamily

                                        font.pixelSize:
                                            Style.font.title
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width

                        height:
                            Style.space(4)
                    }
                }

                /*
                 * =================================================
                 * PROFILE EDITOR
                 * =================================================
                 */

                Column {
                    width: parent.width

                    visible:
                        root.profileEditor !== ""

                    spacing:
                        Style.space(10)

                    /*
                     * Back button
                     */

                    CursorSurface {
                        width: parent.width

                        implicitHeight:
                            Style.spacing.controlHeight +
                            Style.space(8)

                        foreground:
                            root.bar.foreground

                        fill:
                            Style.hoverFillFor(
                                root.bar.foreground,
                                Color.accent
                            )

                        currentFill:
                            Style.selectedFillFor(
                                root.bar.foreground,
                                Color.accent
                            )

                        MouseArea {
                            anchors.fill: parent

                            hoverEnabled: true

                            cursorShape:
                                Qt.PointingHandCursor

                            onClicked: {
                                root.closeProfileEditor()
                            }
                        }

                        Row {
                            anchors.left:
                                parent.left

                            anchors.right:
                                parent.right

                            anchors.verticalCenter:
                                parent.verticalCenter

                            anchors.leftMargin:
                                Style.space(10)

                            anchors.rightMargin:
                                Style.space(10)

                            spacing:
                                Style.space(8)

                            Text {
                                text: "‹"

                                width:
                                    Style.space(20)

                                color:
                                    root.bar.foreground

                                font.family:
                                    root.bar.fontFamily

                                font.pixelSize:
                                    Style.font.title

                                horizontalAlignment:
                                    Text.AlignHCenter
                            }

                            Text {
                                text:
                                    "Back to profiles"

                                color:
                                    root.bar.foreground

                                font.family:
                                    root.bar.fontFamily

                                font.pixelSize:
                                    Style.font.body

                                font.bold: true

                                anchors.verticalCenter:
                                    parent.verticalCenter
                            }
                        }
                    }

                    PanelSeparator {
                        foreground:
                            root.bar.foreground
                    }

                    PanelSectionHeader {
                        text:
                            root.profileEditor === "Monitor"
                                ? "MONITOR"
                                : (
                                    root.profileEditor === "AC"
                                        ? "AC MODE"
                                        : "BATTERY MODE"
                                )

                        foreground:
                            root.bar.foreground

                        fontFamily:
                            root.bar.fontFamily
                    }

                    Text {
                        width: parent.width

                        text:
                            root.savingProfile
                                ? "Saving..."
                                : (
                                    root.profileEditor === "Monitor"
                                        ? "Select which monitor this plugin should manage."
                                        : (
                                            root.profileEditor === "AC"
                                                ? "Select the mode to use while plugged in."
                                                : "Select the mode to use while on battery."
                                        )
                                )

                        color:
                            Qt.darker(
                                root.bar.foreground,
                                1.4
                            )

                        font.family:
                            root.bar.fontFamily

                        font.pixelSize:
                            Style.font.caption

                        wrapMode:
                            Text.WordWrap
                    }

                    Column {
                        width: parent.width

                        spacing:
                            Style.space(4)

                        Repeater {
                            model:
                                root.profileEditor === "Monitor"
                                    ? (
                                        Array.isArray(displayController.monitors)
                                            ? displayController.monitors
                                            : []
                                    )
                                    : (
                                        root.currentMonitor &&
                                        Array.isArray(
                                            root.currentMonitor.availableModes
                                        )
                                            ? root.currentMonitor.availableModes
                                            : []
                                    )

                            delegate:
                                CursorSurface {
                                    id: profileModeRow

                                    required property var modelData
                                    required property int index

                                    width:
                                        parent.width

                                    implicitHeight:
                                        Style.spacing.controlHeight +
                                        Style.space(8)

                                    foreground:
                                        root.bar.foreground

                                    current:
                                        root.profileEditor === "Monitor"
                                            ? (modelData.name === root.monitorName)
                                            : displayController.modesEquivalent(
                                                modelData,
                                                root.profileModeForEditor()
                                            )

                                    fill:
                                        Style.hoverFillFor(
                                            root.bar.foreground,
                                            Color.accent
                                        )

                                    currentFill:
                                        Style.selectedFillFor(
                                            root.bar.foreground,
                                            Color.accent
                                        )

                                    MouseArea {
                                        anchors.fill: parent

                                        hoverEnabled: true

                                        cursorShape:
                                            Qt.PointingHandCursor

                                        onClicked: {
                                            if (root.profileEditor === "Monitor") {
                                                root.saveMonitor(modelData.name)
                                            } else {
                                                root.saveProfileMode(
                                                    modelData
                                                )
                                            }
                                        }
                                    }

                                    Row {
                                        anchors.left:
                                            parent.left

                                        anchors.right:
                                            parent.right

                                        anchors.verticalCenter:
                                            parent.verticalCenter

                                        anchors.leftMargin:
                                            Style.space(10)

                                        anchors.rightMargin:
                                            Style.space(10)

                                        spacing:
                                            Style.space(8)

                                        Text {
                                            text:
                                                root.profileEditor === "Monitor"
                                                    ? (
                                                        modelData.name === root.monitorName
                                                            ? "󰄬"
                                                            : "󰍹"
                                                    )
                                                    : (
                                                        displayController.modesEquivalent(
                                                            modelData,
                                                            root.profileModeForEditor()
                                                        )
                                                            ? "󰄬"
                                                            : "󰍹"
                                                    )

                                            width:
                                                Style.space(20)

                                            horizontalAlignment:
                                                Text.AlignHCenter

                                            color:
                                                root.bar.foreground

                                            font.family:
                                                root.bar.fontFamily

                                            font.pixelSize:
                                                Style.font.body
                                        }

                                        Column {
                                            width:
                                                parent.width -
                                                Style.space(28)

                                            spacing:
                                                Style.space(1)

                                            Text {
                                                text:
                                                    root.profileEditor === "Monitor"
                                                        ? modelData.name
                                                        : root.modeLabel(modelData)

                                                color:
                                                    root.bar.foreground

                                                font.family:
                                                    root.bar.fontFamily

                                                font.pixelSize:
                                                    Style.font.body

                                                font.bold:
                                                    root.profileEditor === "Monitor"
                                                        ? (modelData.name === root.monitorName)
                                                        : displayController.modesEquivalent(
                                                            modelData,
                                                            root.profileModeForEditor()
                                                        )

                                                elide:
                                                    Text.ElideRight

                                                width: parent.width
                                            }

                                            Text {
                                                visible: root.profileEditor === "Monitor"

                                                text:
                                                    root.profileEditor === "Monitor"
                                                        ? (modelData.width + "×" + modelData.height + " · " + Math.round(modelData.refreshRate) + " Hz")
                                                        : ""

                                                color:
                                                    Qt.darker(
                                                        root.bar.foreground,
                                                        1.4
                                                    )

                                                font.family:
                                                    root.bar.fontFamily

                                                font.pixelSize:
                                                    Style.font.caption

                                                elide:
                                                    Text.ElideRight

                                                width: parent.width
                                            }
                                        }
                                    }
                                }
                        }
                    }

                    Item {
                        width: parent.width

                        height:
                            Style.space(4)
                    }
                }
            }
        }
    }

    /*
     * ---------------------------------------------------------
     * Settings / startup
     * ---------------------------------------------------------
     */

    onSettingsChanged: {
        console.log(
            "[Battery Display Profiles] Bar settings updated:",
            JSON.stringify(settings)
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
    }

    Component.onCompleted: {
        console.log(
            "[Battery Display Profiles] BAR WIDGET LOADED"
        )

        displayController.discoverMonitors()
    }
}