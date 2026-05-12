<p align="center">
  <video src="https://github.com/user-attachments/assets/6937f666-ba62-430c-b38c-98e399cd772b" controls width="100%"></video>
</p>

# Islands

> "Awww man, another macOS window manager? 😫"

Yessir.

Hold a key combo (default = `Ctrl+Opt`) then press an arrow key. Focused window snaps to that side. Press again and it squishes further to that side. Simple.

A few other cool things:

- key combo + `Enter` maximizes the window
- key combo + `Cmd` + arrows keeps the window centered when resizing
- got another monitor that way? the window overflows onto it
- drop two windows in the same spot and they accordion-stack, the back one peeks out a few pixels so you don't lose it. key combo + `Tab` rotates the stack
- horizontal and vertical are independent. left half + top half = top-left quarter
- every modifier is reconfigurable in Settings
- lives in the menu bar, no Dock icon, no animations, no overlays

**Download:** [latest release](https://github.com/JaimeOrtegaxyz/Islands/releases/latest) · macOS 14+ · Apple Silicon only (not tested on Intel, no plans to chase it)

## Keybindings

| Shortcut | What it does |
|---|---|
| `Ctrl+Opt + ←/→/↑/↓` | Cycle the focused window's size on that axis |
| `Ctrl+Opt + Return` | Maximize |
| `Ctrl+Opt + Cmd + ←/→/↑/↓` | Centered grow / shrink |
| `Ctrl+Opt + Tab` | Rotate the accordion stack |
| `Ctrl+Opt + Shift + Tab` | Rotate it the other way |

## Snap sizes

Each arrow press steps through a set of fractions. Default is **sixths** (⅙ → ⅓ → ½ → ⅔ → ⅚). In Settings you can switch to:

- **Quarters**: ¼, ½, ¾
- **Sixths**: ⅙, ⅓, ½, ⅔, ⅚
- **Quarters + Sixths**: both, combined

## Settings

Menu bar icon → *Settings…*:

- re-record the base modifier combo (click the chip, press keys, release)
- pick the extra modifiers for centered mode and reverse stack
- choose snap profile
- adjust accordion peek size (small / medium / large)
- toggle launch at login
- restore defaults

## Install

Download the `.dmg` from [Releases](https://github.com/JaimeOrtegaxyz/Islands/releases/latest), drag `Islands.app` into Applications, grant Accessibility when asked.

## Build from source

```bash
git clone https://github.com/JaimeOrtegaxyz/Islands
cd Islands && make
open Islands.app
```

## How it works

Direct Accessibility API calls via `AXUIElement`, plus Carbon for the global hotkeys (still the cleanest way to grab keys system-wide). No animation, no runtime overhead. Windows move instantly. As they should.

## License

MIT. See [LICENSE](LICENSE).
