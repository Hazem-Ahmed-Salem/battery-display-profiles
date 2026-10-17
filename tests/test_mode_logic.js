// Unit tests for DisplayController resolution preservation and auto-detection logic

const assert = require("assert");

function normalizeMode(mode) {
    if (typeof mode !== "string") return "";
    var result = mode.trim().replace(/Hz$/i, "");
    var parts = result.split("@");
    if (parts.length !== 2) return result;
    var refreshRate = Number(parts[1]);
    if (isNaN(refreshRate)) return result;
    return parts[0] + "@" + refreshRate;
}

function parseMode(mode) {
    var normalized = normalizeMode(mode);
    var parts = normalized.split("@");
    if (parts.length !== 2) return null;
    var resolution = parts[0].split("x");
    if (resolution.length !== 2) return null;
    var width = Number(resolution[0]);
    var height = Number(resolution[1]);
    var refreshRate = Number(parts[1]);
    if (isNaN(width) || isNaN(height) || isNaN(refreshRate)) return null;
    return { width, height, refreshRate };
}

function formatRefreshRate(rate) {
    var num = Number(rate);
    if (isNaN(num)) return "";
    if (Math.abs(num - Math.round(num)) < 0.005) {
        num = Math.round(num);
    } else {
        num = Number(num.toFixed(2));
    }
    return num + " Hz";
}

function modesEquivalent(firstMode, secondMode) {
    var first = parseMode(firstMode);
    var second = parseMode(secondMode);
    if (!first || !second) return false;
    if (first.width !== second.width || first.height !== second.height) {
        return false;
    }
    return Math.abs(first.refreshRate - second.refreshRate) < 0.01;
}

function currentMode(monitor) {
    if (!monitor) return "";
    if (Array.isArray(monitor.availableModes) && monitor.availableModes.length > 0) {
        var currentW = Number(monitor.width);
        var currentH = Number(monitor.height);
        var currentHz = Number(monitor.refreshRate);
        var bestMode = "";
        var bestDiff = 999999;

        for (var i = 0; i < monitor.availableModes.length; i++) {
            var p = parseMode(monitor.availableModes[i]);
            if (!p) continue;
            if ((p.width === currentW && p.height === currentH) ||
                (p.width === currentH && p.height === currentW)) {
                var diff = Math.abs(p.refreshRate - currentHz);
                if (diff < bestDiff) {
                    bestDiff = diff;
                    bestMode = normalizeMode(monitor.availableModes[i]);
                }
            }
        }
        if (bestMode !== "" && bestDiff < 0.5) {
            return bestMode;
        }
    }
    return normalizeMode(monitor.width + "x" + monitor.height + "@" + monitor.refreshRate);
}

function modesForCurrentResolution(monitor) {
    if (!monitor || !Array.isArray(monitor.availableModes) || monitor.availableModes.length === 0) return [];
    var currentW = Number(monitor.width);
    var currentH = Number(monitor.height);
    if (isNaN(currentW) || isNaN(currentH) || currentW <= 0 || currentH <= 0) return [];

    var matches = [];
    for (var i = 0; i < monitor.availableModes.length; i++) {
        var parsed = parseMode(monitor.availableModes[i]);
        if (!parsed) continue;
        if (parsed.width === currentW && parsed.height === currentH) {
            matches.push({
                raw: monitor.availableModes[i],
                normalized: normalizeMode(monitor.availableModes[i]),
                parsed: parsed
            });
        }
    }

    if (matches.length === 0) {
        for (var j = 0; j < monitor.availableModes.length; j++) {
            var parsedRot = parseMode(monitor.availableModes[j]);
            if (!parsedRot) continue;
            if (parsedRot.width === currentH && parsedRot.height === currentW) {
                matches.push({
                    raw: monitor.availableModes[j],
                    normalized: normalizeMode(monitor.availableModes[j]),
                    parsed: parsedRot
                });
            }
        }
    }

    matches.sort(function(a, b) {
        return b.parsed.refreshRate - a.parsed.refreshRate;
    });

    return matches;
}

function modeMatchesCurrentResolution(monitor, mode) {
    if (!monitor || typeof mode !== "string" || mode.trim() === "") return false;
    var parsed = parseMode(mode);
    if (!parsed) return false;
    var currentW = Number(monitor.width);
    var currentH = Number(monitor.height);
    if (isNaN(currentW) || isNaN(currentH)) return false;
    return (parsed.width === currentW && parsed.height === currentH) ||
           (parsed.width === currentH && parsed.height === currentW);
}

function highestMode(monitor) {
    if (!monitor) return "";
    var matches = modesForCurrentResolution(monitor);
    if (matches.length === 0) return currentMode(monitor);
    var best = matches[0];
    for (var i = 1; i < matches.length; i++) {
        if (matches[i].parsed.refreshRate > best.parsed.refreshRate) {
            best = matches[i];
        }
    }
    return best.normalized;
}

function lowestMode(monitor) {
    if (!monitor) return "";
    var matches = modesForCurrentResolution(monitor);
    if (matches.length === 0) return currentMode(monitor);
    var smoothModes = [];
    for (var i = 0; i < matches.length; i++) {
        if (matches[i].parsed.refreshRate >= 59.0) {
            smoothModes.push(matches[i]);
        }
    }
    var candidates = (smoothModes.length > 0) ? smoothModes : matches;
    var best = candidates[0];
    for (var j = 1; j < candidates.length; j++) {
        if (candidates[j].parsed.refreshRate < best.parsed.refreshRate) {
            best = candidates[j];
        }
    }
    return best.normalized;
}

function gcd(a, b) {
    var x = Math.abs(a);
    var y = Math.abs(b);
    while (y !== 0) {
        var t = y;
        y = x % y;
        x = t;
    }
    return x;
}

function aspectRatio(width, height) {
    var w = Number(width);
    var h = Number(height);
    if (isNaN(w) || isNaN(h) || w <= 0 || h <= 0) return "";

    var ratio = w / h;
    if (Math.abs(ratio - 16 / 9) < 0.02) return "16:9";
    if (Math.abs(ratio - 16 / 10) < 0.02) return "16:10";
    if (Math.abs(ratio - 4 / 3) < 0.02) return "4:3";
    if (Math.abs(ratio - 5 / 4) < 0.02) return "5:4";
    if (Math.abs(ratio - 21 / 9) < 0.05 || Math.abs(ratio - 64 / 27) < 0.05) return "21:9";
    if (Math.abs(ratio - 32 / 9) < 0.05) return "32:9";

    var d = gcd(w, h);
    var rw = w / d;
    var rh = h / d;
    if (rw < 50 && rh < 50) return rw + ":" + rh;
    return (Math.round(ratio * 10) / 10) + ":1";
}

function availableResolutions(monitor) {
    if (!monitor || !Array.isArray(monitor.availableModes) || monitor.availableModes.length === 0) {
        return [];
    }

    var currentW = Number(monitor.width);
    var currentH = Number(monitor.height);

    var map = {};
    for (var i = 0; i < monitor.availableModes.length; i++) {
        var rawMode = monitor.availableModes[i];
        var parsed = parseMode(rawMode);
        if (!parsed) continue;

        var key = parsed.width + "x" + parsed.height;
        if (!map[key]) {
            var isCurrent = (parsed.width === currentW && parsed.height === currentH) ||
                            (parsed.width === currentH && parsed.height === currentW);
            map[key] = {
                width: parsed.width,
                height: parsed.height,
                label: parsed.width + " × " + parsed.height,
                aspect: aspectRatio(parsed.width, parsed.height),
                pixelCount: parsed.width * parsed.height,
                isCurrent: isCurrent,
                refreshRates: [],
                modes: []
            };
        }

        var rateExists = false;
        for (var r = 0; r < map[key].refreshRates.length; r++) {
            if (Math.abs(map[key].refreshRates[r] - parsed.refreshRate) < 0.01) {
                rateExists = true
                break;
            }
        }
        if (!rateExists) {
            map[key].refreshRates.push(parsed.refreshRate);
        }
        map[key].modes.push(rawMode);
    }

    var list = [];
    for (var k in map) {
        if (map.hasOwnProperty(k)) {
            map[k].refreshRates.sort(function(a, b) { return b - a; });
            list.push(map[k]);
        }
    }

    list.sort(function(a, b) {
        if (b.pixelCount !== a.pixelCount) return b.pixelCount - a.pixelCount;
        return b.width - a.width;
    });

    return list;
}

function modesForResolution(monitor, width, height) {
    if (!monitor || !Array.isArray(monitor.availableModes)) return [];
    var targetW = Number(width);
    var targetH = Number(height);
    if (isNaN(targetW) || isNaN(targetH)) return [];

    var matches = [];
    for (var i = 0; i < monitor.availableModes.length; i++) {
        var parsed = parseMode(monitor.availableModes[i]);
        if (!parsed) continue;

        if ((parsed.width === targetW && parsed.height === targetH) ||
            (parsed.width === targetH && parsed.height === targetW)) {
            matches.push({
                raw: monitor.availableModes[i],
                normalized: normalizeMode(monitor.availableModes[i]),
                parsed: parsed
            });
        }
    }

    matches.sort(function(a, b) {
        return b.parsed.refreshRate - a.parsed.refreshRate;
    });

    return matches;
}

function highestModeForResolution(monitor, width, height) {
    if (!monitor) return "";
    var matches = modesForResolution(monitor, width, height);
    if (matches.length === 0) return currentMode(monitor);
    return matches[0].normalized;
}

function lowestModeForResolution(monitor, width, height) {
    if (!monitor) return "";
    var matches = modesForResolution(monitor, width, height);
    if (matches.length === 0) return currentMode(monitor);

    var smoothModes = [];
    for (var i = 0; i < matches.length; i++) {
        if (matches[i].parsed.refreshRate >= 59.0) {
            smoothModes.push(matches[i]);
        }
    }

    var candidates = (smoothModes.length > 0) ? smoothModes : matches;
    var best = candidates[0];
    for (var j = 1; j < candidates.length; j++) {
        if (candidates[j].parsed.refreshRate < best.parsed.refreshRate) {
            best = candidates[j];
        }
    }

    return best.normalized;
}

// -------------------------------------------------------------
// Tests
// -------------------------------------------------------------

console.log("==> Running DisplayController logic tests...");

// Test 1: Laptop internal display (2560x1600 @ 165Hz / 60Hz)
{
    const mon = {
        name: "eDP-1",
        width: 2560,
        height: 1600,
        refreshRate: 165.002,
        availableModes: ["2560x1600@165.00Hz", "2560x1600@60.00Hz"]
    };
    assert.strictEqual(highestMode(mon), "2560x1600@165", "AC mode must be 2560x1600@165");
    assert.strictEqual(lowestMode(mon), "2560x1600@60", "Battery mode must be 2560x1600@60");
    assert.strictEqual(modeMatchesCurrentResolution(mon, "2560x1600@165"), true);
    assert.strictEqual(modeMatchesCurrentResolution(mon, "1920x1080@60"), false);
    console.log("  ✓ Test 1: Laptop internal display passed");
}

// Test 2: External 4K display running at 1080p
{
    const mon = {
        name: "HDMI-A-1",
        width: 1920,
        height: 1080,
        refreshRate: 144.0,
        availableModes: [
            "3840x2160@144.00Hz",
            "3840x2160@60.00Hz",
            "2560x1440@144.00Hz",
            "1920x1080@144.00Hz",
            "1920x1080@120.00Hz",
            "1920x1080@60.00Hz",
            "640x480@60.00Hz"
        ]
    };
    assert.strictEqual(highestMode(mon), "1920x1080@144", "AC mode must not change to 4K");
    assert.strictEqual(lowestMode(mon), "1920x1080@60", "Battery mode must not change to 640x480");
    console.log("  ✓ Test 2: External multi-resolution display passed (resolution preserved)");
}

// Test 3: Rotated display (portrait 1080x1920)
{
    const mon = {
        name: "DP-2",
        width: 1080,
        height: 1920,
        refreshRate: 144.0,
        availableModes: [
            "1920x1080@144.00Hz",
            "1920x1080@60.00Hz",
            "640x480@60.00Hz"
        ]
    };
    assert.strictEqual(highestMode(mon), "1920x1080@144", "Rotated AC mode must match physical 1080p");
    assert.strictEqual(lowestMode(mon), "1920x1080@60", "Rotated Battery mode must match physical 1080p");
    assert.strictEqual(modeMatchesCurrentResolution(mon, "1920x1080@144"), true);
    console.log("  ✓ Test 3: Rotated display passed");
}

// Test 4: TV / HDMI display with 24Hz/30Hz/60Hz modes
{
    const mon = {
        name: "HDMI-A-2",
        width: 3840,
        height: 2160,
        refreshRate: 60.0,
        availableModes: [
            "3840x2160@60.00Hz",
            "3840x2160@50.00Hz",
            "3840x2160@30.00Hz",
            "3840x2160@24.00Hz"
        ]
    };
    assert.strictEqual(highestMode(mon), "3840x2160@60");
    assert.strictEqual(lowestMode(mon), "3840x2160@60", "Battery mode on TV must pick 60Hz instead of 24Hz slideshow");
    console.log("  ✓ Test 4: TV HDMI display avoided 24/30Hz");
}

// Test 5: Auto-detection multi-monitor reconciliation
{
    const liveMonitors = [
        {
            name: "eDP-1",
            width: 2560,
            height: 1600,
            refreshRate: 165.0,
            availableModes: ["2560x1600@165.00Hz", "2560x1600@60.00Hz"]
        },
        {
            name: "DP-1",
            width: 1920,
            height: 1080,
            refreshRate: 144.0,
            availableModes: ["1920x1080@144.00Hz", "1920x1080@60.00Hz"]
        }
    ];

    // Initial empty config
    const configured = [];

    // Reconcile
    for (const m of liveMonitors) {
        configured.push({
            name: m.name,
            enabled: true,
            acMode: highestMode(m),
            batteryMode: lowestMode(m)
        });
    }

    assert.strictEqual(configured.length, 2);
    assert.strictEqual(configured[0].name, "eDP-1");
    assert.strictEqual(configured[0].acMode, "2560x1600@165");
    assert.strictEqual(configured[0].batteryMode, "2560x1600@60");
    assert.strictEqual(configured[1].name, "DP-1");
    assert.strictEqual(configured[1].acMode, "1920x1080@144");
    assert.strictEqual(configured[1].batteryMode, "1920x1080@60");
    console.log("  ✓ Test 5: Auto-detection multi-monitor reconciliation passed");
}

// Test 6: Available resolutions grouping, aspect ratios, and sorting
{
    const mon = {
        name: "HDMI-A-5",
        width: 1920,
        height: 1080,
        refreshRate: 165.003,
        availableModes: [
            "1920x1080@60.00Hz",
            "3840x2160@59.94Hz",
            "3840x2160@29.97Hz",
            "1920x1080@165.00Hz",
            "1920x1080@143.98Hz",
            "1280x720@60.00Hz",
            "1280x720@50.00Hz",
            "2560x1600@60.00Hz"
        ]
    };

    const resList = availableResolutions(mon);
    assert.ok(resList.length >= 4, "Should have at least 4 unique resolutions");

    // Sorted descending by pixelCount
    assert.strictEqual(resList[0].width, 3840);
    assert.strictEqual(resList[0].height, 2160);
    assert.strictEqual(resList[0].aspect, "16:9");
    assert.strictEqual(resList[0].isCurrent, false);
    assert.strictEqual(resList[0].refreshRates.length, 2);

    assert.strictEqual(resList[1].width, 2560);
    assert.strictEqual(resList[1].height, 1600);
    assert.strictEqual(resList[1].aspect, "16:10");

    assert.strictEqual(resList[2].width, 1920);
    assert.strictEqual(resList[2].height, 1080);
    assert.strictEqual(resList[2].aspect, "16:9");
    assert.strictEqual(resList[2].isCurrent, true);
    assert.strictEqual(resList[2].refreshRates.length, 3);
    assert.strictEqual(Math.round(resList[2].refreshRates[0]), 165);

    console.log("  ✓ Test 6: Available resolutions grouping, aspect ratios, and sorting passed");
}

// Test 7: Resolution selection and profile adaptation
{
    const mon = {
        name: "HDMI-A-5",
        width: 1920,
        height: 1080,
        refreshRate: 165.003,
        availableModes: [
            "3840x2160@60.00Hz",
            "3840x2160@30.00Hz",
            "1920x1080@165.00Hz",
            "1920x1080@60.00Hz",
            "1280x720@120.00Hz",
            "1280x720@60.00Hz"
        ]
    };

    // Switch to 4K
    const ac4k = highestModeForResolution(mon, 3840, 2160);
    const bat4k = lowestModeForResolution(mon, 3840, 2160);
    assert.strictEqual(ac4k, "3840x2160@60");
    assert.strictEqual(bat4k, "3840x2160@60", "Must avoid 30Hz on battery for 4K");

    // Switch to 720p
    const ac720 = highestModeForResolution(mon, 1280, 720);
    const bat720 = lowestModeForResolution(mon, 1280, 720);
    assert.strictEqual(ac720, "1280x720@120");
    assert.strictEqual(bat720, "1280x720@60");

    console.log("  ✓ Test 7: Resolution selection and profile adaptation passed");
}

// Test 8: Unrounded refresh rates, 59.94Hz vs 60.00Hz separation, and sorting
{
    const mon = {
        name: "HDMI-A-5",
        width: 1920,
        height: 1080,
        refreshRate: 165.00301,
        availableModes: [
            "1920x1080@60.00Hz",
            "3840x2160@59.94Hz",
            "3840x2160@29.97Hz",
            "3840x2160@23.98Hz",
            "1920x1080@165.00Hz",
            "1920x1080@143.98Hz",
            "1920x1080@119.88Hz",
            "1920x1080@59.94Hz",
            "1920x1080@50.00Hz",
            "1920x1080@23.98Hz"
        ]
    };

    // 1. Current mode canonical resolution (maps 165.00301 to 165)
    assert.strictEqual(currentMode(mon), "1920x1080@165");

    // 2. Format refresh rate tests
    assert.strictEqual(formatRefreshRate(60), "60 Hz");
    assert.strictEqual(formatRefreshRate(59.94), "59.94 Hz");
    assert.strictEqual(formatRefreshRate(165), "165 Hz");
    assert.strictEqual(formatRefreshRate(165.00301), "165 Hz");
    assert.strictEqual(formatRefreshRate(143.98), "143.98 Hz");
    assert.strictEqual(formatRefreshRate(119.88), "119.88 Hz");
    assert.strictEqual(formatRefreshRate(23.98), "23.98 Hz");
    assert.strictEqual(formatRefreshRate(50), "50 Hz");

    // 3. Modes for current resolution must be sorted descending and include both 60 and 59.94
    const curModes = modesForCurrentResolution(mon);
    assert.strictEqual(curModes.length, 7);
    const formattedRates = curModes.map(m => formatRefreshRate(m.parsed.refreshRate));
    assert.deepStrictEqual(formattedRates, [
        "165 Hz",
        "143.98 Hz",
        "119.88 Hz",
        "60 Hz",
        "59.94 Hz",
        "50 Hz",
        "23.98 Hz"
    ]);

    // Ensure all formatted rates are distinct - no duplicate "60 Hz" pills!
    const uniqueFormatted = Array.from(new Set(formattedRates));
    assert.strictEqual(uniqueFormatted.length, formattedRates.length, "All refresh rate pill labels must be unique");

    // 4. Mode equivalence must strictly separate 60 from 59.94
    assert.strictEqual(modesEquivalent("1920x1080@60", "1920x1080@59.94"), false, "60Hz and 59.94Hz must not be equivalent");
    assert.strictEqual(modesEquivalent("1920x1080@144", "1920x1080@143.98"), false, "144Hz and 143.98Hz must not be equivalent");
    assert.strictEqual(modesEquivalent("1920x1080@24", "1920x1080@23.98"), false, "24Hz and 23.98Hz must not be equivalent");

    // But accommodate PLL clock jitter (~0.003)
    assert.strictEqual(modesEquivalent("1920x1080@165", "1920x1080@165.00301"), true);
    assert.strictEqual(modesEquivalent("1920x1080@165", "1920x1080@165.00200"), true);

    // 5. Switching to 59.94 maps correctly
    const mon59 = Object.assign({}, mon, { refreshRate: 59.94002 });
    assert.strictEqual(currentMode(mon59), "1920x1080@59.94");

    // 6. Available resolutions lists both 60 and 59.94
    const resList = availableResolutions(mon);
    const fhd = resList.find(r => r.width === 1920 && r.height === 1080);
    assert.ok(fhd, "1080p must be found");
    assert.strictEqual(fhd.refreshRates.length, 7);
    assert.ok(fhd.refreshRates.includes(60));
    assert.ok(fhd.refreshRates.includes(59.94));

    console.log("  ✓ Test 8: Unrounded refresh rates, 59.94Hz vs 60.00Hz separation, and sorting passed");
}

console.log("==> All tests passed successfully!");
