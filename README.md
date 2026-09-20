# LookAway

**Your screen softens when you look away.** LookAway uses the head-tracking
motion sensors in your AirPods and blurs/dims the display when you turn your
head past a comfort zone — and clears it the moment you look back.

It's the Linux/Omarchy answer to [ShyGlass](https://shyglass.app/), built as a
native [Omarchy](https://omarchy.org/) shell plugin for Quickshell + Hyprland.
Unlike the macOS original it never captures your screen: Hyprland blurs the
backdrop of a passive, click-through layer surface, so nothing is ever read off
the framebuffer.

## How it works

1. A background helper opens the AirPods' Apple Accessory Protocol (AAP)
   channel over Bluetooth L2CAP (PSM `0x1001`), performs the handshake, and
   asks the buds to start streaming their fused orientation (AAP opcode `0x17`).
2. It calibrates a neutral "facing the screen" pose from the first still
   samples, then decodes yaw/pitch/roll relative to that pose.
3. The plugin turns the angular distance from center into a `cover` value:
   `0` inside the comfort zone, ramping to `1` at the full-cover angle.
4. A per-output, focus-less, click-through layer surface (`lookaway-scrim`)
   fades in a directional gradient plus a full scrim. Hyprland's `blur` layer
   rule softens the screen behind it.

No screen recording permission, no screenshotting, no cloud.

## Requirements

- Omarchy Quattro (Quickshell shell + Hyprland)
- AirPods with head tracking: AirPods Pro (any gen), AirPods 3rd gen+, AirPods
  Max. **AirPods Pro 2 is the tested target.**
- AirPods paired and connected over Bluetooth (BlueZ / `bluetoothctl`)
- `python3` (preinstalled on Omarchy)

## Install

```bash
omarchy plugin add https://github.com/artemisa81/lookaway.git --enable
```

Then install the Hyprland layer rule (plugins can't edit compositor config):

```bash
cp ~/.config/omarchy/plugins/io.github.artemisa81.lookaway/hypr/lookaway.lua ~/.config/hypr/
```

Add this line to `~/.config/hypr/hyprland.lua` alongside the other user
`require`s:

```lua
require("hypr.lookaway")
```

Apply it:

```bash
hyprctl reload && hyprctl configerrors
```

Put your AirPods in. Look at the screen until the bar icon turns solid, then
turn your head away — the display should soften.

### Development

```bash
ln -sfn "$PWD" ~/.config/omarchy/plugins/io.github.artemisa81.lookaway
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.artemisa81.lookaway
```

Saving a file under the plugin directory hot-reloads the QML. Service code
changes may need `omarchy restart shell`.

## Usage

- **Bar widget** — left-click toggles the shield, right-click re-centers.
- **CLI** (`bin/lookaway`) — optionally put it on `PATH` first:

  ```bash
  ln -sfn ~/.config/omarchy/plugins/io.github.artemisa81.lookaway/bin/lookaway ~/.local/bin/lookaway
  ```

  ```bash
  lookaway status            # JSON state
  lookaway toggle            # enable/disable
  lookaway recenter          # treat the current pose as "screen ahead"
  lookaway comfort 12        # comfort-zone angle (2–30°)
  lookaway full 28           # full-cover angle (comfort+1..60°)
  lookaway demo on           # synthetic sweep, no AirPods needed
  lookaway test 25           # force a fixed offset angle for preview
  ```
- **IPC**: `omarchy-shell lookaway <status|enable|disable|toggle|recenter|demo|comfort|full|test>`

## Settings

Editable from the bar widget's settings panel (stored in `shell.json`):

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Master switch |
| `comfortDeg` | `15` | Movement inside this cone is ignored |
| `fullCoverDeg` | `33` | Angle at which the screen is fully covered |
| `dimStrength` | `0.92` | Maximum scrim opacity |
| `demo` | `false` | Run the synthetic feed instead of live AirPods |
| `mac` | `""` | Pin an AirPods MAC (else auto-detected by name) |
| `startVariant` | `auto` | Head-tracking start packet: `auto`, `alt`, or `def` |

## Credits

The AAP packet layout, the head-tracking start packets, and the orientation
math are derived from the reverse-engineering work of:

- **[LibrePods](https://github.com/kavishdevar/librepods)** (@kavishdevar) —
  `HeadOrientation.kt`, the source of the yaw/pitch/roll math.
- **[pods-head-tracker](https://github.com/batubozkan/pods-head-tracker)** —
  the Linux L2CAP/BlueZ implementation this helper is modeled on.
- `librepods-rs`, `AirPods`, and the broader AAP reverse-engineering community.

Because it derives from LibrePods, LookAway is licensed **GPL-3.0-or-later**
(see `LICENSE`).

## Caveats

- Only one process can own the AirPods AACP channel at a time. LookAway will
  conflict with other AirPods daemons (e.g. `airpods-helper`, LibrePods).
- The scrim appears in screen shares/recordings by default. Uncomment
  `no_screen_share = true` in `hypr/lookaway.lua` to keep it local-only.
- Head tracking is gated by the buds' firmware; results vary by model and
  firmware. The `startVariant` setting exists for that reason.
- `AirPods` is a trademark of Apple Inc. This project is unaffiliated with and
  not endorsed by Apple.

## Uninstall

```bash
omarchy plugin remove io.github.artemisa81.lookaway
rm ~/.config/hypr/lookaway.lua   # and drop the require("hypr.lookaway") line
hyprctl reload
```
