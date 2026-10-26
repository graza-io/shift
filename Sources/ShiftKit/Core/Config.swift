import Foundation
import CoreGraphics
import TOMLKit

/// Owns the on-disk config: seeding, loading/parsing, and live reload.
final class Config {
    static let shared = Config()
    private init() {}

    private(set) var current = ShiftConfig(settings: GridSettings(), positions: [])
    /// Why the last reload failed (nil when it succeeded). `current` is then
    /// still the last good config.
    private(set) var loadError: String?
    private var watcher: FileWatcher?

    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/shift", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("config.toml")
    }

    // MARK: - Load / seed

    func loadOrSeed() {
        if !FileManager.default.fileExists(atPath: Self.fileURL.path) {
            seed()
        }
        reload()
    }

    private func seed() {
        do {
            try FileManager.default.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
            try DefaultConfig.toml.write(to: Self.fileURL, atomically: true, encoding: .utf8)
            FileLog.write("seeded default config at \(Self.fileURL.path)")
        } catch {
            FileLog.write("failed to seed config: \(error)")
        }
    }

    func reload() {
        do {
            let text = try String(contentsOf: Self.fileURL, encoding: .utf8)
            current = try ConfigLoader.parse(text)
            loadError = nil
            FileLog.write("config loaded: \(current.positions.count) positions, \(current.positions.filter { $0.key != nil }.count) bound, \(current.warnings.count) warnings")
        } catch {
            loadError = Self.describe(error)
            FileLog.write("config load FAILED: \(error) — keeping previous config")
        }
        NotificationCenter.default.post(name: .configReloaded, object: nil)
    }

    /// A one-line, human-readable reason for a failed load.
    static func describe(_ error: Error) -> String {
        if let e = error as? TOMLParseError {
            return "Line \(e.source.begin.line): \(e.description)"
        }
        if (error as NSError).code == NSFileReadNoSuchFileError {
            return "Couldn't find \(fileURL.path)"
        }
        return error.localizedDescription
    }

    // MARK: - Watch

    func startWatching(_ onChange: @escaping () -> Void) {
        // Watch the directory (not the file) so atomic saves by editors are seen.
        watcher = FileWatcher(url: Self.directoryURL, onChange: onChange)
        watcher?.start()
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }
}

/// Stateless TOML → ShiftConfig parsing. Unit-testable.
///
/// Malformed TOML throws; anything else that's wrong (bad cells, unknown keys,
/// clashing shortcuts…) is skipped or fixed up and reported in `warnings`, so
/// one typo never takes the rest of the config down with it.
enum ConfigLoader {
    private static let knownTables: Set<String> = ["settings", "keybindings", "position"]
    private static let knownSettings: Set<String> = ["gap", "screen_gap", "menu_icon", "columns", "rows"]
    private static let knownPositionKeys: Set<String> = ["code", "name", "category", "cell", "action", "key"]

    static func parse(_ toml: String) throws -> ShiftConfig {
        let root = try TOMLTable(string: toml)
        var warnings: [String] = []
        func warn(_ message: String) {
            warnings.append(message)
            FileLog.write("config: \(message)")
        }

        for key in root.keys where !knownTables.contains(key) {
            warn("unknown table or setting '\(key)' (expected [settings], [keybindings] or [[position]])")
        }

        var settings = GridSettings()
        if let s = root["settings"]?.table {
            for key in s.keys where !knownSettings.contains(key) {
                warn("[settings] has an unknown setting '\(key)'")
            }
            if s["columns"] != nil || s["rows"] != nil {
                warn("the grid is fixed at 24×12, so columns/rows in [settings] are ignored")
            }
            for (key, path) in [("gap", \GridSettings.gap), ("screen_gap", \GridSettings.screenGap)] {
                guard let value = s[key] else { continue }
                if let n = number(value) {
                    settings[keyPath: path] = n
                } else {
                    warn("[settings] \(key) must be a number")
                }
            }
            if let v = s["menu_icon"]?.string, !v.isEmpty { settings.menuIcon = v }
        }

        // Built-in positions are baked in; the config only rebinds their keys.
        var overrides: [String: String] = [:]
        if let kb = root["keybindings"]?.table {
            for code in kb.keys {
                if !BuiltinPositions.codes.contains(code) {
                    warn("[keybindings] '\(code)' isn't a built-in position")
                } else if let v = kb[code]?.string {
                    overrides[code] = v
                } else {
                    warn("[keybindings] \(code) must be a string like \"cmd+ctrl+left\"")
                }
            }
        }
        let builtins = BuiltinPositions.resolved(overrides: overrides, warn: warn)

        // Custom positions: fully user-defined via [[position]].
        var customs: [Position] = []
        if let arr = root["position"]?.array {
            for i in 0..<arr.count {
                guard let table = arr[i].table else { continue }

                // Identity: a position needs at least a `code` or a `name`.
                // `code` is the stable id; `name` is the friendly display name.
                // Either can be derived from the other for backward compatibility.
                let rawCode = table["code"]?.string.flatMap { $0.isEmpty ? nil : $0 }
                let rawName = table["name"]?.string.flatMap { $0.isEmpty ? nil : $0 }
                guard rawCode != nil || rawName != nil else {
                    warn("[[position]] #\(i + 1) has no code or name, skipped")
                    continue
                }
                let code = rawCode ?? slug(rawName!)
                let name = rawName ?? humanize(rawCode!)

                for key in table.keys where !knownPositionKeys.contains(key) {
                    warn("'\(code)' has an unknown setting '\(key)'")
                }
                guard !BuiltinPositions.codes.contains(code) else {
                    warn("'\(code)' is a built-in, rebind it in [keybindings] instead (skipped)")
                    continue
                }
                guard customs.allSatisfy({ $0.code != code }) else {
                    warn("'\(code)' is defined more than once, only the first one is used")
                    continue
                }
                guard let kind = parseKind(code: code, table: table, warn: warn) else { continue }
                let category = table["category"]?.string.flatMap { $0.isEmpty ? nil : $0 }
                var key: Keybinding?
                if let keyValue = table["key"], keyValue.string?.trimmingCharacters(in: .whitespaces).isEmpty != true {
                    if let keyStr = keyValue.string, let kb = KeyParser.keybinding(from: keyStr) {
                        key = kb
                    } else {
                        warn("'\(code)' has an invalid key '\(keyValue.string ?? "?")', left unbound")
                    }
                }
                customs.append(Position(code: code, name: name, category: category, kind: kind, key: key))
            }
        }

        // Menu order: Basic Layout, then the user's custom categories, then Displays.
        let leading = builtins.filter { $0.category != BuiltinPositions.displaysCategory }
        let trailing = builtins.filter { $0.category == BuiltinPositions.displaysCategory }
        let positions = dedupeShortcuts(leading + customs + trailing, warn: warn)
        return ShiftConfig(settings: settings, positions: positions, warnings: warnings)
    }

    /// Two positions on the same shortcut can't both work, so the first one (in
    /// menu order) keeps it and the rest are left unbound.
    private static func dedupeShortcuts(_ positions: [Position], warn: (String) -> Void) -> [Position] {
        var owners: [UInt64: String] = [:]
        return positions.map { position in
            guard let key = position.key else { return position }
            let id = UInt64(key.modifiers) << 32 | UInt64(key.keyCode)
            guard let owner = owners[id] else {
                owners[id] = position.name
                return position
            }
            warn("\(KeyParser.display(key)) is bound to both \(owner) and \(position.name), only \(owner) will work")
            var unbound = position
            unbound.key = nil
            return unbound
        }
    }

    /// "Left Half" → "left-half"  (lowercased, runs of non-alphanumerics → single dash).
    static func slug(_ s: String) -> String {
        let lowered = s.lowercased()
        var out = ""
        var lastWasDash = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// "left-half" → "Left Half"  (separators → spaces, each word capitalized).
    static func humanize(_ s: String) -> String {
        s.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func parseKind(code: String, table: TOMLTable, warn: (String) -> Void) -> PositionKind? {
        if let actionValue = table["action"] {
            guard let action = actionValue.string, let kind = kind(forAction: action) else {
                warn("'\(code)' has an unknown action '\(actionValue.string ?? "?")', skipped")
                return nil
            }
            return kind
        }
        guard let cellValue = table["cell"] else {
            warn("'\(code)' needs a cell or an action, skipped")
            return nil
        }
        guard let cellArr = cellValue.array, cellArr.count == 4,
              let x = cellArr[0].int, let y = cellArr[1].int, let w = cellArr[2].int, let h = cellArr[3].int else {
            warn("'\(code)' has an invalid cell, it should be 4 whole numbers like [x, y, w, h] (skipped)")
            return nil
        }
        let grid = GridSettings()
        if x < 0 || y < 0 || w < 1 || h < 1 || x + w > grid.columns || y + h > grid.rows {
            warn("'\(code)' cell [\(x), \(y), \(w), \(h)] doesn't fit the 24×12 grid, it'll be squeezed to fit")
        }
        return .cell(CellRect(x: x, y: y, w: w, h: h))
    }

    static func kind(forAction action: String) -> PositionKind? {
        switch action.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") {
        case "maximize", "max", "fullscreen": return .maximize
        case "center", "centre":              return .center
        case "restore":                       return .restore
        case "nextdisplay":                   return .nextDisplay
        case "previousdisplay", "prevdisplay": return .previousDisplay
        default:                              return nil
        }
    }

    private static func number(_ value: TOMLValueConvertible?) -> CGFloat? {
        if let d = value?.double { return CGFloat(d) }
        if let i = value?.int { return CGFloat(i) }
        return nil
    }
}
