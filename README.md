<p align="center">
  <video src="https://github.com/user-attachments/assets/6937f666-ba62-430c-b38c-98e399cd772b" controls width="100%"></video>
</p>

# Islands

`Islands` is a native Swift window manager for macOS. It lives in the menu bar, listens for global hotkeys, and moves the focused window the moment you press them — no animations, no overlays, no magic.

**Download:** [Latest release](https://github.com/JaimeOrtegaxyz/Islands/releases/latest)

## Requirements

- macOS 14 or newer.
- The current `v0.1.1` DMG is Apple Silicon only. Future release builds are universal for Apple Silicon and Intel Macs.
- Accessibility permission for window management.

## What it does

Press `Ctrl+Opt + ←/→/↑/↓` and the focused window snaps to that side of the screen. Press the same shortcut again and it cycles through more sizes anchored to that edge. Run out of sizes and the window overflows onto the monitor in that direction (above, below, left, right — whichever you've got).

That's the core. The rest are variations on it:

- **Reset** with `Ctrl+Opt+Return` — back to full screen.
- **Centered mode** (`Ctrl+Opt+Cmd + arrows`) keeps the window centered and grows or shrinks it from the middle instead of snapping to an edge.
- **Accordion stacking** — when two or more windows live in the same snap zone, they stack instead of fully overlapping. The window behind sticks out a few pixels so it stays discoverable. `Ctrl+Opt+Tab` rotates the stack forward, `Ctrl+Opt+Shift+Tab` rotates it backward.
- Horizontal and vertical axes are independent. Snap left half + top half = top-left quarter. Mix centered and edge modes per axis if you want. Just like that booty.

## Keybindings (defaults)

| Shortcut | What it does |
|---|---|
| `Ctrl+Opt + ←/→/↑/↓` | Cycle the focused window's size on that axis |
| `Ctrl+Opt+Return` | Reset to full screen |
| `Ctrl+Opt+Tab` | Cycle the accordion stack forward |
| `Ctrl+Opt+Shift+Tab` | Reverse stack (cycle backward) |
| `Ctrl+Opt+Cmd + ←/→/↑/↓` | Centered grow / shrink |

Every modifier above is reconfigurable in Settings.

## Snap sizes

Each press advances through a configured set of fractions. Default is **sixths** — the cycle steps through ⅙ → ⅓ → ½ → ⅔ → ⅚. You can switch the profile in Settings:

- **Quarters** — ¼, ½, ¾.
- **Sixths** — ⅙, ⅓, ½, ⅔, ⅚.
- **Quarters + Sixths** — both, combined into one denser cycle.

## Multi-monitor overflow

If you keep cycling past the smallest size on a side and there's a monitor in that direction, the window jumps over to it. Cycling back the other way brings it home. Works left/right and up/down.

## Accordion stacking

Inspired by Aerospace (minus the forced snapping). Drop two windows into the same snap zone and they stack — the back window peeks out by a few pixels so it stays visible. `Ctrl+Opt+Tab` rotates through them.

Peek size is configurable in Settings: **Small / Medium / Large**.

## Settings

Click the menu-bar icon → *Settings…* to:

- Re-record the **base modifier combo** — click the chip, press the new keys, release.
- Choose the extra modifiers for **centered mode** and **reverse stack**.
- Pick the **snap profile** (quarters / sixths / both).
- Adjust **peek size**.
- Toggle **Launch at login**.
- **Restore defaults** (leaves your launch-at-login setting untouched).

If Accessibility permission isn't granted yet, the same window also nudges you to System Settings — Islands picks up the permission the moment it's enabled.

## Install

Download the latest `.dmg` from [GitHub Releases](https://github.com/JaimeOrtegaxyz/Islands/releases/latest), open it, and drag `Islands.app` into Applications.

Grant Accessibility permission when prompted. Islands lives in the menu bar, not the Dock.

## Build from source

```bash
git clone https://github.com/JaimeOrtegaxyz/Islands ~/Documents/GitHub/Islands
cd ~/Documents/GitHub/Islands && make
open Islands.app
```

## How it works

Direct Accessibility API calls via `AXUIElement`. Carbon hotkeys for global keybindings. No animation or runtime overhead. Windows move instantly. As they should.

## License

MIT. See [LICENSE](LICENSE).
