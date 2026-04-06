<p align="center">
  <img src="islands.webp" alt="Islands logo" width="600" />
</p>

# Islands

`Islands` is a native Swift window manager for macOS.

Keybindings tile windows across a multi-position spectrum per axis. Hit it again, it cycles. Overflow sends the window to the next monitor.

## Keybindings defaults

| Shortcut | What it does |
|---|---|
| `Ctrl+Opt+←` | Cycle left (¾ → ½ → ¼ → overflow to next monitor) |
| `Ctrl+Opt+→` | Cycle right |
| `Ctrl+Opt+↑` | Cycle up |
| `Ctrl+Opt+↓` | Cycle down |
| `Ctrl+Opt+Return` | Reset to full screen |
| `Ctrl+Opt+Tab` | Cycle accordion stack forward |
| `Ctrl+Opt+Shift+Tab` | Cycle accordion stack backward |
| `Ctrl+Opt+Cmd+←` | Center horizontally (shrink) |
| `Ctrl+Opt+Cmd+→` | Center horizontally (grow) |
| `Ctrl+Opt+Cmd+↑` | Center vertically (shrink) |
| `Ctrl+Opt+Cmd+↓` | Center vertically (grow) |

Horizontal and vertical axes are independent. Tile left half + top half and you get the top-left quarter. Centered mode and edge-snap mode are also independent per axis — mix them, shake them. Just like that booty.

## Accordion stacking

Inspired by Aerospace (minus the forced snapping). Put two windows in the same zone and they stack. The back window peeks out so you know it's there. `Ctrl+Opt+Tab` rotates the stack.

## Install

```bash
git clone https://github.com/JaimeOrtegaxyz/Islands ~/Documents/GitHub/Islands
cd ~/Documents/GitHub/Islands && make
open Islands.app
```

Grant Accessibility permission when prompted. Lives in the menu bar, not the Dock.

## How it works

Direct Accessibility API calls via `AXUIElement`. Carbon hotkeys for global keybindings. No animation or runtime overhead. Windows move instantly. As they should.
