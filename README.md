# LookAway

**Your screen softens when you look away.** LookAway uses the head-tracking
motion sensors in your AirPods and blurs/dims the display when you turn your
head past a comfort zone — and clears it the moment you look back.

It's the Linux/Omarchy answer to [ShyGlass](https://shyglass.app/), built as a
native [Omarchy](https://omarchy.org/) shell plugin for Quickshell + Hyprland.
Unlike the macOS original it never captures your screen: Hyprland blurs the
backdrop of a passive, click-through layer surface, so nothing is ever read off
the framebuffer. The compositor may still include that layer in screen shares
and recordings; see the caveat below.

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

No screen-recording permission, no screenshotting, no cloud, and no Python
packages beyond the standard library.

## Requirements

- Omarchy Quattro (Quickshell shell + Hyprland), with a Bluetooth Classic
  adapter and the BlueZ daemon available to the logged-in user.
- `bluetoothctl` and raw Bluetooth L2CAP support (both part of a normal
  Omarchy install).
- AirPods with head tracking. **AirPods Pro 2 is the only tested target.**
  Other AirPods models may use the same protocol, but their firmware and packet
  variants are not guaranteed.
- `python3` (preinstalled on Omarchy).

## Install

```bash
omarchy plugin add https://github.com/artemisa81/lookaway.git --enable
```

Plugins execute unsandboxed code inside the long-lived Omarchy shell. Review the
source or pin the cloned checkout to a reviewed commit before enabling it when
that matters to your threat model. `omarchy plugin add` currently clones the
repository's default branch rather than accepting a commit pin.

Then install the Hyprland layer rule (plugins cannot edit compositor config):

```bash
~/.config/omarchy/plugins/io.github.artemisa81.lookaway/bin/lookaway-hypr install
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

The rule enables Hyprland's global blur engine and applies blur to the
LookAway layer only. This adds some compositor work while the shield is
visible; disable `blur.enabled` in the rule if that tradeoff is not wanted.

Put your AirPods in and wait for the bar icon to stop showing `!`. Turn your
head away — the icon becomes solid and the display should soften.

### Development

```bash
ln -sfn "$PWD" ~/.config/omarchy/plugins/io.github.artemisa81.lookaway
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.artemisa81.lookaway
```

Saving a file under the plugin directory refreshes the catalog. Run
`omarchy restart shell` after changing `Service.qml` or process lifecycle code
so the long-lived service instance definitely loads the new source.

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
  lookaway failsafe on       # cover after a live sensor session is lost
  lookaway hysteresis 2      # release margin near the comfort threshold
  lookaway smoothing 140     # visual fade duration in milliseconds
  lookaway demo on           # synthetic sweep, no AirPods needed
  lookaway test 25           # force a fixed offset angle for preview
  ```
- **IPC**: `omarchy-shell lookaway <status|enable|disable|toggle|recenter|demo|comfort|full|failsafe|hysteresis|smoothing|test>`

## Settings

Editable from the bar widget's settings panel (stored in `shell.json`):

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Master switch |
| `comfortDeg` | `15` | Movement inside this cone is ignored |
| `fullCoverDeg` | `33` | Angle at which the screen is fully covered |
| `dimStrength` | `0.92` | Maximum scrim opacity |
| `failSafe` | `false` | After a live session, cover instead of opening the screen when sensor data is lost |
| `hysteresisDeg` | `2` | Release margin below the comfort threshold; higher is steadier, `0` is most sensitive |
| `smoothingMs` | `140` | Visual fade duration; lower is faster, higher is calmer |
| `demo` | `false` | Run the synthetic feed instead of live AirPods |
| `mac` | `""` | Pin an AirPods MAC (else auto-detected by name) |
| `startVariant` | `auto` | Head-tracking start packet: `auto`, `alt`, or `def` |

For a more sensitive shield, lower `comfortDeg` (it engages sooner) and/or
lower `fullCoverDeg` (it reaches full cover sooner). If the icon flickers near
the boundary, increase `hysteresisDeg`; if the visual transition feels slow,
lower `smoothingMs`.

## Credits

The AAP packet layout, the head-tracking start packets, and the orientation
math are derived from the reverse-engineering work of:

- **[LibrePods](https://github.com/kavishdevar/librepods)** (@kavishdevar) —
  `HeadOrientation.kt`, the source of the yaw/pitch/roll math.
- **[pods-head-tracker](https://github.com/batubozkan/pods-head-tracker)** —
  the Linux L2CAP/BlueZ implementation this helper is modeled on.

Exact source revisions, file-level attribution, and license provenance are in
`NOTICE`.

Because it derives from LibrePods, LookAway is licensed **GPL-3.0-or-later**
(see `LICENSE`).

## Caveats

- Only one process can own the AirPods AACP channel at a time. LookAway will
  conflict with other AirPods daemons (e.g. `airpods-helper`, LibrePods).
- The scrim appears in screen shares/recordings by default. Uncomment
  `no_screen_share = true` in `hypr/lookaway.lua` to keep it local-only. This
  means remote viewers will see the unobscured screen, so use that option only
  when remote privacy is not required.
- `failSafe` defaults to `false` so a fresh install does not block the desktop
  before AirPods have ever connected. Enable it when the screen must stay
  covered after an active sensor session is lost.
- The scrim is a privacy aid, not a security boundary. Bluetooth, firmware,
  compositor, and screen-share behavior can all affect the result.
- Head tracking is gated by the buds' firmware; results vary by model and
  firmware. The `startVariant` setting exists for that reason.
- `AirPods` is a trademark of Apple Inc. This project is unaffiliated with and
  not endorsed by Apple.

## Uninstall

```bash
~/.config/omarchy/plugins/io.github.artemisa81.lookaway/bin/lookaway-hypr uninstall
# Drop the require("hypr.lookaway") line from ~/.config/hypr/hyprland.lua.
omarchy plugin remove io.github.artemisa81.lookaway
hyprctl reload
```

The helper refuses to overwrite or remove an unmarked Hyprland file and keeps
a backup when replacing or uninstalling the managed rule.
