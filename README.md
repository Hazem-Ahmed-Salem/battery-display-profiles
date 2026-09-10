# Battery Display Profiles

An Omarchy 4 service plugin that automatically switches a monitor's
display profile depending on whether the system is running on AC power
or battery.

## Status

Early development.

Currently implemented:

- Omarchy service plugin structure
- Quickshell UPower integration
- AC/battery state detection

Not implemented yet:

- Monitor discovery
- Display mode discovery
- Display profile configuration
- Automatic resolution/refresh-rate switching
- Configuration UI

## Development

This project targets current Omarchy 4 / Quickshell.

The plugin is designed to be event-driven and independent of:

- power-profiles-daemon
- powerprofilesctl
- systemd services
- dbus-monitor
- shell polling

Power state detection uses Quickshell's UPower integration.