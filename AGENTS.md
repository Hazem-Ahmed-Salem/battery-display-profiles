# Battery Display Profiles — Agent Guidelines

## 1. Zero-Polling Requirement
- Do not implement polling loops, `while true` sleep commands, or periodic `Timer` elements for power-state or display detection.
- Rely solely on event-driven signals from `Quickshell.Services.UPower` (`UPower.onBattery`).

## 2. Hyprland Mode Switching & Safety
- Never execute `hyprctl keyword monitor ...` for dynamic mode switches, as this clobbers user transforms, scales, and positions.
- Always use the Hyprland Lua runtime mechanism:
  ```bash
  hyprctl eval 'hl.monitor({ output = "<name>", mode = "<res@hz>" })'
  ```
- Compare refresh rates using numeric tolerance (~0.1 Hz) to accommodate fractional values (e.g. `165.002Hz`).
- Verify successful switches with `hyprctl monitors -j` before updating internal caches.

## 3. Configuration & State Reactivity
- Persist settings via `omarchy bar set hazem.battery.display <key> <val>`. Do not rewrite `shell.json` directly from QML.
- Invalidate profile caches across both `(powerState, appliedMode)` so that profile modifications on the current power state trigger immediate application.

## 4. Live Verification Standard
- Always validate the plugin via `omarchy plugin validate .` and verify runtime behavior on the live system before marking tasks complete.
