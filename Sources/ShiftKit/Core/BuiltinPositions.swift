import Foundation

/// Positions baked into the app. Their geometry, name, and category are fixed —
/// the config can only rebind their shortcut (via the `[keybindings]` table).
/// Specs are listed in menu order: "Basic Layout", "Move & Resize", then "Displays".
enum BuiltinPositions {
    static let basicCategory = "Basic Layout"
    static let adjustCategory = "Move & Resize"
    static let displaysCategory = "Displays"

    struct Spec {
        let code: String
        let name: String
        let category: String
        let kind: PositionKind
        let defaultKey: String?
    }

    private static func half(_ code: String, _ name: String, _ rect: CellRect, _ key: String?) -> Spec {
        Spec(code: code, name: name, category: basicCategory, kind: .cell(rect), defaultKey: key)
    }

    private static func adjust(_ code: String, _ name: String, _ delta: CellDelta) -> Spec {
        Spec(code: code, name: name, category: adjustCategory, kind: .adjust(delta), defaultKey: nil)
    }

    static let specs: [Spec] = [
        // ── Basic Layout: halves ──
        half("left-half",   "Left Half",   CellRect(x: 0,  y: 0, w: 12, h: 12), "cmd+ctrl+left"),
        half("right-half",  "Right Half",  CellRect(x: 12, y: 0, w: 12, h: 12), "cmd+ctrl+right"),
        half("top-half",    "Top Half",    CellRect(x: 0,  y: 0, w: 24, h: 6),  "cmd+ctrl+up"),
        half("bottom-half", "Bottom Half", CellRect(x: 0,  y: 6, w: 24, h: 6),  "cmd+ctrl+down"),
        // ── Basic Layout: quarters ──
        half("top-left",     "Top Left",     CellRect(x: 0,  y: 0, w: 12, h: 6), "cmd+ctrl+u"),
        half("top-right",    "Top Right",    CellRect(x: 12, y: 0, w: 12, h: 6), "cmd+ctrl+i"),
        half("bottom-left",  "Bottom Left",  CellRect(x: 0,  y: 6, w: 12, h: 6), "cmd+ctrl+j"),
        half("bottom-right", "Bottom Right", CellRect(x: 12, y: 6, w: 12, h: 6), "cmd+ctrl+k"),
        // ── Basic Layout: thirds (24 / 3 = 8 cols) ──
        half("left-third",   "Left Third",   CellRect(x: 0,  y: 0, w: 8, h: 12), "cmd+ctrl+d"),
        half("center-third", "Center Third", CellRect(x: 8,  y: 0, w: 8, h: 12), "cmd+ctrl+x"), // ⌘⌃F is taken by macOS
        half("right-third",  "Right Third",  CellRect(x: 16, y: 0, w: 8, h: 12), "cmd+ctrl+g"),
        // ── Basic Layout: two-thirds ──
        half("left-two-thirds",  "Left Two-Thirds",  CellRect(x: 0, y: 0, w: 16, h: 12), "cmd+ctrl+e"),
        half("right-two-thirds", "Right Two-Thirds", CellRect(x: 8, y: 0, w: 16, h: 12), "cmd+ctrl+t"),
        // ── Basic Layout: vertical thirds (stack windows; handy on portrait displays).
        //    Keyless by default — bind any of these via [keybindings]. (12 / 3 = 4 rows.) ──
        half("top-third",    "Top Third",    CellRect(x: 0, y: 0, w: 24, h: 4), nil),
        half("middle-third", "Middle Third", CellRect(x: 0, y: 4, w: 24, h: 4), nil),
        half("bottom-third", "Bottom Third", CellRect(x: 0, y: 8, w: 24, h: 4), nil),
        half("top-two-thirds",    "Top Two-Thirds",    CellRect(x: 0, y: 0, w: 24, h: 8), nil),
        half("bottom-two-thirds", "Bottom Two-Thirds", CellRect(x: 0, y: 4, w: 24, h: 8), nil),
        // ── Basic Layout: window actions ──
        Spec(code: "maximize", name: "Maximize", category: basicCategory, kind: .maximize, defaultKey: "cmd+ctrl+return"),
        Spec(code: "center",   name: "Center",   category: basicCategory, kind: .center,   defaultKey: "cmd+ctrl+c"),
        Spec(code: "restore",  name: "Restore",  category: basicCategory, kind: .restore,  defaultKey: "cmd+ctrl+delete"),
        // ── Move & Resize: one grid cell at a time. Keyless by default. ──
        adjust("move-left",     "Move Left",     CellDelta(dx: -1)),
        adjust("move-right",    "Move Right",    CellDelta(dx: 1)),
        adjust("move-up",       "Move Up",       CellDelta(dy: -1)),
        adjust("move-down",     "Move Down",     CellDelta(dy: 1)),
        adjust("grow-width",    "Grow Width",    CellDelta(dw: 1)),
        adjust("shrink-width",  "Shrink Width",  CellDelta(dw: -1)),
        adjust("grow-height",   "Grow Height",   CellDelta(dh: 1)),
        adjust("shrink-height", "Shrink Height", CellDelta(dh: -1)),
        // ── Displays ──
        Spec(code: "next-display", name: "Next Display",     category: displaysCategory, kind: .nextDisplay,     defaultKey: "cmd+ctrl+alt+right"),
        Spec(code: "prev-display", name: "Previous Display", category: displaysCategory, kind: .previousDisplay, defaultKey: "cmd+ctrl+alt+left"),
    ]

    static let codes: Set<String> = Set(specs.map(\.code))

    /// The built-in positions as a list, with `[keybindings]` overrides applied.
    /// An override of "" / "none" / "off" unbinds; an absent/blank one keeps the
    /// default; an unparseable one is reported via `warn` and left at the default.
    static func resolved(overrides: [String: String], warn: (String) -> Void = { _ in }) -> [Position] {
        specs.map { spec in
            var key = spec.defaultKey.flatMap { KeyParser.keybinding(from: $0) }
            if let override = overrides[spec.code] {
                let trimmed = override.trimmingCharacters(in: .whitespaces).lowercased()
                if ["", "none", "off", "disabled"].contains(trimmed) {
                    key = nil
                } else if let kb = KeyParser.keybinding(from: override) {
                    key = kb
                } else {
                    warn("[keybindings] \(spec.code) = '\(override)' isn't a valid shortcut, keeping the default")
                }
            }
            return Position(code: spec.code, name: spec.name, category: spec.category,
                            kind: spec.kind, key: key, isBuiltin: true)
        }
    }
}
