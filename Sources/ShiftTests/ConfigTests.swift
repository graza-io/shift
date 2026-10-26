import Carbon
@testable import ShiftKit

func runConfigTests() {
    R.suite("Config")

    R.noThrow("parse settings + custom position") {
        let config = try ConfigLoader.parse("""
        [settings]
        columns = 16
        rows = 8
        gap = 6
        screen_gap = 12
        menu_icon = "macwindow"

        [[position]]
        code = "reading"
        cell = [0, 0, 8, 8]
        key = "cmd+alt+left"
        """)
        // The grid is fixed: columns/rows in config are ignored, not honored.
        R.equal(config.settings.columns, 24, "columns locked at 24")
        R.equal(config.settings.rows, 12, "rows locked at 12")
        R.equal(config.settings.gap, 6, "gap")
        R.equal(config.settings.screenGap, 12, "screen_gap")
        R.equal(config.settings.menuIcon, "macwindow", "menu_icon")

        let customs = config.positions.filter { !$0.isBuiltin }
        R.equal(customs.count, 1, "one custom position")
        R.equal(customs.first?.code, "reading", "code")
        R.equal(customs.first?.isBuiltin, false, "custom is not built-in")
        R.ok(customs.first?.kind == .cell(CellRect(x: 0, y: 0, w: 8, h: 8)), "cell kind")
        R.equal(customs.first?.key?.keyCode, UInt32(kVK_LeftArrow), "bound key")
    }

    R.noThrow("built-ins are present even with an empty config") {
        let config = try ConfigLoader.parse("""
        [settings]
        columns = 24
        """)
        R.equal(config.positions.count, BuiltinPositions.specs.count, "only the built-ins")
        let lh = config.positions.first { $0.code == "left-half" }
        R.equal(lh?.isBuiltin, true, "left-half is built-in")
        R.equal(lh?.name, "Left Half", "built-in display name")
        R.equal(lh?.category, "Basic Layout", "built-in category")
        R.equal(lh?.key?.keyCode, UInt32(kVK_LeftArrow), "built-in default key")
        R.ok(lh?.kind == .cell(CellRect(x: 0, y: 0, w: 12, h: 12)), "built-in geometry")
    }

    R.noThrow("vertical-third built-ins: keyless by default, bindable, exact thirds") {
        let config = try ConfigLoader.parse("""
        [keybindings]
        middle-third = "cmd+ctrl+m"
        """)
        let top = config.positions.first { $0.code == "top-third" }
        R.ok(top?.isBuiltin == true, "top-third is built-in")
        R.equal(top?.category, "Basic Layout", "top-third under Basic Layout")
        R.ok(top?.key == nil, "top-third keyless by default")
        R.ok(top?.kind == .cell(CellRect(x: 0, y: 0, w: 24, h: 4)), "top-third = exact top third")

        let bottom = config.positions.first { $0.code == "bottom-third" }
        R.ok(bottom?.kind == .cell(CellRect(x: 0, y: 8, w: 24, h: 4)), "bottom-third = exact bottom third")

        // A keyless built-in can be bound via [keybindings].
        let middle = config.positions.first { $0.code == "middle-third" }
        R.equal(middle?.key?.keyCode, UInt32(kVK_ANSI_M), "middle-third bound via keybindings")
    }

    R.noThrow("keybindings override and unbind built-ins") {
        let config = try ConfigLoader.parse("""
        [keybindings]
        left-half = "cmd+ctrl+h"
        maximize = ""
        """)
        let lh = config.positions.first { $0.code == "left-half" }
        R.equal(lh?.key?.keyCode, UInt32(kVK_ANSI_H), "override applied")
        let mx = config.positions.first { $0.code == "maximize" }
        R.ok(mx?.key == nil, "empty string unbinds")
        let rh = config.positions.first { $0.code == "right-half" }
        R.equal(rh?.key?.keyCode, UInt32(kVK_RightArrow), "untouched built-in keeps default")
    }

    R.noThrow("a built-in code in [[position]] is ignored") {
        let config = try ConfigLoader.parse("""
        [[position]]
        code = "left-half"
        cell = [0, 0, 1, 1]
        key = "cmd+ctrl+z"
        """)
        let lefts = config.positions.filter { $0.code == "left-half" }
        R.equal(lefts.count, 1, "no duplicate left-half")
        R.ok(lefts.first?.isBuiltin == true, "kept the built-in")
        R.ok(lefts.first?.kind == .cell(CellRect(x: 0, y: 0, w: 12, h: 12)), "built-in geometry, not [[position]]'s")
        R.equal(config.positions.filter { !$0.isBuiltin }.count, 0, "colliding custom dropped")
    }

    R.noThrow("custom categories sit between Basic Layout and Displays") {
        let config = try ConfigLoader.parse("""
        [[position]]
        code = "mine"
        category = "Custom Layout"
        cell = [0, 0, 6, 12]
        """)
        let lastBasic = config.positions.lastIndex { $0.category == "Basic Layout" }!
        let mine = config.positions.firstIndex { $0.code == "mine" }!
        let firstDisplay = config.positions.firstIndex { $0.category == "Displays" }!
        R.ok(lastBasic < mine, "custom comes after Basic Layout")
        R.ok(mine < firstDisplay, "custom comes before Displays")
    }

    R.noThrow("code, name, and category on custom positions") {
        let config = try ConfigLoader.parse("""
        [[position]]
        code = "center-half"
        name = "Center Half"
        category = "Custom Layout"
        cell = [6, 0, 12, 12]

        [[position]]
        code = "left-quarter"
        cell = [0, 0, 6, 12]

        [[position]]
        name = "Right Quarter"
        cell = [18, 0, 6, 12]
        """)
        let customs = config.positions.filter { !$0.isBuiltin }
        R.equal(customs.count, 3, "three custom positions")
        R.equal(customs[0].code, "center-half", "explicit code")
        R.equal(customs[0].name, "Center Half", "explicit name")
        R.equal(customs[0].category, "Custom Layout", "category")
        // name derived from code
        R.equal(customs[1].name, "Left Quarter", "name humanized from code")
        R.ok(customs[1].category == nil, "no category → nil")
        // code derived from name
        R.equal(customs[2].code, "right-quarter", "code slugged from name")
    }

    R.noThrow("defaults when [settings] omitted") {
        let config = try ConfigLoader.parse("""
        [[position]]
        code = "max"
        action = "maximize"
        """)
        R.equal(config.settings.columns, 24, "default columns")
        R.equal(config.settings.rows, 12, "default rows")
        R.equal(config.settings.menuIcon, "rectangle.3.group", "default menu_icon")
        R.ok(config.positions.first { $0.code == "max" }?.kind == .maximize, "maximize action")
    }

    R.noThrow("action normalization") {
        let config = try ConfigLoader.parse("""
        [[position]]
        code = "a"
        action = "previous-display"
        [[position]]
        code = "b"
        action = "next_display"
        [[position]]
        code = "c"
        action = "PrevDisplay"
        """)
        R.ok(config.positions.first { $0.code == "a" }?.kind == .previousDisplay, "hyphen: previous-display")
        R.ok(config.positions.first { $0.code == "b" }?.kind == .nextDisplay, "underscore: next_display")
        R.ok(config.positions.first { $0.code == "c" }?.kind == .previousDisplay, "case + alias: PrevDisplay")
    }

    R.noThrow("keyless custom position kept unbound") {
        let config = try ConfigLoader.parse("""
        [[position]]
        code = "reading"
        cell = [6, 0, 12, 12]
        """)
        let customs = config.positions.filter { !$0.isBuiltin }
        R.equal(customs.count, 1, "kept")
        R.ok(customs.first?.key == nil, "unbound")
    }

    R.noThrow("invalid custom entries skipped, not fatal") {
        let config = try ConfigLoader.parse("""
        [[position]]
        code = "ok"
        cell = [0, 0, 1, 1]
        [[position]]
        cell = [0, 0, 1, 1]
        [[position]]
        code = "bad-action"
        action = "teleport"
        [[position]]
        code = "no-kind"
        """)
        R.equal(config.positions.filter { !$0.isBuiltin }.map(\.code), ["ok"], "only valid custom kept")
    }

    R.noThrow("bad key leaves custom position unbound") {
        let config = try ConfigLoader.parse("""
        [[position]]
        code = "x"
        cell = [0, 0, 1, 1]
        key = "cmd+totally-not-a-key"
        """)
        let customs = config.positions.filter { !$0.isBuiltin }
        R.equal(customs.count, 1, "kept")
        R.ok(customs.first?.key == nil, "unbound on bad key")
    }

    R.throwsError("malformed TOML throws") { _ = try ConfigLoader.parse("this is = = not toml [") }

    R.noThrow("parse errors are described with a line number") {
        do {
            _ = try ConfigLoader.parse("[settings]\ngap = 0\nthis is = = not toml [")
            R.ok(false, "expected a parse error")
        } catch {
            let message = Config.describe(error)
            R.ok(message.hasPrefix("Line 3:"), "points at line 3 — got \(message)")
        }
    }

    R.noThrow("invalid entries are reported as warnings") {
        let config = try ConfigLoader.parse("""
        [[position]]
        code = "bad-action"
        action = "teleport"
        [[position]]
        code = "bad-cell"
        cell = [0, 0, 1]
        [[position]]
        code = "no-kind"
        [[position]]
        code = "bad-key"
        cell = [0, 0, 1, 1]
        key = "cmd+nope"
        """)
        let w = config.warnings
        R.equal(w.count, 4, "one warning per bad entry — got \(w)")
        R.ok(w.contains { $0.contains("bad-action") && $0.contains("teleport") }, "unknown action")
        R.ok(w.contains { $0.contains("bad-cell") && $0.contains("invalid cell") }, "malformed cell")
        R.ok(w.contains { $0.contains("no-kind") && $0.contains("needs a cell or an action") }, "missing cell/action")
        R.ok(w.contains { $0.contains("bad-key") && $0.contains("cmd+nope") }, "unparseable key")
        R.equal(config.positions.filter { !$0.isBuiltin }.map(\.code), ["bad-key"], "bad key still kept, unbound")
    }

    R.noThrow("out-of-grid cells are kept but warned about") {
        let config = try ConfigLoader.parse("""
        [[position]]
        code = "too-wide"
        cell = [20, 0, 8, 12]
        """)
        R.equal(config.positions.filter { !$0.isBuiltin }.count, 1, "kept (geometry clamps it)")
        R.ok(config.warnings.contains { $0.contains("too-wide") && $0.contains("24×12") }, "warned")
    }

    R.noThrow("typos and unknown keys are flagged") {
        let config = try ConfigLoader.parse("""
        [settings]
        gapp = 4
        gap = "wide"

        [keybindings]
        left-halff = "cmd+ctrl+h"
        right-half = "cmd+ctrl+nope"

        [[position]]
        code = "x"
        ceel = [0, 0, 1, 1]
        cell = [0, 0, 1, 1]

        [[postion]]
        code = "y"
        """)
        let w = config.warnings
        R.ok(w.contains { $0.contains("gapp") }, "unknown setting")
        R.ok(w.contains { $0.contains("gap must be a number") }, "wrong type for gap")
        R.ok(w.contains { $0.contains("left-halff") }, "unknown built-in in [keybindings]")
        R.ok(w.contains { $0.contains("right-half") && $0.contains("cmd+ctrl+nope") }, "bad built-in shortcut")
        R.ok(w.contains { $0.contains("ceel") }, "unknown position key")
        R.ok(w.contains { $0.contains("postion") }, "unknown table")
        R.equal(config.settings.gap, 0, "bad gap falls back to default")
    }

    R.noThrow("clashing shortcuts are flagged and only the first keeps it") {
        let config = try ConfigLoader.parse("""
        [[position]]
        code = "mine"
        cell = [0, 0, 6, 12]
        key = "cmd+ctrl+left"
        """)
        let lh = config.positions.first { $0.code == "left-half" }
        let mine = config.positions.first { $0.code == "mine" }
        R.equal(lh?.key?.keyCode, UInt32(kVK_LeftArrow), "built-in keeps the shortcut")
        R.ok(mine?.key == nil, "later duplicate is unbound")
        R.ok(config.warnings.contains { $0.contains("Left Half") && $0.contains("Mine") }, "clash warned")
    }

    R.noThrow("duplicate custom codes are flagged") {
        let config = try ConfigLoader.parse("""
        [[position]]
        code = "dup"
        cell = [0, 0, 1, 1]
        [[position]]
        code = "dup"
        cell = [1, 1, 1, 1]
        """)
        R.equal(config.positions.filter { $0.code == "dup" }.count, 1, "only the first kept")
        R.ok(config.warnings.contains { $0.contains("dup") && $0.contains("more than once") }, "warned")
    }

    R.noThrow("shipped default config parses") {
        let config = try ConfigLoader.parse(DefaultConfig.toml)
        R.equal(config.warnings, [], "no warnings")
        R.ok(config.positions.count >= 17, "has at least 17 positions (got \(config.positions.count))")

        let leftHalf = config.positions.first { $0.code == "left-half" }
        R.ok(leftHalf?.isBuiltin == true, "left-half is built-in")
        R.ok(leftHalf?.kind == .cell(CellRect(x: 0, y: 0, w: 12, h: 12)), "left-half cell")
        R.ok(leftHalf?.key != nil, "left-half bound")
        R.equal(leftHalf?.name, "Left Half", "left-half display name")
        R.equal(leftHalf?.category, "Basic Layout", "left-half category")

        // center-third must dodge the ⌘⌃F "Enter Full Screen" system shortcut.
        let centerThird = config.positions.first { $0.code == "center-third" }
        R.equal(centerThird?.key?.keyCode, UInt32(kVK_ANSI_X), "center-third on X not F")

        // The custom layouts ship in the default config under "Custom Layout".
        let centerHalf = config.positions.first { $0.code == "center-half" }
        R.ok(centerHalf?.isBuiltin == false, "center-half is custom")
        R.ok(centerHalf?.kind == .cell(CellRect(x: 6, y: 0, w: 12, h: 12)), "center-half cell")
        R.equal(centerHalf?.category, "Custom Layout", "center-half category")

        // maximize / center / restore are built-in under Basic Layout.
        let maximize = config.positions.first { $0.code == "maximize" }
        R.equal(maximize?.category, "Basic Layout", "maximize under Basic Layout")
        R.ok(maximize?.isBuiltin == true, "maximize is built-in")

        let displays = config.positions.filter { $0.category == "Displays" }
        R.equal(displays.count, 2, "two display throws")
    }
}

func runAppInfoTests() {
    R.suite("AppInfo")
    let label = AppInfo.versionLabel
    R.ok(!label.isEmpty, "version label is non-empty")
    // Under `swift run` there is no versioned bundle → "dev"; a packaged app → "vX.Y.Z".
    R.ok(label == "dev" || label.hasPrefix("v"), "label is 'dev' or 'vX.Y.Z' — got \(label)")
}

func runMenuLayoutTests() {
    R.suite("MenuLayout")

    func pos(_ code: String, _ category: String?, _ kind: PositionKind) -> Position {
        Position(code: code, name: code, category: category, kind: kind, key: nil)
    }
    let unit = PositionKind.cell(CellRect(x: 0, y: 0, w: 1, h: 1))

    R.noThrow("default-style grouping clusters layouts, sets Displays apart") {
        let positions = [
            pos("left-half", "Basic Layout", unit),
            pos("maximize", "Basic Layout", .maximize),
            pos("center-half", "Custom Layout", unit),
            pos("next", "Displays", .nextDisplay),
            pos("prev", "Displays", .previousDisplay),
        ]
        let sections = MenuLayout.sections(for: positions)
        R.equal(sections.map(\.title), ["Basic Layout", "Custom Layout", "Displays"], "three categories in order")
        R.equal(sections[0].separatorBefore, false, "first: no separator")
        R.equal(sections[1].separatorBefore, false, "Custom hugs Basic")
        R.equal(sections[2].separatorBefore, true, "Displays set apart")
        R.equal(sections[0].positionIndices, [0, 1], "Basic Layout keeps both members")
    }

    R.noThrow("uncategorized config → single inline section") {
        let positions = [pos("a", nil, unit), pos("b", nil, unit)]
        let sections = MenuLayout.sections(for: positions)
        R.equal(sections.count, 1, "one section")
        R.equal(sections[0].title, "", "empty title → rendered inline")
    }
}
