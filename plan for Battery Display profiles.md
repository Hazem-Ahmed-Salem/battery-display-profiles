# Battery Display Profiles — Codex Build Plan

## Goal

Build a public, generic **Omarchy 4 plugin** that automatically changes a selected monitor's display mode according to power state:

- AC / plugged in -> `acMode`
- Battery / unplugged -> `batteryMode`

Each profile contains a resolution and refresh rate.

Development example only:

- Monitor: `eDP-1`
- AC: `2560x1600@165`
- Battery: `2560x1600@60`

Never hardcode those values in production.

## Environment

Target:

- Omarchy 4
- Arch Linux
- Hyprland
- Quickshell
- UPower
- optional auto-cpufreq

Do not depend on:

- power-profiles-daemon
- powerprofilesctl
- dbus-monitor
- systemd services
- shell polling loops
- continuous polling

Power detection must use:

```qml
import Quickshell.Services.UPower
UPower.onBattery
```

## Architecture

```text
UPower.onBattery
       |
       v
 Service.qml
       |
       v
DisplayController.qml
       |
       v
   Hyprland
       |
       v
selected monitor + selected mode
```

The service is the headless automatic controller. The bar widget is only the UI/control surface.

## Repository

Keep the project simple:

```text
battery-display-profiles/
├── manifest.json
├── Service.qml
├── DisplayController.qml
├── BarWidget.qml
├── README.md
├── LICENSE
└── plan.md
```

Only add files when there is a real architectural reason.

## Omarchy plugin

Use the current Omarchy 4 third-party plugin architecture.

Manifest must define the required schema fields and expose:

- `service`
- `bar-widget`

Use a non-reserved public namespace when preparing the final marketplace version.

## Configuration

Current configuration is stored in:

```text
~/.config/omarchy/shell.json
```

The plugin entry contains:

```json
{
  "id": "battery-display-profiles",
  "monitor": "eDP-1",
  "acMode": "2560x1600@165",
  "batteryMode": "2560x1600@60"
}
```

Required settings:

- `monitor`
- `acMode`
- `batteryMode`

Read and validate the active plugin entry. Never directly rewrite `shell.json` from the widget.

## Configuration changes

Configuration changes are first-class events.

When `shell.json` changes:

```text
shell.json changed
      |
      v
reload configuration
      |
      v
detect relevant plugin changes
      |
      v
invalidate previous applied-profile state
      |
      v
rediscover monitor state
      |
      v
select profile for CURRENT power state
      |
      v
validate
      |
      v
apply if necessary
```

Changing a profile while already on that power state must immediately take effect.

For example:

```text
Already on battery
Battery: 60 Hz -> 165 Hz
```

must change the display without unplugging/replugging.

Do not use only `lastAppliedPowerState` as the cache key. Track the applied mode too, e.g.:

```text
lastAppliedPowerState
lastAppliedMode
```

A mode change must invalidate the previous applied state even if the power state is unchanged.

## Power semantics

The semantic contract is:

```text
UPower.onBattery == true
    -> battery profile

UPower.onBattery == false
    -> AC profile
```

Do not invert this mapping merely because a display result looks reversed.

Log enough information to diagnose it:

```text
onBattery = ...
selected profile = ...
selected mode = ...
```

If physical behavior contradicts the semantic contract, investigate the actual UPower event and configuration values before changing the mapping.

## Service.qml

Responsible for:

- lifecycle
- configuration loading
- configuration watching
- UPower state
- AC/battery selection
- monitor discovery coordination
- validation
- applying profiles
- success/failure handling

Apply profiles only on relevant events:

1. startup
2. power-state change
3. relevant configuration change
4. monitor availability/discovery
5. explicit manual action

No polling.

## DisplayController.qml

Responsible for:

- monitor discovery
- parsing `hyprctl monitors -j`
- finding the configured monitor
- available modes
- mode normalization
- mode comparison
- validation
- applying modes
- verification
- error handling

Use the current Hyprland Lua runtime mechanism:

```bash
hyprctl eval 'hl.monitor({
    output = "...",
    mode = "..."
})'
```

Do not use:

```bash
hyprctl keyword monitor ...
```

The runtime command should only modify:

- `output`
- `mode`

Never send position, scale, transform, VRR, workspace, reserved-area, or unrelated-monitor settings.

## Monitor safety

Before applying:

1. Confirm configured monitor exists.
2. Confirm requested mode is available.
3. Normalize refresh-rate representation.
4. Reject malformed/unavailable modes.
5. Apply only the requested mode.

If the monitor is unavailable, log and leave the current display state unchanged.

## Mode handling

Treat equivalent representations such as:

```text
2560x1600@165
2560x1600@165.00Hz
```

as equivalent when appropriate.

Use a small numeric refresh-rate tolerance rather than exact floating-point string equality.

After applying:

```text
validate
  -> apply
  -> check command result
  -> rediscover
  -> verify actual mode
```

Only mark the profile as applied after successful verification.

If Hyprland fails, do not update the applied-state cache.

## BarWidget.qml

The widget should:

- show selected monitor
- show current mode
- list available modes
- allow manual mode selection
- show AC profile
- show Battery profile
- edit both profiles
- persist profile changes
- reflect saved configuration

Persist through the canonical command:

```bash
omarchy bar set battery-display-profiles <key> <value>
```

Do not make the widget the source of truth for automatic switching.

Keep the current Omarchy-native visual design; avoid unnecessary redesign.

## Logging

Use:

```text
[Battery Display Profiles]
```

Useful events:

- service startup
- initial `onBattery`
- configuration loaded
- monitor
- AC mode
- Battery mode
- power-state changes
- selected profile/mode
- monitor discovery
- mode validation
- application
- Hyprland result
- verification
- invalid configuration
- unavailable monitor/mode

Avoid continuous log spam.

## Git

Use small commits, for example:

```text
feat: add Omarchy service plugin
feat: add monitor discovery
feat: add safe Hyprland mode switching
feat: add power profile selection
feat: watch configuration changes
feat: persist display profiles
feat: add display profile UI
test: add regression coverage
docs: add installation and troubleshooting
```

Do not mix unrelated refactors into functional commits.

## Completion criteria

Do not call the project complete until all testing below passes:

- manifest validates
- service starts
- UPower events work
- AC switching works
- Battery switching works
- profile changes work while remaining on the same power state
- invalid modes are rejected safely
- invalid monitor is safe
- unrelated monitors remain untouched
- restart behavior works
- no polling exists
- widget persistence works
- service and widget agree on configuration
- README documents installation/configuration/troubleshooting

Actual display state must be verified with:

```bash
hyprctl monitors
```

and power transitions must be verified through UPower/service logs.
