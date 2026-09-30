# Battery Display Profiles

A native **Omarchy 4** plugin and bar widget that automatically manages display modes (resolution and refresh rate) based on power state across multiple monitors independently:

- **AC Power / Plugged In** ➔ `acMode` (e.g. high refresh rate like 165Hz)
- **Battery / Unplugged** ➔ `batteryMode` (e.g. power-saving rate like 60Hz)

Includes a headless automatic service controller, a status bar widget, an interactive profile editor, quick manual display controls, and independent multi-monitor management.

---

## Features

- **Independent Multi-Monitor Support**: Configure separate AC and battery profiles for every connected display (eDP, HDMI, DisplayPort). Changing one monitor never touches other monitors.
- **Strict Multi-Monitor Isolation**: Applies modes via Hyprland Lua runtime evaluation (`hyprctl eval 'hl.monitor({ output = "...", mode = "..." })'`) specifying only `output` and `mode`. Never modifies or resets monitor scaling, positions, transforms, VRR, workspaces, or reserved areas.
- **Event-Driven & Polling-Free**: Uses `Quickshell.Services.UPower.onBattery` for instantaneous power state detection without daemon polling loops, `dbus-monitor`, or background sleep timers.
- **Immediate Profile Application**: Watches `~/.config/omarchy/shell.json` for live changes. Modifying an AC profile while plugged in (or battery profile while unplugged) immediately applies the change without needing a power state transition.
- **Per-Monitor Applied State Tracking**: Tracks applied power state and mode per monitor (`appliedState[monitorName] = { powerState, mode }`), preventing redundant mode changes while ensuring immediate re-evaluation on profile edits.
- **Safe Handling for Disconnected & Disabled Displays**: Disconnected configured monitors are safely preserved in configuration and skipped without error loops. Displays can be toggled on/off individually.
- **Invalid Mode Protection**: Validates requested modes against discovered hardware capabilities before execution. Unavailable modes are rejected safely, leaving the display intact.
- **Automatic Legacy Migration**: Seamlessly upgrades legacy single-monitor configurations (`monitor`, `acMode`, `batteryMode`) to the multi-monitor `monitors` array format without data loss.
- **Native Quattro Bar Widget**: Built with native Omarchy styling:
  - Multi-monitor tab chips with connection dots (`●`) and disabled status indicators.
  - Active monitor card with connection badge, enable/disable toggle, and remove button.
  - Quick refresh rate buttons for instant manual overrides.
  - AC and Battery Profile cards with interactive mode pickers.
  - "Add Monitor" view to easily configure newly connected displays.

---

## Architecture

```text
Quickshell UPower.onBattery
             │
             ▼
        Service.qml  ◄────── shell.json (FileView watcher)
             │
             ├── Independent per-monitor queue
             ▼
    DisplayController.qml
             │
             ├── hyprctl eval 'hl.monitor({ output = "...", mode = "..." })'
             ▼
    Hyprland Compositor
             │
             ▼
     Mode Verified via rediscovery
```

- **`Service.qml`**: Headless singleton service managing lifecycle, configuration loading and migration, UPower reactivity, per-monitor applied state caching, and sequential mode execution queue.
- **`DisplayController.qml`**: Interacts with Hyprland (`hyprctl monitors -j` and `hyprctl eval`), normalizes and compares modes with numeric tolerance, validates available display modes, and verifies applied modes.
- **`BarWidget.qml`**: The Omarchy bar UI surface allowing quick manual overrides, monitor selection, enabling/disabling, adding/removing displays, and persisting profile settings via canonical Omarchy commands.

---

## Requirements

- **Omarchy 4 (Quattro)**
- **Arch Linux**
- **Hyprland**
- **Quickshell**
- **UPower**

*Does not require or depend on `power-profiles-daemon`, `powerprofilesctl`, `dbus-monitor`, or custom systemd services.*

---

## Installation

### 1. Via Omarchy Plugin Manager

```bash
omarchy plugin add https://github.com/Hazem-Ahmed-Salem/battery-display-profiles.git --enable
```

### 2. Manual Installation / Development

Clone or link the repository into your Omarchy plugins directory:

```bash
mkdir -p ~/.config/omarchy/plugins
git clone https://github.com/Hazem-Ahmed-Salem/battery-display-profiles.git ~/.config/omarchy/plugins/battery-display-profiles
```

Force plugin discovery in the Omarchy shell:

```bash
omarchy-shell shell rescanPlugins
```

Enable the plugin on your bar:

```bash
omarchy plugin enable battery-display-profiles --section right
```

---

## Configuration

Settings are stored in `~/.config/omarchy/shell.json` within your bar layout:

```json
{
  "id": "battery-display-profiles",
  "monitors": [
    {
      "name": "eDP-1",
      "enabled": true,
      "acMode": "2560x1600@165",
      "batteryMode": "2560x1600@60"
    },
    {
      "name": "HDMI-A-5",
      "enabled": true,
      "acMode": "1920x1080@165",
      "batteryMode": "1920x1080@60"
    }
  ]
}
```

### Monitor Schema

Each item in the `monitors` array supports the following properties:

| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `name` | `string` | *(required)* | Display monitor identifier (e.g. `eDP-1`, `HDMI-A-5`). |
| `enabled` | `boolean` | `true` | Whether automatic switching is enabled for this monitor. |
| `acMode` | `string` | *(highest mode)* | Desired resolution and refresh rate when plugged in. |
| `batteryMode` | `string` | *(lowest mode)* | Desired resolution and refresh rate when on battery power. |

### Backward-Compatible Migration

If your `shell.json` contains a legacy single-monitor configuration:

```json
{
  "id": "battery-display-profiles",
  "monitor": "eDP-1",
  "acMode": "2560x1600@165",
  "batteryMode": "2560x1600@60"
}
```

The plugin automatically detects and migrates it on startup into:

```json
{
  "id": "battery-display-profiles",
  "monitors": [
    {
      "name": "eDP-1",
      "enabled": true,
      "acMode": "2560x1600@165",
      "batteryMode": "2560x1600@60"
    }
  ],
  "monitor": "eDP-1",
  "acMode": "2560x1600@165",
  "batteryMode": "2560x1600@60"
}
```

Legacy fields are preserved for full backward compatibility.

---

## Bar Widget Usage

Click the display icon in the bar to open the popup control surface:

1. **Monitor Tabs**: Switch between configured monitors. Green dots indicate connected displays; grey dots indicate disconnected displays; `(off)` indicates disabled monitors.
2. **Enable / Disable Toggle**: Click **Disable** or **Enable** to pause or resume automatic switching for the active monitor without deleting its profile.
3. **Quick Refresh Rate**: Buttons under "Quick Refresh Rate" allow one-click manual mode changes to any supported refresh rate at the current resolution.
4. **AC & Battery Profile Pickers**: Click **Change** next to either profile to display the list of available modes. Selecting a mode updates the configuration and immediately applies it if you are currently on that power source.
5. **Add Monitor**: If an unconfigured display is connected, an "Add Monitor" chip appears in the tab row. Clicking it allows adding the display with auto-detected high (AC) and low (Battery) refresh rates.
6. **Remove Monitor**: Click the trash icon in the monitor header to remove a display from managed profiles.

---

## Troubleshooting & Verification

### Verify Display State in Hyprland

Check the active resolution and refresh rate for all monitors:

```bash
hyprctl monitors
```

Or format as JSON:

```bash
hyprctl monitors -j | jq '.[] | {name, width, height, refreshRate}'
```

### Inspect Live Logs

Logs use the `[Battery Display Profiles]` prefix:

```bash
journalctl --user -u omarchy-shell -f | grep "\[Battery Display Profiles\]"
```

Or via Quickshell:

```bash
quickshell log | grep "\[Battery Display Profiles\]"
```

Key diagnostic events logged:
- `Configuration loaded with X monitor(s)`
- `Profile applied successfully: <monitor> <mode>`
- `Mode change verified: <monitor> <mode>`
- `Refusing unavailable mode for <monitor>: <mode>`
- `Configured monitor is disconnected (skipped safely): <monitor>`

### Validate Plugin Structure

Run the Omarchy plugin validator:

```bash
omarchy plugin validate ~/Side\ Projects/battery-display-profiles
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.