import Foundation

/// The TOML written to ~/.config/shift/config.toml on first launch.
///
/// Built-in positions (Basic Layout + Displays) live in the app; the config can
/// only rebind their shortcuts via [keybindings]. Custom positions are fully
/// user-owned via [[position]] blocks.
enum DefaultConfig {
    static let toml = """
    # Shift configuration — https://github.com/GhostLabsHQ/shift
    #
    # The screen's usable area (minus menu bar / Dock) is divided into a grid.
    # A `cell = [x, y, w, h]` is in grid units with a TOP-LEFT origin:
    #   x = columns from the left,  y = rows from the top,
    #   w = width in columns,       h = height in rows.
    #
    # There are two kinds of positions:
    #
    #  • Built-in (Basic Layout + Displays) — baked into the app. You can't add,
    #    remove, or move them, but you CAN change their shortcut in [keybindings]
    #    below (key by `code`; set to "" to unbind, or delete the line to keep
    #    the default).
    #
    #  • Custom — fully yours. Add / edit / remove the [[position]] blocks at the
    #    bottom. Each needs a `code`, a `cell` or `action`, and an optional `key`.
    #
    # Keys: cmd / ctrl / alt(opt) / shift  +  a-z, 0-9, arrows, return, space,
    #       tab, delete, esc, f1-f12, punctuation.   e.g. "cmd+ctrl+left"
    #
    # Edit this file and save — Shift reloads automatically.

    [settings]
    # The grid is a fixed 24×12 (not configurable); cells below are in those units.
    gap = 0                      # px between adjacent windows
    screen_gap = 0              # px outer margin from screen edges
    # menu_icon: an SF Symbol name (e.g. "square.grid.3x3", "macwindow",
    # "rectangle.grid.2x2"), a path to a template PNG/PDF, or literal text/emoji.
    menu_icon = "rectangle.3.group"

    # ── Built-in shortcuts ───────────────────────────────────
    # Rebind any built-in here. Delete a line to keep its default; set "" to unbind.
    [keybindings]
    # Halves
    left-half        = "cmd+ctrl+left"
    right-half       = "cmd+ctrl+right"
    top-half         = "cmd+ctrl+up"
    bottom-half      = "cmd+ctrl+down"
    # Quarters
    top-left         = "cmd+ctrl+u"
    top-right        = "cmd+ctrl+i"
    bottom-left      = "cmd+ctrl+j"
    bottom-right     = "cmd+ctrl+k"
    # Thirds
    left-third       = "cmd+ctrl+d"
    center-third     = "cmd+ctrl+x"        # ⌘⌃F is the macOS "Enter Full Screen" shortcut
    right-third      = "cmd+ctrl+g"
    # Two-thirds
    left-two-thirds  = "cmd+ctrl+e"
    right-two-thirds = "cmd+ctrl+t"
    # Vertical thirds — stack windows top/middle/bottom (great on portrait displays).
    # Unbound by default; uncomment and pick shortcuts to enable.
    # top-third         = ""
    # middle-third      = ""
    # bottom-third      = ""
    # top-two-thirds    = ""
    # bottom-two-thirds = ""
    # Window actions
    maximize         = "cmd+ctrl+return"
    center           = "cmd+ctrl+c"
    restore          = "cmd+ctrl+delete"
    # Move & Resize: nudge the window one grid cell at a time (off-grid windows
    # snap to the nearest cell first). Unbound by default; uncomment to enable.
    # move-left         = ""
    # move-right        = ""
    # move-up           = ""
    # move-down         = ""
    # grow-width        = ""
    # shrink-width      = ""
    # grow-height       = ""
    # shrink-height     = ""
    # Displays
    next-display     = "cmd+ctrl+alt+right"
    prev-display     = "cmd+ctrl+alt+left"

    # ── Custom Layout — your own positions ───────────────────
    [[position]]
    code = "center-half"
    name = "Center Half"
    category = "Custom Layout"
    cell = [6, 0, 12, 12]       # 50% width, 100% height, centered
    key  = "cmd+ctrl+1"

    [[position]]
    code = "left-quarter"
    name = "Left Quarter"
    category = "Custom Layout"
    cell = [0, 0, 6, 12]        # 25% width, 100% height
    key  = "cmd+ctrl+2"

    [[position]]
    code = "left-quarter-top"
    name = "Left Quarter (Top)"
    category = "Custom Layout"
    cell = [0, 0, 6, 6]         # 25% width, top 50% height
    key  = "cmd+ctrl+shift+2"

    [[position]]
    code = "left-quarter-bottom"
    name = "Left Quarter (Bottom)"
    category = "Custom Layout"
    cell = [0, 6, 6, 6]         # 25% width, bottom 50% height
    key  = "cmd+ctrl+alt+2"

    [[position]]
    code = "right-quarter"
    name = "Right Quarter"
    category = "Custom Layout"
    cell = [18, 0, 6, 12]       # 25% width, 100% height
    key  = "cmd+ctrl+3"

    [[position]]
    code = "right-quarter-top"
    name = "Right Quarter (Top)"
    category = "Custom Layout"
    cell = [18, 0, 6, 6]        # 25% width, top 50% height
    key  = "cmd+ctrl+shift+3"

    [[position]]
    code = "right-quarter-bottom"
    name = "Right Quarter (Bottom)"
    category = "Custom Layout"
    cell = [18, 6, 6, 6]        # 25% width, bottom 50% height
    key  = "cmd+ctrl+alt+3"

    # ── Cycles ───────────────────────────────────────────────
    # Press the same shortcut again to step through the list (wraps around).
    # A cycle can share its shortcut with its FIRST position, so the first press
    # works exactly like before. Mix built-in and custom codes freely.
    [[cycle]]
    key       = "cmd+ctrl+left"
    positions = ["left-half", "left-two-thirds", "left-third"]

    [[cycle]]
    key       = "cmd+ctrl+right"
    positions = ["right-half", "right-two-thirds", "right-third"]

    [[cycle]]
    key       = "cmd+ctrl+up"
    positions = ["top-half", "top-two-thirds", "top-third"]

    [[cycle]]
    key       = "cmd+ctrl+down"
    positions = ["bottom-half", "bottom-two-thirds", "bottom-third"]

    # ── Example: a keyless, menu-only custom position ────────
    # [[position]]
    # code = "reading"
    # name = "Reading"
    # category = "Custom Layout"
    # cell = [5, 2, 14, 8]

    """
}
