# Battery Guard for Omarchy

Reminders that keep your battery between 20% and 80%, for laptops whose firmware can't limit charging (HP Victus/Omen and others with no `charge_control_end_threshold`).

- **Daily mode:** a notification to unplug at 80% and to plug in at 20%. It repeats every few minutes until you act.
- **Travel mode:** no unplug reminder. You get one notice when the battery reaches 100%, and the plug-in reminder still works.
- The panel shows battery size, charge cycles, time left or time to full, and the power draw (light yellow while discharging, green while charging). It also has the power profile picker.
- The percentage can be shown next to the icon. Settings are saved in `~/.config/omarchy/shell.json`.

## Install

```bash
omarchy plugin add https://github.com/T3mon/omarchy-battery-guard.git --enable
```

## Use

- Left click the battery icon to open the panel.
- Right click it to switch between Daily and Travel.
- The unplug notification has a **Travel mode** button. The 100% notification has a **Back to Daily** button.

Keybinding (optional, `~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + ALT + B", "Battery travel mode", "omarchy-shell t3mon.battery-guard toggleTravel")
```

IPC: `omarchy-shell t3mon.battery-guard <open|close|toggle|travelOn|travelOff|toggleTravel|togglePercentage|status>`

## Tests

```bash
node tests/model.test.js
```

## License

MIT
