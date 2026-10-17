import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var monitors: []

    readonly property bool busy:
        commandProcess.running

    property string operation: ""

    property string pendingMonitorName: ""
    property string pendingMode: ""

    property var pendingDiscoveryMonitors: null
    property string pendingDiscoveryError: ""

    signal discoveryCompleted(var monitors)
    signal discoveryFailed(string error)

    signal modeApplied(
        string monitorName,
        string mode
    )

    signal modeApplyFailed(
        string monitorName,
        string mode
    )

    /*
     * ---------------------------------------------------------
     * Monitor discovery
     * ---------------------------------------------------------
     */

    function discoverMonitors() {
        if (commandProcess.running) {
            console.log(
                "[Battery Display Profiles] Discovery requested while another operation is running"
            )

            return false
        }

        operation = "discover"

        pendingDiscoveryMonitors = null
        pendingDiscoveryError = ""

        commandProcess.command = [
            "hyprctl",
            "monitors",
            "-j"
        ]

        console.log(
            "[Battery Display Profiles] Discovering monitors..."
        )

        commandProcess.running = true

        return true
    }

    /*
     * ---------------------------------------------------------
     * Monitor lookup
     * ---------------------------------------------------------
     */

    function findMonitor(name) {
        for (
            var i = 0;
            i < monitors.length;
            i++
        ) {
            if (
                monitors[i].name === name
            ) {
                return monitors[i]
            }
        }

        return null
    }

    function autoDetectMonitor() {
        if (!Array.isArray(monitors) || monitors.length === 0) {
            return null
        }

        // 1. Prefer internal laptop display (eDP, LVDS)
        for (var i = 0; i < monitors.length; i++) {
            if (/^(eDP|LVDS)/i.test(monitors[i].name)) {
                return monitors[i]
            }
        }

        // 2. Prefer focused monitor
        for (var j = 0; j < monitors.length; j++) {
            if (monitors[j].focused === true) {
                return monitors[j]
            }
        }

        // 3. Fallback to first discovered monitor
        return monitors[0]
    }

    /*
     * ---------------------------------------------------------
     * Current resolution modes lookup
     *
     * Finds all modes matching the monitor's active resolution,
     * accounting for normal and rotated displays (90/270 deg).
     * ---------------------------------------------------------
     */

    function modesForCurrentResolution(monitor) {
        if (!monitor || !Array.isArray(monitor.availableModes) || monitor.availableModes.length === 0) {
            return []
        }

        var currentW = Number(monitor.width)
        var currentH = Number(monitor.height)
        if (isNaN(currentW) || isNaN(currentH) || currentW <= 0 || currentH <= 0) {
            return []
        }

        var matches = []

        // 1. Direct match with current width and height
        for (var i = 0; i < monitor.availableModes.length; i++) {
            var parsed = parseMode(monitor.availableModes[i])
            if (!parsed) continue

            if (parsed.width === currentW && parsed.height === currentH) {
                matches.push({
                    raw: monitor.availableModes[i],
                    normalized: normalizeMode(monitor.availableModes[i]),
                    parsed: parsed
                })
            }
        }

        // 2. Swapped match for rotated displays (transform 90/270 degrees)
        if (matches.length === 0) {
            for (var j = 0; j < monitor.availableModes.length; j++) {
                var parsedRot = parseMode(monitor.availableModes[j])
                if (!parsedRot) continue

                if (parsedRot.width === currentH && parsedRot.height === currentW) {
                    matches.push({
                        raw: monitor.availableModes[j],
                        normalized: normalizeMode(monitor.availableModes[j]),
                        parsed: parsedRot
                    })
                }
            }
        }

        matches.sort(function(a, b) {
            return b.parsed.refreshRate - a.parsed.refreshRate
        })

        return matches
    }

    function modeMatchesCurrentResolution(monitor, mode) {
        if (!monitor || typeof mode !== "string" || mode.trim() === "") {
            return false
        }

        var parsed = parseMode(mode)
        if (!parsed) {
            return false
        }

        var currentW = Number(monitor.width)
        var currentH = Number(monitor.height)
        if (isNaN(currentW) || isNaN(currentH)) {
            return false
        }

        return (parsed.width === currentW && parsed.height === currentH) ||
               (parsed.width === currentH && parsed.height === currentW)
    }

    function highestMode(monitor) {
        if (!monitor) {
            return ""
        }

        var matches = modesForCurrentResolution(monitor)
        if (matches.length === 0) {
            // Guarantee: NEVER change resolution, fallback to currentMode
            return currentMode(monitor)
        }

        var best = matches[0]
        for (var i = 1; i < matches.length; i++) {
            if (matches[i].parsed.refreshRate > best.parsed.refreshRate) {
                best = matches[i]
            }
        }

        return best.normalized
    }

    function lowestMode(monitor) {
        if (!monitor) {
            return ""
        }

        var matches = modesForCurrentResolution(monitor)
        if (matches.length === 0) {
            // Guarantee: NEVER change resolution, fallback to currentMode
            return currentMode(monitor)
        }

        // For battery mode, prefer ~60Hz if available (>= 59.0Hz)
        // to avoid picking an unusable 24Hz/30Hz mode on HDMI/TV displays.
        var smoothModes = []
        for (var i = 0; i < matches.length; i++) {
            if (matches[i].parsed.refreshRate >= 59.0) {
                smoothModes.push(matches[i])
            }
        }

        var candidates = (smoothModes.length > 0) ? smoothModes : matches
        var best = candidates[0]
        for (var j = 1; j < candidates.length; j++) {
            if (candidates[j].parsed.refreshRate < best.parsed.refreshRate) {
                best = candidates[j]
            }
        }

        return best.normalized
    }

    /*
     * ---------------------------------------------------------
     * Resolution helper functions
     * ---------------------------------------------------------
     */

    function gcd(a, b) {
        var x = Math.abs(a)
        var y = Math.abs(b)
        while (y !== 0) {
            var t = y
            y = x % y
            x = t
        }
        return x
    }

    function aspectRatio(width, height) {
        var w = Number(width)
        var h = Number(height)
        if (isNaN(w) || isNaN(h) || w <= 0 || h <= 0) {
            return ""
        }

        var ratio = w / h
        if (Math.abs(ratio - 16 / 9) < 0.02) return "16:9"
        if (Math.abs(ratio - 16 / 10) < 0.02) return "16:10"
        if (Math.abs(ratio - 4 / 3) < 0.02) return "4:3"
        if (Math.abs(ratio - 5 / 4) < 0.02) return "5:4"
        if (Math.abs(ratio - 21 / 9) < 0.05 || Math.abs(ratio - 64 / 27) < 0.05) return "21:9"
        if (Math.abs(ratio - 32 / 9) < 0.05) return "32:9"

        var d = gcd(w, h)
        var rw = w / d
        var rh = h / d
        if (rw < 50 && rh < 50) {
            return rw + ":" + rh
        }
        return (Math.round(ratio * 10) / 10) + ":1"
    }

    function availableResolutions(monitor) {
        if (!monitor || !Array.isArray(monitor.availableModes) || monitor.availableModes.length === 0) {
            return []
        }

        var currentW = Number(monitor.width)
        var currentH = Number(monitor.height)

        var map = {}
        for (var i = 0; i < monitor.availableModes.length; i++) {
            var rawMode = monitor.availableModes[i]
            var parsed = parseMode(rawMode)
            if (!parsed) continue

            var key = parsed.width + "x" + parsed.height
            if (!map[key]) {
                var isCurrent = (parsed.width === currentW && parsed.height === currentH) ||
                                (parsed.width === currentH && parsed.height === currentW)
                map[key] = {
                    width: parsed.width,
                    height: parsed.height,
                    label: parsed.width + " × " + parsed.height,
                    aspect: aspectRatio(parsed.width, parsed.height),
                    pixelCount: parsed.width * parsed.height,
                    isCurrent: isCurrent,
                    refreshRates: [],
                    modes: []
                }
            }

            // Avoid duplicate refresh rates (within 0.01 Hz)
            var rateExists = false
            for (var r = 0; r < map[key].refreshRates.length; r++) {
                if (Math.abs(map[key].refreshRates[r] - parsed.refreshRate) < 0.01) {
                    rateExists = true
                    break
                }
            }
            if (!rateExists) {
                map[key].refreshRates.push(parsed.refreshRate)
            }
            map[key].modes.push(rawMode)
        }

        var list = []
        for (var k in map) {
            if (map.hasOwnProperty(k)) {
                // Sort refresh rates descending
                map[k].refreshRates.sort(function(a, b) {
                    return b - a
                })
                list.push(map[k])
            }
        }

        // Sort resolutions by pixel count descending, then width descending
        list.sort(function(a, b) {
            if (b.pixelCount !== a.pixelCount) {
                return b.pixelCount - a.pixelCount
            }
            return b.width - a.width
        })

        return list
    }

    function modesForResolution(monitor, width, height) {
        if (!monitor || !Array.isArray(monitor.availableModes)) {
            return []
        }

        var targetW = Number(width)
        var targetH = Number(height)
        if (isNaN(targetW) || isNaN(targetH)) {
            return []
        }

        var matches = []
        for (var i = 0; i < monitor.availableModes.length; i++) {
            var parsed = parseMode(monitor.availableModes[i])
            if (!parsed) continue

            if ((parsed.width === targetW && parsed.height === targetH) ||
                (parsed.width === targetH && parsed.height === targetW)) {
                matches.push({
                    raw: monitor.availableModes[i],
                    normalized: normalizeMode(monitor.availableModes[i]),
                    parsed: parsed
                })
            }
        }

        matches.sort(function(a, b) {
            return b.parsed.refreshRate - a.parsed.refreshRate
        })

        return matches
    }

    function highestModeForResolution(monitor, width, height) {
        if (!monitor) return ""
        var matches = modesForResolution(monitor, width, height)
        if (matches.length === 0) {
            return currentMode(monitor)
        }
        return matches[0].normalized
    }

    function lowestModeForResolution(monitor, width, height) {
        if (!monitor) return ""
        var matches = modesForResolution(monitor, width, height)
        if (matches.length === 0) {
            return currentMode(monitor)
        }

        var smoothModes = []
        for (var i = 0; i < matches.length; i++) {
            if (matches[i].parsed.refreshRate >= 59.0) {
                smoothModes.push(matches[i])
            }
        }

        var candidates = (smoothModes.length > 0) ? smoothModes : matches
        var best = candidates[0]
        for (var j = 1; j < candidates.length; j++) {
            if (candidates[j].parsed.refreshRate < best.parsed.refreshRate) {
                best = candidates[j]
            }
        }

        return best.normalized
    }

    /*
     * ---------------------------------------------------------
     * Mode normalization
     * ---------------------------------------------------------
     */

    function normalizeMode(mode) {
        if (
            typeof mode !== "string"
        ) {
            return ""
        }

        var result =
            mode.trim()

        result =
            result.replace(
                /Hz$/i,
                ""
            )

        var parts =
            result.split("@")

        if (
            parts.length !== 2
        ) {
            return result
        }

        var refreshRate =
            Number(parts[1])

        if (
            isNaN(refreshRate)
        ) {
            return result
        }

        return (
            parts[0] +
            "@" +
            refreshRate
        )
    }

    function parseMode(mode) {
        var normalized =
            normalizeMode(mode)

        var parts =
            normalized.split("@")

        if (
            parts.length !== 2
        ) {
            return null
        }

        var resolution =
            parts[0].split("x")

        if (
            resolution.length !== 2
        ) {
            return null
        }

        var width =
            Number(resolution[0])

        var height =
            Number(resolution[1])

        var refreshRate =
            Number(parts[1])

        if (
            isNaN(width) ||
            isNaN(height) ||
            isNaN(refreshRate)
        ) {
            return null
        }

        return {
            width: width,
            height: height,
            refreshRate: refreshRate
        }
    }

    function formatRefreshRate(rate) {
        var num = Number(rate)
        if (isNaN(num)) {
            return ""
        }

        if (Math.abs(num - Math.round(num)) < 0.005) {
            num = Math.round(num)
        } else {
            num = Number(num.toFixed(2))
        }

        return num + " Hz"
    }

    /*
     * ---------------------------------------------------------
     * Mode comparison
     * ---------------------------------------------------------
     */

    function modesEquivalent(
        firstMode,
        secondMode
    ) {
        var first =
            parseMode(firstMode)

        var second =
            parseMode(secondMode)

        if (
            !first ||
            !second
        ) {
            return false
        }

        if (
            first.width !==
                second.width ||
            first.height !==
                second.height
        ) {
            return false
        }

        /*
         * Hyprland may report the active refresh rate
         * slightly differently from availableModes due to DRM/KMS
         * hardware PLL clock jitter.
         *
         * Example:
         * available: 165.00
         * active:    165.002
         *
         * A tolerance of 0.01 accommodates PLL jitter (<0.005)
         * while strictly differentiating real NTSC drop-frame rates
         * (e.g. 59.94 vs 60.00, 143.98 vs 144.00, 23.98 vs 24.00).
         */
        return Math.abs(
            first.refreshRate -
            second.refreshRate
        ) < 0.01
    }

    function currentMode(monitor) {
        if (!monitor) {
            return ""
        }

        if (Array.isArray(monitor.availableModes) && monitor.availableModes.length > 0) {
            var currentW = Number(monitor.width)
            var currentH = Number(monitor.height)
            var currentHz = Number(monitor.refreshRate)
            var bestMode = ""
            var bestDiff = 999999

            for (var i = 0; i < monitor.availableModes.length; i++) {
                var p = parseMode(monitor.availableModes[i])
                if (!p) continue
                if ((p.width === currentW && p.height === currentH) ||
                    (p.width === currentH && p.height === currentW)) {
                    var diff = Math.abs(p.refreshRate - currentHz)
                    if (diff < bestDiff) {
                        bestDiff = diff
                        bestMode = normalizeMode(monitor.availableModes[i])
                    }
                }
            }
            if (bestMode !== "" && bestDiff < 0.5) {
                return bestMode
            }
        }

        return normalizeMode(
            monitor.width +
            "x" +
            monitor.height +
            "@" +
            monitor.refreshRate
        )
    }

    /*
     * ---------------------------------------------------------
     * Mode validation
     * ---------------------------------------------------------
     */

    function modeExists(
        monitor,
        requestedMode
    ) {
        if (!monitor) {
            return false
        }

        if (
            !Array.isArray(
                monitor.availableModes
            )
        ) {
            return false
        }

        for (
            var i = 0;
            i <
                monitor.availableModes.length;
            i++
        ) {
            if (
                modesEquivalent(
                    monitor.availableModes[i],
                    requestedMode
                )
            ) {
                return true
            }
        }

        return false
    }

    function validateMode(
        monitorName,
        requestedMode
    ) {
        var monitor =
            findMonitor(
                monitorName
            )

        if (!monitor) {
            console.warn(
                "[Battery Display Profiles] Monitor not found:",
                monitorName
            )

            return false
        }

        if (
            !modeExists(
                monitor,
                requestedMode
            )
        ) {
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

    /*
     * ---------------------------------------------------------
     * Lua string escaping
     * ---------------------------------------------------------
     */

    function escapeLuaString(value) {
        return String(value)
            .replace(
                /\\/g,
                "\\\\"
            )
            .replace(
                /"/g,
                '\\"'
            )
    }

    /*
     * ---------------------------------------------------------
     * Apply display mode
     * ---------------------------------------------------------
     */

    function applyMode(
        monitorName,
        requestedMode
    ) {
        if (
            commandProcess.running
        ) {
            console.warn(
                "[Battery Display Profiles] Cannot apply mode while another operation is running"
            )

            return false
        }

        var monitor =
            findMonitor(
                monitorName
            )

        if (!monitor) {
            console.warn(
                "[Battery Display Profiles] Cannot apply mode:",
                "monitor not found:",
                monitorName
            )

            modeApplyFailed(
                monitorName,
                requestedMode
            )

            return false
        }

        if (
            !modeExists(
                monitor,
                requestedMode
            )
        ) {
            console.warn(
                "[Battery Display Profiles] Refusing unavailable mode:",
                requestedMode,
                "on",
                monitorName
            )

            modeApplyFailed(
                monitorName,
                requestedMode
            )

            return false
        }

        var normalizedMode =
            normalizeMode(
                requestedMode
            )

        var lua =
            'hl.monitor({ output = "' +
            escapeLuaString(
                monitorName
            ) +
            '", mode = "' +
            escapeLuaString(
                normalizedMode
            ) +
            '" })'

        pendingMonitorName =
            monitorName

        pendingMode =
            normalizedMode

        operation = "apply"

        commandProcess.command = [
            "hyprctl",
            "eval",
            lua
        ]

        console.log(
            "[Battery Display Profiles] Applying mode:",
            monitorName,
            normalizedMode
        )

        console.log(
            "[Battery Display Profiles] Hyprland Lua:",
            lua
        )

        commandProcess.running = true

        return true
    }

    /*
     * ---------------------------------------------------------
     * Parse monitor discovery output
     *
     * IMPORTANT:
     *
     * We do NOT emit discoveryCompleted here.
     *
     * stdout finishing does not necessarily mean the
     * Process has emitted its exited signal yet.
     * We wait for onExited.
     * ---------------------------------------------------------
     */

    function handleDiscoveryData(
        data
    ) {
        var parsed

        try {
            parsed =
                JSON.parse(data)
        } catch (error) {
            var message =
                "Failed to parse hyprctl monitor JSON: " +
                error

            console.warn(
                "[Battery Display Profiles]",
                message
            )

            pendingDiscoveryError =
                message

            pendingDiscoveryMonitors =
                null

            return
        }

        if (
            !Array.isArray(parsed)
        ) {
            var message =
                "Unexpected monitor data from hyprctl"

            console.warn(
                "[Battery Display Profiles]",
                message
            )

            pendingDiscoveryError =
                message

            pendingDiscoveryMonitors =
                null

            return
        }

        pendingDiscoveryMonitors =
            parsed

        pendingDiscoveryError = ""

        console.log(
            "[Battery Display Profiles] Discovered",
            parsed.length,
            "monitor(s)"
        )

        for (
            var i = 0;
            i < parsed.length;
            i++
        ) {
            var monitor =
                parsed[i]

            console.log(
                "[Battery Display Profiles] Monitor:",
                monitor.name,
                monitor.width +
                    "x" +
                    monitor.height,
                "@" +
                    monitor.refreshRate +
                    "Hz",
                "scale=" +
                    monitor.scale
            )

            if (
                Array.isArray(
                    monitor.availableModes
                )
            ) {
                console.log(
                    "[Battery Display Profiles] Available modes:",
                    monitor.availableModes.join(
                        ", "
                    )
                )
            }
        }
    }

    /*
     * ---------------------------------------------------------
     * Complete monitor discovery
     * ---------------------------------------------------------
     */

    function completeDiscovery() {
        if (
            pendingDiscoveryMonitors === null
        ) {
            var error =
                pendingDiscoveryError

            if (
                error === ""
            ) {
                error =
                    "No monitor data received"
            }

            console.warn(
                "[Battery Display Profiles] Discovery failed:",
                error
            )

            pendingDiscoveryError =
                ""

            if (pendingMonitorName !== "") {
                var failedMonitor = pendingMonitorName
                var failedMode = pendingMode
                pendingMonitorName = ""
                pendingMode = ""
                modeApplyFailed(
                    failedMonitor,
                    failedMode
                )
            }

            discoveryFailed(
                error
            )

            return
        }

        monitors =
            pendingDiscoveryMonitors

        pendingDiscoveryMonitors =
            null

        pendingDiscoveryError =
            ""

        console.log(
            "[Battery Display Profiles] Monitor discovery completed"
        )

        /*
         * If this discovery was triggered after applying a mode,
         * verify the target monitor's new mode before emitting
         * discoveryCompleted so listeners see the updated applied state.
         */
        if (pendingMonitorName !== "") {
            verifyAppliedMode()
        }

        /*
         * The Process has already exited at this point.
         *
         * It is now safe for listeners to start another
         * Process operation.
         */
        discoveryCompleted(
            monitors
        )
    }

    /*
     * ---------------------------------------------------------
     * Verify applied mode
     * ---------------------------------------------------------
     */

    function verifyAppliedMode() {
        var monitorName =
            pendingMonitorName

        var requestedMode =
            pendingMode

        var targetMonitor =
            findMonitor(
                monitorName
            )

        var actualMode =
            currentMode(
                targetMonitor
            )

        var verified =
            targetMonitor !== null &&
            modesEquivalent(
                actualMode,
                requestedMode
            )

        pendingMonitorName =
            ""

        pendingMode =
            ""

        if (verified) {
            console.log(
                "[Battery Display Profiles] Mode change verified:",
                monitorName,
                requestedMode
            )

            modeApplied(
                monitorName,
                requestedMode
            )

            return
        }

        console.warn(
            "[Battery Display Profiles] Mode change could not be verified:",
            "expected =",
            requestedMode,
            "actual =",
            actualMode
        )

        modeApplyFailed(
            monitorName,
            requestedMode
        )
    }

    /*
     * ---------------------------------------------------------
     * Process completion
     * ---------------------------------------------------------
     */

    function handleCommandExit(
        exitCode,
        exitStatus
    ) {
        var completedOperation =
            operation

        operation = ""

        console.log(
            "[Battery Display Profiles] hyprctl exited:",
            "operation =",
            completedOperation,
            "code =",
            exitCode,
            "status =",
            exitStatus
        )

        if (
            exitCode !== 0
        ) {
            var error =
                stderrCollector.text

            if (
                error.length === 0
            ) {
                error =
                    "hyprctl exited with code " +
                    exitCode
            }

            console.warn(
                "[Battery Display Profiles] hyprctl failed:",
                error
            )

            if (
                completedOperation ===
                "discover"
            ) {
                pendingDiscoveryMonitors =
                    null

                pendingDiscoveryError =
                    error

                completeDiscovery()

                return
            }

            if (
                completedOperation ===
                "apply"
            ) {
                var failedMonitor =
                    pendingMonitorName

                var failedMode =
                    pendingMode

                pendingMonitorName =
                    ""

                pendingMode =
                    ""

                modeApplyFailed(
                    failedMonitor,
                    failedMode
                )

                return
            }

            return
        }

        /*
         * Discovery completed successfully.
         *
         * This is intentionally the ONLY place where
         * discoveryCompleted is emitted.
         */
        if (
            completedOperation ===
            "discover"
        ) {
            completeDiscovery()

            return
        }

        /*
         * Mode application succeeded at the hyprctl
         * level. We now need a fresh monitor snapshot
         * before declaring success.
         */
        if (
            completedOperation ===
            "apply"
        ) {
            console.log(
                "[Battery Display Profiles] Mode command succeeded. Verifying..."
            )

            discoverMonitors()

            return
        }
    }

    /*
     * ---------------------------------------------------------
     * Hyprland process
     * ---------------------------------------------------------
     */

    Process {
        id: commandProcess

        stdout: StdioCollector {
            id: stdoutCollector

            onStreamFinished: {
                if (
                    root.operation ===
                    "discover"
                ) {
                    root.handleDiscoveryData(
                        text
                    )

                    return
                }

                if (
                    root.operation ===
                    "apply"
                ) {
                    console.log(
                        "[Battery Display Profiles] hyprctl eval output:",
                        text.trim()
                    )
                }
            }
        }

        stderr: StdioCollector {
            id: stderrCollector
        }

        onExited: function(
            exitCode,
            exitStatus
        ) {
            root.handleCommandExit(
                exitCode,
                exitStatus
            )
        }
    }

    Component.onCompleted: {
        root.discoverMonitors()
    }
}