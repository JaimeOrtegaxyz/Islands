# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Islands is a macOS keyboard-driven window manager. Hold a modifier combo (default `Ctrl+Opt`) + arrow to cycle the focused window through snap fractions; `Enter` maximizes; `Cmd`+arrows resizes centered; `Tab` rotates an "accordion" stack of windows sharing the same zone. It is a menu-bar-only agent app (`LSUIElement` in `Resources/Info.plist`) — no dock icon, no main window.

It's a Swift Package Manager **executable** (not an Xcode project). All UI is programmatic AppKit; there are no storyboards or `.xib` files.

## Build & run

The Makefile is the source of truth, not `swift build` alone — `swift build` produces a bare binary, but the app needs a bundled `Islands.app` with Info.plist, icons, fonts, and `Sparkle.framework`.

```bash
make          # = make build: universal (arm64+x86_64) release build -> Islands.app
make run      # build, then `open Islands.app`
make clean    # rm -rf .build Islands.app dist
swift build   # fast iteration / type-checking only; does NOT produce a runnable bundle
```

`make test` runs the `IslandsCoreTests` suite (swift-testing) covering the pure layout math in `Sources/IslandsCore`; use it — not bare `swift test`, which lacks the test frameworks under a CommandLineTools-only toolchain. There is no linter config.

After changing window-management logic, the only real verification beyond those unit tests is running the app (`make run`) and exercising hotkeys — behavior depends on live Accessibility state and on-screen windows that unit tests can't model.

## Release

`make release VERSION=x.y.z` does the full Developer ID codesign → DMG → Apple notarize → staple → Sparkle EdDSA sign pipeline. It requires the maintainer's signing identity and a one-time `make notary-setup`, so you generally **cannot run it** in this environment. Before a release the version must be bumped in `Resources/Info.plist` (both `CFBundleVersion` and `CFBundleShortVersionString`) — `release-preflight` aborts on mismatch. Auto-updates are served by Sparkle from `docs/appcast.xml` (published via GitHub Pages at the `SUFeedURL`). `RELEASE_GUIDE.md` is gitignored (maintainer-only operational notes).

## Architecture

`Sources/main.swift` boots `NSApplication` with `AppDelegate`. **`AppDelegate.applicationDidFinishLaunching` is the composition root** — it instantiates every manager and wires the dependency graph by hand. Read it first to see how the pieces connect.

Data flow for a window action:

```
Carbon global hotkey  ->  HotkeyManager  ->  WindowManager  ->  WindowEngine  ->  AXUIElement (macOS)
                                                  |
                                                  +-- ScreenManager (multi-monitor geometry)
```

- **`HotkeyManager`** — registers system-wide hotkeys via **Carbon** (`RegisterEventHotKey`), the only reliable way to grab keys globally. A C event-handler callback dispatches to `WindowManager` methods on the main queue. Re-registers itself on `.settingsDidChange`. Only active when Accessibility is trusted (`setEnabled`).

- **`WindowManager`** — the core logic and the largest/most intricate file. Holds all per-window state; `WindowEngine`/`ScreenManager` are mechanical helpers.
  - `AxisLayout` precomputes position/size tables (edge + centered) from a `SnapProfile`'s fractions, plus the index maps that translate between edge ↔ centered states. Built once per axis, rebuilt on settings change.
  - `WindowState` (keyed by `CGWindowID` in `winState`) tracks each window's horizontal/vertical snap index and centered flags.
  - **Accordion stacking ("zones"):** windows snapped to the same fraction on the same screen share a zone key (`getZoneKey`) and are tracked in `zoneWindows`. `applyPeekOffsets` insets stacked windows by `peekPixels` so they fan out; `cycleZone` (Tab) rotates the stack. `synchronizeZoneMembership` reconciles tracked state against where the window actually is before every action (the user may have moved it manually).
  - A 3s `cleanupTimer` prunes closed windows from state.

- **`WindowEngine`** — thin wrapper over the Accessibility API (`AXUIElement`). Gets/sets window frames, raises/focuses. Uses the private SPI `_AXUIElementGetWindow` (declared via `@_silgen_name`) to map an `AXUIElement` to a `CGWindowID`. **All AX calls set a 0.25s messaging timeout** (`AXUIElementSetMessagingTimeout`) so one hung app can't freeze the main thread — preserve this when adding AX calls.

- **`ScreenManager`** — multi-monitor geometry and the directional `screenTo{East,West,North,South}` lookups that power "overflow onto the next monitor". **Coordinate-system gotcha:** `NSScreen` uses a bottom-left origin; AX window positions use a top-left origin. `convertToTopLeftCoordinates` bridges them — any new geometry code must be explicit about which space it's in.

- **`SettingsStore` / `AppSettings.swift`** — settings live in `UserDefaults` as a normalized `AppSettingsSnapshot`. Mutating any setter persists and posts `.settingsDidChange`; `WindowManager` and `HotkeyManager` observe it and reconfigure. `ModifierSet` is an `OptionSet` that converts between `NSEvent.ModifierFlags`, Carbon flags, and display symbols. `normalizedSnapshot` guards against invalid modifier combos (e.g. a base combo that collides with the extra modifiers).

- **`AccessibilityManager`** — wraps `AXIsProcessTrustedWithOptions`. `AppDelegate` polls trust state every 1s while untrusted, gates hotkeys on it, and (via `AccessibilityOnboardingWindowController`) prompts the user. On a *fresh* grant it offers to relaunch, because hotkeys often don't bind correctly until the process restarts after permission is first granted.

- UI controllers (`SettingsWindowController`, `SplashWindowController`, `AccessibilityOnboardingWindowController`, `StatusBar`) are programmatic AppKit. `LaunchAtLoginController` uses `SMAppService`. Custom fonts are bundled and loaded via `Fonts.swift` + `ATSApplicationFontsPath`.

## Conventions

- Managers are `final class`, single-responsibility, injected through initializers (see the composition root). No global singletons except `AccessibilityManager.shared`.
- Cross-component signaling goes through the single `.settingsDidChange` notification, not direct calls.
- Carbon callbacks and AX calls are main-thread-only — work dispatched from C callbacks or background completion handlers hops back to `DispatchQueue.main` (see `HotkeyManager.installHandler` and `AppDelegate.relaunchApplication`).
- **Keep the hot path lean.** Window actions run synchronously on the main thread on every hotkey press, and a single action can fan across several windows (`applyPeekOffsets`). Favor a cheap, simple common path over completeness — don't add AX round-trips, slower loops, or extra state to cover rare or app-specific cases. When a workaround is genuinely unavoidable, gate it behind a cheap check so only the windows that need it pay for it, and keep it contained in `WindowEngine` rather than threading branches through the core logic. `WindowEngine.setFrame` is the model: well-behaved apps take a 2-call fast path, and only apps that advertise `AXEnhancedUserInterface` (Spotify, Electron/Chromium) incur the disable-dance + on-screen re-pin.

## `remotion/`

A standalone TypeScript/React (Remotion + Bun) project that renders the README demo video. **Unrelated to the app build** — don't pull it into Swift work. `cd remotion && bun install && bun run render`.
