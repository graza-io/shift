# Shift

A free, open-source macOS window manager driven by a fixed **24×12 grid** and a plain-text config file.

Register named positions tied to grid cells (`[x, y, w, h]`) and bind them to keyboard shortcuts. Edit one TOML file; Shift reloads it live. Inspired by Nudge and Magnet, minus the mouse dragging.

## Requirements

- macOS 11+
- Swift 5.9+ toolchain (Xcode **or** the standalone Command Line Tools - `xcode-select --install`)

Builds with SwiftPM; no Xcode required.

## Build & run

```bash
cd shift
swift build                 # resolves TOMLKit + compiles
swift run Shift            # launches the menu-bar agent (runs until you Quit)
```

On first launch grant **Accessibility** access (System Settings → Privacy & Security → Accessibility). Shift lives in the menu bar (no Dock icon).

> The dev binary at `.build/debug/Shift` is unsigned, so macOS may ask you to
> re-grant Accessibility after a rebuild changes its signature. For a stable,
> signed `.app`, open `Package.swift` in Xcode and archive.

## Config

On first launch Shift seeds `~/.config/shift/config.toml` with sensible defaults
(halves/quarters/thirds/etc. on ⌘⌃ shortcuts). Edit and save - it reloads automatically.

There are two kinds of positions:

- **Built-in** - the **Basic Layout** group (halves/quarters/thirds/two-thirds,
  vertical top/middle/bottom thirds for stacking on portrait displays, +
  maximize/center/restore) and **Displays** (next/previous). These are baked into
  the app: you can't add, remove, or move them, but you *can* rebind their
  shortcuts in the `[keybindings]` table (keyed by `code`; `""` unbinds, and a
  deleted line keeps the default). The vertical thirds are **unbound by default** -
  give them a shortcut in `[keybindings]` to enable, or trigger them from the menu.
- **Custom** - fully yours. Add / edit / remove `[[position]]` blocks.

The grid is a fixed **24×12** - those numbers divide cleanly into halves, thirds,
quarters, sixths, and eighths, so it isn't configurable (and the built-ins rely on
it). All cells are expressed in those grid units.

```toml
[settings]
gap = 0                          # px between adjacent windows
screen_gap = 0                   # px outer margin
menu_icon = "rectangle.3.group"  # SF Symbol name, image path, or literal text/emoji

# Rebind built-ins (delete a line to keep its default; "" to unbind):
[keybindings]
left-half    = "cmd+ctrl+left"
maximize     = "cmd+ctrl+return"
next-display = "cmd+ctrl+alt+right"
# … 18 built-ins total

# Custom positions:
[[position]]
code     = "center-half"         # stable id
name     = "Center Half"         # friendly name shown in the menu
category = "Custom Layout"       # menu grouping
cell     = [6, 0, 12, 12]        # x, y, w, h  - top-left origin
key      = "cmd+ctrl+1"

[[position]]
code = "reading"                 # keyless = menu-only, still in the registry
cell = [5, 2, 14, 8]
```

Custom positions can also use `action =` instead of `cell`: `maximize`, `center`,
`restore`, `next-display` / `previous-display`.

The menu groups positions into submenus by `category`: **Basic Layout**, then your
custom categories, then **Displays**.

Default modifier scheme: positions on **⌘⌃**, monitor throws on **⌘⌃⌥←/→**.

## Test

```bash
swift run ShiftTests       # self-contained unit suite (geometry, key parsing, config)
```

Verify grid geometry numerically without moving any windows:

```bash
swift run Shift --print-grid
```

Debug log: `~/shift-debug.log` (DEBUG builds).

## Build for other machines

> Full guide: [docs/BUILD.md](docs/BUILD.md).

```bash
./scripts/build-app.sh        # → dist/Shift.app and dist/Shift.zip
```

This makes a release `Shift.app` (a self-contained ~300 KB bundle - TOMLKit is
statically linked). By default it builds for the host architecture and ad-hoc
signs it.

- **Apple Silicon → Apple Silicon:** copy `Shift.app` to `/Applications` and run.
- **Also need Intel Macs?** Build universal with `ARCHS="arm64 x86_64" ./scripts/build-app.sh`
  - this requires **full Xcode** (multi-arch SwiftPM builds use `xcbuild`).

On the target Mac, Gatekeeper quarantines apps from unidentified developers. If
it won't open:

```bash
xattr -dr com.apple.quarantine /Applications/Shift.app
```

Then grant Accessibility on first launch. (Accessibility is per-machine, so each
Mac grants once.)

Releases are automated via GitHub Actions - push a `v*` tag and the workflow
builds, zips, and publishes the app. See [docs/BUILD.md](docs/BUILD.md).

## License

MIT
