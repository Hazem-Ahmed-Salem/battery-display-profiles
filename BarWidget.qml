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

    // Array of configured monitors: [ { name: string, enabled: bool, acMode: string, batteryMode: string } ]
    property var configuredMonitors: []
    property string activeMonitorName: ""

    // Sub-views: "main", "editMode", "addMonitor"
    property string currentView: "main"
    // When editing mode: "ac" or "battery"
    property string editingProfileKey: ""

    readonly property string powerState:
        UPower.onBattery ? "Battery" : "AC"

    readonly property var activeConfiguredMonitor: {
        for (var i = 0; i < configuredMonitors.length; i++) {
            if (configuredMonitors[i].name === activeMonitorName) {
                return configuredMonitors[i]
            }
        }
        return null
    }

    readonly property var activeLiveMonitor: {
        var _m = displayController.monitors
        return displayController.findMonitor(activeMonitorName)
    }

    readonly property bool isActiveConnected: activeLiveMonitor !== null

    readonly property string activeCurrentMode: {
        var _m = displayController.monitors
        return displayController.currentMode(activeLiveMonitor)
    }

    readonly property var unconfiguredDiscoveredMonitors: {
        var all = displayController.monitors || []
        var res = []
        for (var i = 0; i < all.length; i++) {
            var name = all[i].name
            var alreadyConfigured = false
            for (var c = 0; c < configuredMonitors.length; c++) {
                if (configuredMonitors[c].name === name) {
                    alreadyConfigured = true
                    break
                }
            }
            if (!alreadyConfigured) {
                res.push(all[i])
            }
        }
        return res
    }

    implicitWidth: iconButton.implicitWidth
    implicitHeight: iconButton.implicitHeight

    DisplayController {
        id: displayController

        onDiscoveryCompleted: function(monitors) {
            root.syncConfiguration()
        }

        onModeApplied: function(monitorName, mode) {
            console.log(
                "[Battery Display Profiles] Mode applied manually:",
                monitorName,
                mode
            )
        }

        onModeApplyFailed: function(monitorName, mode) {
            console.warn(
                "[Battery Display Profiles] Manual mode change failed:",
                monitorName,
                mode
            )
        }
    }

    // React to monitor hotplug events without polling
    readonly property int screenCount: Quickshell.screens.length
    onScreenCountChanged: {
        displayController.discoverMonitors()
    }

    /*
     * ---------------------------------------------------------
     * Helpers & Configuration sync
     * ---------------------------------------------------------
     */

    function syncConfiguration() {
        var list = []

        if (settings && typeof settings === "object") {
            if (Array.isArray(settings.monitors)) {
                list = settings.monitors
            } else if (typeof settings.monitors === "string") {
                try {
                    var parsedMonitorsJson = JSON.parse(settings.monitors)
                    if (Array.isArray(parsedMonitorsJson)) {
                        list = parsedMonitorsJson
                    } else if (parsedMonitorsJson && typeof parsedMonitorsJson === "object") {
                        list = [parsedMonitorsJson]
                    }
                } catch (e) {}
            } else if (settings.monitors && typeof settings.monitors === "object") {
                list = [settings.monitors]
            } else if (settings.monitor && typeof settings.monitor === "string") {
                list = [
                    {
                        name: String(settings.monitor).trim(),
                        enabled: true,
                        acMode: String(settings.acMode || "").trim(),
                        batteryMode: String(settings.batteryMode || "").trim()
                    }
                ]
            }
        }

        var parsed = []
        var needsPersist = false

        // 1. Process configured monitors
        for (var i = 0; i < list.length; i++) {
            var item = list[i]
            if (!item || typeof item !== "object") continue
            var mName = String(item.name || "").trim()
            if (mName === "") continue

            var mEnabled = item.enabled !== false
            var mAc = String(item.acMode || "").trim()
            var mBat = String(item.batteryMode || "").trim()

            var live = displayController.findMonitor(mName)
            if (live) {
                if (mAc === "" || !displayController.modeMatchesCurrentResolution(live, mAc) || !displayController.modeExists(live, mAc)) {
                    mAc = displayController.highestMode(live)
                    needsPersist = true
                }
                if (mBat === "" || !displayController.modeMatchesCurrentResolution(live, mBat) || !displayController.modeExists(live, mBat)) {
                    mBat = displayController.lowestMode(live)
                    needsPersist = true
                }
            }

            parsed.push({
                name: mName,
                enabled: mEnabled,
                acMode: mAc,
                batteryMode: mBat
            })
        }

        // 2. Auto-detect any newly discovered monitors not yet configured
        if (Array.isArray(displayController.monitors) && displayController.monitors.length > 0) {
            for (var d = 0; d < displayController.monitors.length; d++) {
                var autoM = displayController.monitors[d]
                var alreadyPresent = false
                for (var p = 0; p < parsed.length; p++) {
                    if (parsed[p].name === autoM.name) {
                        alreadyPresent = true
                        break
                    }
                }
                if (!alreadyPresent) {
                    parsed.push({
                        name: autoM.name,
                        enabled: true,
                        acMode: displayController.highestMode(autoM),
                        batteryMode: displayController.lowestMode(autoM)
                    })
                    needsPersist = true
                }
            }
        }

        root.configuredMonitors = parsed

        if (parsed.length > 0) {
            var found = false
            for (var k = 0; k < parsed.length; k++) {
                if (parsed[k].name === root.activeMonitorName) {
                    found = true
                    break
                }
            }
            if (!found) {
                var preferred = displayController.autoDetectMonitor()
                root.activeMonitorName = (preferred && preferred.name) ? preferred.name : parsed[0].name
            }
        } else {
            root.activeMonitorName = ""
        }

        if (needsPersist) {
            root.persistSettings()
        }
    }

    onSettingsChanged: {
        root.syncConfiguration()
    }

    Component.onCompleted: {
        root.syncConfiguration()
        displayController.discoverMonitors()
    }

    function persistSettings() {
        var entry = {}
        if (root.settings && typeof root.settings === "object") {
            for (var key in root.settings) {
                if (key !== "id" && key !== "monitors" && key !== "monitor" && key !== "acMode" && key !== "batteryMode") {
                    entry[key] = root.settings[key]
                }
            }
        }

        entry.monitors = root.configuredMonitors

        // Maintain backward compatibility for single-monitor readers
        if (root.configuredMonitors.length > 0) {
            entry.monitor = root.configuredMonitors[0].name
            entry.acMode = root.configuredMonitors[0].acMode
            entry.batteryMode = root.configuredMonitors[0].batteryMode
        } else {
            entry.monitor = ""
            entry.acMode = ""
            entry.batteryMode = ""
        }

        root.settings = entry

        var modName = root.moduleName || "battery-display-profiles"
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
            root.bar.shell.updateEntryInline(modName, entry)
        }
    }

    function toggle() {
        if (root.opened) {
            root.close()
        } else {
            root.open()
        }
    }

    function open() {
        root.currentView = "main"
        root.editingProfileKey = ""
        displayController.discoverMonitors()
        root.opened = true
    }

    function close() {
        root.currentView = "main"
        root.editingProfileKey = ""
        root.opened = false
    }

    function modeLabel(mode) {
        var normalized = displayController.normalizeMode(mode)
        var parsed = displayController.parseMode(normalized)
        if (!parsed) return mode
        return parsed.width + "×" + parsed.height + " · " + Math.round(parsed.refreshRate) + " Hz"
    }

    function isCurrentMode(mode) {
        return displayController.modesEquivalent(mode, root.activeCurrentMode)
    }

    function selectMode(mode) {
        if (isCurrentMode(mode) || !root.isActiveConnected) return
        displayController.applyMode(root.activeMonitorName, mode)
    }

    function toggleActiveMonitorEnabled() {
        if (!root.activeConfiguredMonitor) return
        var list = []
        for (var i = 0; i < root.configuredMonitors.length; i++) {
            var item = root.configuredMonitors[i]
            if (item.name === root.activeMonitorName) {
                list.push({
                    name: item.name,
                    enabled: !item.enabled,
                    acMode: item.acMode,
                    batteryMode: item.batteryMode
                })
            } else {
                list.push(item)
            }
        }
        root.configuredMonitors = list
        root.persistSettings()
    }

    function removeActiveMonitor() {
        if (!root.activeConfiguredMonitor) return
        var list = []
        for (var i = 0; i < root.configuredMonitors.length; i++) {
            if (root.configuredMonitors[i].name !== root.activeMonitorName) {
                list.push(root.configuredMonitors[i])
            }
        }
        root.configuredMonitors = list
        root.activeMonitorName = list.length > 0 ? list[0].name : ""
        root.persistSettings()
    }

    function addDiscoveredMonitor(mon) {
        if (!mon || !mon.name) return
        var list = []
        for (var i = 0; i < root.configuredMonitors.length; i++) {
            list.push(root.configuredMonitors[i])
        }
        var newEntry = {
            name: mon.name,
            enabled: true,
            acMode: displayController.highestMode(mon),
            batteryMode: displayController.lowestMode(mon)
        }
        list.push(newEntry)
        root.configuredMonitors = list
        root.activeMonitorName = mon.name
        root.currentView = "main"
        root.persistSettings()
    }

    function saveEditedMode(mode) {
        if (!root.activeConfiguredMonitor || root.editingProfileKey === "") return
        var norm = displayController.normalizeMode(mode)
        var list = []
        for (var i = 0; i < root.configuredMonitors.length; i++) {
            var item = root.configuredMonitors[i]
            if (item.name === root.activeMonitorName) {
                var updated = {
                    name: item.name,
                    enabled: item.enabled,
                    acMode: root.editingProfileKey === "ac" ? norm : item.acMode,
                    batteryMode: root.editingProfileKey === "battery" ? norm : item.batteryMode
                }
                list.push(updated)
            } else {
                list.push(item)
            }
        }
        root.configuredMonitors = list
        root.currentView = "main"
        root.editingProfileKey = ""
        root.persistSettings()
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

        text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"

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

        contentWidth: panel.fittedContentWidth(Style.space(380))
        contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent

            onCloseRequested: {
                if (root.currentView !== "main") {
                    root.currentView = "main"
                    root.editingProfileKey = ""
                } else {
                    root.close()
                }
            }
        }

        ScrollView {
            id: scrollArea
            anchors.fill: parent
            clip: true

            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

            Column {
                id: panelColumn
                width: scrollArea.availableWidth
                spacing: Style.space(14)

                /*
                 * -------------------------------------------------
                 * Top Header
                 * -------------------------------------------------
                 */

                Item {
                    width: parent.width
                    implicitHeight: Math.max(headerIcon.implicitHeight, headerTextCol.implicitHeight)

                    Text {
                        id: headerIcon
                        textFormat: Text.PlainText
                        text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.display
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Item {
                        id: headerTextCol
                        anchors.left: headerIcon.right
                        anchors.leftMargin: Style.space(12)
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: headerTextColLayout.implicitHeight

                        Column {
                            id: headerTextColLayout
                            width: parent.width
                            spacing: Style.space(2)

                            Text {
                                width: parent.width
                                text: root.currentView === "main"
                                    ? "Display Profiles"
                                    : (root.currentView === "addMonitor"
                                        ? "Add Monitor"
                                        : (root.editingProfileKey === "ac" ? "AC Mode Profile" : "Battery Mode Profile"))
                                color: root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: root.currentView === "main"
                                    ? (root.powerState + " power active (" + root.configuredMonitors.length + " monitor" + (root.configuredMonitors.length === 1 ? "" : "s") + ")")
                                    : (root.currentView === "addMonitor"
                                        ? "Select an output to configure"
                                        : "Choose mode for " + root.activeMonitorName)
                                color: Qt.darker(root.bar.foreground, 1.4)
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                PanelSeparator {
                    foreground: root.bar.foreground
                }

                /*
                 * =================================================
                 * MAIN VIEW
                 * =================================================
                 */

                Column {
                    width: parent.width
                    visible: root.currentView === "main"
                    spacing: Style.space(12)

                    /*
                     * ---------------------------------------------
                     * Monitor Selector Tabs / Chips
                     * ---------------------------------------------
                     */

                    Flow {
                        width: parent.width
                        spacing: Style.space(6)

                        Repeater {
                            model: root.configuredMonitors

                            delegate: CursorSurface {
                                required property var modelData
                                required property int index

                                implicitHeight: Style.spacing.controlHeight
                                implicitWidth: monChipRow.implicitWidth + Style.space(16)
                                foreground: root.bar.foreground
                                current: modelData.name === root.activeMonitorName
                                fill: Style.hoverFillFor(root.bar.foreground, Color.accent)
                                currentFill: Style.selectedFillFor(root.bar.foreground, Color.accent)

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.activeMonitorName = modelData.name
                                    }
                                }

                                Row {
                                    id: monChipRow
                                    anchors.centerIn: parent
                                    spacing: Style.space(6)

                                    // Connection status dot
                                    Text {
                                        readonly property bool isConn: displayController.findMonitor(modelData.name) !== null
                                        text: "●"
                                        color: isConn ? "#98c379" : Qt.darker(root.bar.foreground, 1.8)
                                        font.pixelSize: Style.font.caption
                                    }

                                    Text {
                                        text: modelData.name
                                        color: root.bar.foreground
                                        font.family: root.bar.fontFamily
                                        font.pixelSize: Style.font.body
                                        font.bold: modelData.name === root.activeMonitorName
                                    }

                                    Text {
                                        visible: !modelData.enabled
                                        text: "(off)"
                                        color: Qt.darker(root.bar.foreground, 1.5)
                                        font.family: root.bar.fontFamily
                                        font.pixelSize: Style.font.caption
                                    }
                                }
                            }
                        }

                        // "+ Add" chip if there are unconfigured monitors
                        CursorSurface {
                            visible: root.unconfiguredDiscoveredMonitors.length > 0
                            implicitHeight: Style.spacing.controlHeight
                            implicitWidth: addChipRow.implicitWidth + Style.space(16)
                            foreground: root.bar.foreground
                            fill: Style.hoverFillFor(root.bar.foreground, Color.accent)

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.currentView = "addMonitor"
                                }
                            }

                            Row {
                                id: addChipRow
                                anchors.centerIn: parent
                                spacing: Style.space(4)

                                Text {
                                    text: "+"
                                    color: Color.accent
                                    font.bold: true
                                    font.pixelSize: Style.font.body
                                }

                                Text {
                                    text: "Add Monitor"
                                    color: root.bar.foreground
                                    font.family: root.bar.fontFamily
                                    font.pixelSize: Style.font.body
                                }
                            }
                        }
                    }

                    /*
                     * ---------------------------------------------
                     * Active Monitor Card
                     * ---------------------------------------------
                     */

                    Item {
                        width: parent.width
                        implicitHeight: activeCardCol.implicitHeight

                        visible: root.activeConfiguredMonitor !== null

                        Column {
                            id: activeCardCol
                            width: parent.width
                            spacing: Style.space(10)

                            // Monitor Header Row: Name, Status badge, Enabled toggle, Remove button
                            Item {
                                width: parent.width
                                implicitHeight: Math.max(monitorTitleRow.implicitHeight, actionButtonsRow.implicitHeight)

                                Row {
                                    id: monitorTitleRow
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Style.space(8)

                                    Text {
                                        text: root.activeMonitorName
                                        color: root.bar.foreground
                                        font.family: root.bar.fontFamily
                                        font.pixelSize: Style.font.title
                                        font.bold: true
                                    }

                                    // Connected / Disconnected badge
                                    CursorSurface {
                                        implicitHeight: Style.space(22)
                                        implicitWidth: connBadgeRow.implicitWidth + Style.space(12)
                                        foreground: root.bar.foreground
                                        fill: root.isActiveConnected
                                            ? Qt.rgba(152/255, 195/255, 121/255, 0.15)
                                            : Qt.rgba(224/255, 108/255, 117/255, 0.15)

                                        Row {
                                            id: connBadgeRow
                                            anchors.centerIn: parent
                                            spacing: Style.space(4)

                                            Text {
                                                text: root.isActiveConnected ? "●" : "○"
                                                color: root.isActiveConnected ? "#98c379" : "#e06c75"
                                                font.pixelSize: Style.font.caption
                                            }

                                            Text {
                                                text: root.isActiveConnected ? "Connected" : "Disconnected"
                                                color: root.isActiveConnected ? "#98c379" : "#e06c75"
                                                font.family: root.bar.fontFamily
                                                font.pixelSize: Style.font.caption
                                                font.bold: true
                                            }
                                        }
                                    }
                                }

                                Row {
                                    id: actionButtonsRow
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Style.space(6)

                                    // Enable / Disable toggle button
                                    CursorSurface {
                                        implicitHeight: Style.spacing.controlHeight
                                        implicitWidth: enableToggleRow.implicitWidth + Style.space(12)
                                        foreground: root.bar.foreground
                                        current: root.activeConfiguredMonitor ? root.activeConfiguredMonitor.enabled : false
                                        fill: Style.hoverFillFor(root.bar.foreground, Color.accent)
                                        currentFill: Style.selectedFillFor(root.bar.foreground, Color.accent)

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.toggleActiveMonitorEnabled()
                                            }
                                        }

                                        Row {
                                            id: enableToggleRow
                                            anchors.centerIn: parent
                                            spacing: Style.space(6)

                                            Text {
                                                text: (root.activeConfiguredMonitor && root.activeConfiguredMonitor.enabled) ? "󰄬" : "󰅖"
                                                color: root.bar.foreground
                                                font.family: root.bar.fontFamily
                                                font.pixelSize: Style.font.body
                                            }

                                            Text {
                                                text: (root.activeConfiguredMonitor && root.activeConfiguredMonitor.enabled) ? "Enabled" : "Disabled"
                                                color: root.bar.foreground
                                                font.family: root.bar.fontFamily
                                                font.pixelSize: Style.font.caption
                                                font.bold: true
                                            }
                                        }
                                    }

                                    // Remove monitor button
                                    CursorSurface {
                                        implicitHeight: Style.spacing.controlHeight
                                        implicitWidth: Style.spacing.controlHeight
                                        foreground: root.bar.foreground
                                        fill: Style.hoverFillFor(root.bar.foreground, Color.accent)

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.removeActiveMonitor()
                                            }
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰆴"
                                            color: "#e06c75"
                                            font.family: root.bar.fontFamily
                                            font.pixelSize: Style.font.body
                                        }
                                    }
                                }
                            }

                            // Disconnected notice if disconnected
                            Text {
                                visible: !root.isActiveConnected
                                width: parent.width
                                text: "Monitor is currently disconnected. Profiles will apply automatically upon connection."
                                color: Qt.darker(root.bar.foreground, 1.4)
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                            }

                            /*
                             * CURRENT MODE (if connected)
                             */
                            Column {
                                width: parent.width
                                visible: root.isActiveConnected
                                spacing: Style.space(4)

                                PanelSectionHeader {
                                    text: "CURRENT"
                                    foreground: root.bar.foreground
                                    fontFamily: root.bar.fontFamily
                                }

                                Text {
                                    text: root.activeCurrentMode !== "" ? root.modeLabel(root.activeCurrentMode) : "Unknown"
                                    color: root.bar.foreground
                                    font.family: root.bar.fontFamily
                                    font.pixelSize: Style.font.body
                                    font.bold: true
                                }
                            }

                            /*
                             * QUICK REFRESH RATE TOGGLES (if connected)
                             */
                            Column {
                                width: parent.width
                                visible: root.isActiveConnected && root.activeLiveMonitor && Array.isArray(root.activeLiveMonitor.availableModes) && root.activeLiveMonitor.availableModes.length > 0
                                spacing: Style.space(6)

                                PanelSectionHeader {
                                    text: "REFRESH RATE"
                                    foreground: root.bar.foreground
                                    fontFamily: root.bar.fontFamily
                                }

                                Flow {
                                    width: parent.width
                                    spacing: Style.space(6)

                                    Repeater {
                                        model: {
                                            if (!root.activeLiveMonitor) return []
                                            var curModes = displayController.modesForCurrentResolution(root.activeLiveMonitor)
                                            return curModes.map(function(m) { return m.raw })
                                        }

                                        delegate: CursorSurface {
                                            required property var modelData
                                            required property int index

                                            implicitHeight: Style.spacing.controlHeight
                                            implicitWidth: hzText.implicitWidth + Style.space(20)
                                            foreground: root.bar.foreground
                                            current: root.isCurrentMode(modelData)
                                            fill: Style.hoverFillFor(root.bar.foreground, Color.accent)
                                            currentFill: Style.selectedFillFor(root.bar.foreground, Color.accent)

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.selectMode(modelData)
                                                }
                                            }

                                            Text {
                                                id: hzText
                                                anchors.centerIn: parent
                                                text: {
                                                    var p = displayController.parseMode(modelData)
                                                    return p ? (Math.round(p.refreshRate) + " Hz") : modelData
                                                }
                                                color: root.bar.foreground
                                                font.family: root.bar.fontFamily
                                                font.pixelSize: Style.font.body
                                                font.bold: root.isCurrentMode(modelData)
                                            }
                                        }
                                    }
                                }
                            }

                            /*
                             * POWER PROFILES (AC & Battery cards)
                             */
                            Column {
                                width: parent.width
                                spacing: Style.space(6)

                                PanelSectionHeader {
                                    text: "POWER PROFILES"
                                    foreground: root.bar.foreground
                                    fontFamily: root.bar.fontFamily
                                }

                                // AC Profile Card
                                CursorSurface {
                                    width: parent.width
                                    implicitHeight: Style.spacing.controlHeight + Style.space(12)
                                    foreground: root.bar.foreground
                                    current: root.powerState === "AC" && (root.activeConfiguredMonitor && root.activeConfiguredMonitor.enabled)
                                    fill: Style.hoverFillFor(root.bar.foreground, Color.accent)
                                    currentFill: Style.selectedFillFor(root.bar.foreground, Color.accent)

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.editingProfileKey = "ac"
                                            root.currentView = "editMode"
                                        }
                                    }

                                    Row {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: Style.space(12)
                                        anchors.rightMargin: Style.space(12)
                                        spacing: Style.space(10)

                                        Text {
                                            text: "󰚥"
                                            color: root.bar.foreground
                                            font.family: root.bar.fontFamily
                                            font.pixelSize: Style.font.title
                                        }

                                        Column {
                                            width: parent.width - Style.space(60)
                                            spacing: Style.space(1)

                                            Text {
                                                text: "AC Profile"
                                                color: root.bar.foreground
                                                font.family: root.bar.fontFamily
                                                font.pixelSize: Style.font.body
                                                font.bold: true
                                            }

                                            Text {
                                                text: (root.activeConfiguredMonitor && root.activeConfiguredMonitor.acMode)
                                                    ? root.modeLabel(root.activeConfiguredMonitor.acMode)
                                                    : "Not configured"
                                                color: Qt.darker(root.bar.foreground, 1.4)
                                                font.family: root.bar.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }
                                        }

                                        Text {
                                            text: "󰄾"
                                            color: Qt.darker(root.bar.foreground, 1.5)
                                            font.family: root.bar.fontFamily
                                            font.pixelSize: Style.font.body
                                        }
                                    }
                                }

                                // Battery Profile Card
                                CursorSurface {
                                    width: parent.width
                                    implicitHeight: Style.spacing.controlHeight + Style.space(12)
                                    foreground: root.bar.foreground
                                    current: root.powerState === "Battery" && (root.activeConfiguredMonitor && root.activeConfiguredMonitor.enabled)
                                    fill: Style.hoverFillFor(root.bar.foreground, Color.accent)
                                    currentFill: Style.selectedFillFor(root.bar.foreground, Color.accent)

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.editingProfileKey = "battery"
                                            root.currentView = "editMode"
                                        }
                                    }

                                    Row {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: Style.space(12)
                                        anchors.rightMargin: Style.space(12)
                                        spacing: Style.space(10)

                                        Text {
                                            text: "󰂁"
                                            color: root.bar.foreground
                                            font.family: root.bar.fontFamily
                                            font.pixelSize: Style.font.title
                                        }

                                        Column {
                                            width: parent.width - Style.space(60)
                                            spacing: Style.space(1)

                                            Text {
                                                text: "Battery Profile"
                                                color: root.bar.foreground
                                                font.family: root.bar.fontFamily
                                                font.pixelSize: Style.font.body
                                                font.bold: true
                                            }

                                            Text {
                                                text: (root.activeConfiguredMonitor && root.activeConfiguredMonitor.batteryMode)
                                                    ? root.modeLabel(root.activeConfiguredMonitor.batteryMode)
                                                    : "Not configured"
                                                color: Qt.darker(root.bar.foreground, 1.4)
                                                font.family: root.bar.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }
                                        }

                                        Text {
                                            text: "󰄾"
                                            color: Qt.darker(root.bar.foreground, 1.5)
                                            font.family: root.bar.fontFamily
                                            font.pixelSize: Style.font.body
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Empty state if no monitor configured
                    Column {
                        width: parent.width
                        visible: root.configuredMonitors.length === 0
                        spacing: Style.space(8)

                        Text {
                            width: parent.width
                            text: "No monitors currently configured."
                            color: root.bar.foreground
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.body
                        }

                        CursorSurface {
                            width: parent.width
                            implicitHeight: Style.spacing.controlHeight + Style.space(8)
                            foreground: root.bar.foreground
                            fill: Style.hoverFillFor(root.bar.foreground, Color.accent)

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.currentView = "addMonitor"
                                }
                            }

                            Row {
                                anchors.centerIn: parent
                                spacing: Style.space(8)

                                Text {
                                    text: "󰐕"
                                    color: Color.accent
                                    font.family: root.bar.fontFamily
                                    font.pixelSize: Style.font.body
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: "Add Discovered Monitor"
                                    color: root.bar.foreground
                                    font.family: root.bar.fontFamily
                                    font.pixelSize: Style.font.body
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }

                /*
                 * =================================================
                 * EDIT MODE VIEW (AC or Battery)
                 * =================================================
                 */

                Column {
                    width: parent.width
                    visible: root.currentView === "editMode"
                    spacing: Style.space(12)

                    // Back button
                    CursorSurface {
                        implicitHeight: Style.spacing.controlHeight
                        implicitWidth: backBtnRow.implicitWidth + Style.space(16)
                        foreground: root.bar.foreground
                        fill: Style.hoverFillFor(root.bar.foreground, Color.accent)

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentView = "main"
                                root.editingProfileKey = ""
                            }
                        }

                        Row {
                            id: backBtnRow
                            anchors.centerIn: parent
                            spacing: Style.space(6)

                            Text {
                                text: "󰁍"
                                color: root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.body
                            }

                            Text {
                                text: "Back"
                                color: root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.body
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: "Select display mode for " + (root.editingProfileKey === "ac" ? "AC" : "Battery") + " power on " + root.activeMonitorName + ":"
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }

                    Column {
                        width: parent.width
                        spacing: Style.space(4)

                        Repeater {
                            model: {
                                if (!root.activeLiveMonitor) return []
                                var curModes = displayController.modesForCurrentResolution(root.activeLiveMonitor)
                                if (curModes.length > 0) {
                                    return curModes.map(function(m) { return m.raw })
                                }
                                return root.activeLiveMonitor.availableModes || []
                            }

                            delegate: CursorSurface {
                                required property var modelData
                                required property int index

                                width: parent.width
                                implicitHeight: Style.spacing.controlHeight + Style.space(8)
                                foreground: root.bar.foreground
                                current: {
                                    if (!root.activeConfiguredMonitor) return false
                                    var currentSaved = root.editingProfileKey === "ac"
                                        ? root.activeConfiguredMonitor.acMode
                                        : root.activeConfiguredMonitor.batteryMode
                                    return displayController.modesEquivalent(modelData, currentSaved)
                                }
                                fill: Style.hoverFillFor(root.bar.foreground, Color.accent)
                                currentFill: Style.selectedFillFor(root.bar.foreground, Color.accent)

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.saveEditedMode(modelData)
                                    }
                                }

                                Row {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Style.space(12)
                                    anchors.rightMargin: Style.space(12)
                                    spacing: Style.space(10)

                                    Text {
                                        text: {
                                            var currentSaved = root.editingProfileKey === "ac"
                                                ? (root.activeConfiguredMonitor ? root.activeConfiguredMonitor.acMode : "")
                                                : (root.activeConfiguredMonitor ? root.activeConfiguredMonitor.batteryMode : "")
                                            return displayController.modesEquivalent(modelData, currentSaved) ? "󰄬" : "󰍹"
                                        }
                                        color: root.bar.foreground
                                        font.family: root.bar.fontFamily
                                        font.pixelSize: Style.font.body
                                    }

                                    Text {
                                        width: parent.width - Style.space(40)
                                        text: root.modeLabel(modelData)
                                        color: root.bar.foreground
                                        font.family: root.bar.fontFamily
                                        font.pixelSize: Style.font.body
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                /*
                 * =================================================
                 * ADD MONITOR VIEW
                 * =================================================
                 */

                Column {
                    width: parent.width
                    visible: root.currentView === "addMonitor"
                    spacing: Style.space(12)

                    // Back button
                    CursorSurface {
                        implicitHeight: Style.spacing.controlHeight
                        implicitWidth: addBackBtnRow.implicitWidth + Style.space(16)
                        foreground: root.bar.foreground
                        fill: Style.hoverFillFor(root.bar.foreground, Color.accent)

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentView = "main"
                            }
                        }

                        Row {
                            id: addBackBtnRow
                            anchors.centerIn: parent
                            spacing: Style.space(6)

                            Text {
                                text: "󰁍"
                                color: root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.body
                            }

                            Text {
                                text: "Back"
                                color: root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.body
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: "Discovered displays not yet configured:"
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    Column {
                        width: parent.width
                        spacing: Style.space(4)

                        Repeater {
                            model: root.unconfiguredDiscoveredMonitors

                            delegate: CursorSurface {
                                required property var modelData
                                required property int index

                                width: parent.width
                                implicitHeight: Style.spacing.controlHeight + Style.space(12)
                                foreground: root.bar.foreground
                                fill: Style.hoverFillFor(root.bar.foreground, Color.accent)

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.addDiscoveredMonitor(modelData)
                                    }
                                }

                                Row {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Style.space(12)
                                    anchors.rightMargin: Style.space(12)
                                    spacing: Style.space(10)

                                    Text {
                                        text: "󰍹"
                                        color: root.bar.foreground
                                        font.family: root.bar.fontFamily
                                        font.pixelSize: Style.font.title
                                    }

                                    Column {
                                        width: parent.width - Style.space(70)
                                        spacing: Style.space(1)

                                        Text {
                                            text: modelData.name + (modelData.description ? (" (" + modelData.description + ")") : "")
                                            color: root.bar.foreground
                                            font.family: root.bar.fontFamily
                                            font.pixelSize: Style.font.body
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: modelData.width + "×" + modelData.height + " · " + Math.round(modelData.refreshRate) + " Hz"
                                            color: Qt.darker(root.bar.foreground, 1.4)
                                            font.family: root.bar.fontFamily
                                            font.pixelSize: Style.font.caption
                                        }
                                    }

                                    Text {
                                        text: "+ Add"
                                        color: Color.accent
                                        font.family: root.bar.fontFamily
                                        font.pixelSize: Style.font.body
                                        font.bold: true
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.unconfiguredDiscoveredMonitors.length === 0
                            width: parent.width
                            text: "All discovered displays are already configured."
                            color: Qt.darker(root.bar.foreground, 1.4)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }
                }
            }
        }
    }
}