# Battery Display Profiles

A native **Omarchy 4** plugin and bar widget that automatically switches your monitor's display mode (resolution and refresh rate) based on power state:

- **AC Power / Plugged In** ➔ `acMode` (e.g. high refresh rate like 165Hz)
- **Battery / Unplugged** ➔ `batteryMode` (e.g. power-saving rate like 60Hz)

Includes a headless automatic service controller, a status bar widget, an interactive profile editor, and quick manual display mode controls.

---

## Features

- **Event-Driven & Polling-Free**: Uses `Quickshell.Services.UPower.onBattery` for instantaneous power state detection without daemon polling loops or background sleep timers.
- **Safe Hyprland Lua Integration**: Utilizes the canonical Hyprland runtime evaluation (`hyprctl eval 'hl.monitor({ output = "...", mode = "..." })'`) to update only the targeted output and mode. Never touches scaling, positions, workspaces, VRR, or unrelated monitors.
- **Robust Mode Normalization**: Smart comparison with numeric refresh rate tolerance (handles differences like `165.002Hz` vs `165.00Hz` or `165`).
- **Live Configuration Watching**: Watches `~/.config/omarchy/shell.json` for live changes. Modifying a profile while currently on that power state immediately applies the new mode without requiring an AC/battery power transition.
- **Post-Switch Verification**: Automatically queries Hyprland to verify the mode was applied successfully before updating cached state.
- **Native Bar Widget**: Shows current output, active mode, quick manual refresh rate toggling, and an interactive profile editor to select modes with a single click.

---

## Architecture

```text
Quickshell UPower.onBattery
             │
             ▼
        Service.qml  ◄────── shell.json (FileView watcher)
             │
             ▼
   DisplayController.qml
             │
             ▼
         Hyprland (hl.monitor runtime eval)
             │
             ▼
    Target Monitor Mode Verified
```

- **`Service.qml`**: Headless singleton service managing lifecycle, configuration loading, UPower reactivity, and mode switching logic.
- **`DisplayController.qml`**: Interacts with Hyprland (`hyprctl monitors -j` and `hyprctl eval`), normalizes and compares modes, validates available display modes, and verifies applied modes.
- **`BarWidget.qml`**: The Omarchy bar UI surface allowing quick manual overrides, monitor selection, and persisting profile settings via canonical Omarchy commands.

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
  "monitor": "eDP-1",
  "acMode": "2560x1600@165",
  "batteryMode": "2560x1600@60"
}
```

### Configuration Options

| Option | Type | Description |
| :--- | :--- | :--- |
| `monitor` | `string` | Display monitor identifier (e.g. `eDP-1`, `HDMI-A-1`). |
| `acMode` | `string` | Desired resolution and refresh rate when plugged in. |
| `batteryMode` | `string` | Desired resolution and refresh rate when on battery power. |

### CLI Configuration

You can configure options from the terminal at any time using the canonical Omarchy command:

```bash
omarchy bar set battery-display-profiles monitor "eDP-1"
omarchy bar set battery-display-profiles acMode "2560x1600@165"
omarchy bar set battery-display-profiles batteryMode "2560x1600@60"
```

---

## Troubleshooting & Verification

### Verify Display State in Hyprland

Check the active resolution and refresh rate for your monitors:

```bash
hyprctl monitors
```

### Monitor Plugin Logs

Logs from the plugin use the `[Battery Display Profiles]` prefix. View live Quickshell logs:

```bash
quickshell log | grep "\[Battery Display Profiles\]"
```

Key diagnostic events logged:
- Service startup and initial power state
- Active configuration loading and monitor validation
- Power state transitions (`onBattery = true / false`)
- Mode switching commands and Hyprland verification results

---

## License

MIT License. See [LICENSE](LICENSE) for details.