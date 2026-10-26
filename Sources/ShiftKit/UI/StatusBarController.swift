import Cocoa

/// Menu-bar UI: lists every registered position (click to apply to the focused
/// window) plus config actions. The menu is rebuilt every time it opens, so the
/// Accessibility status always reflects reality (and starts the hotkey engine
/// the moment access is granted).
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu
        applyIcon()
        populate()
        NotificationCenter.default.addObserver(self, selector: #selector(onConfigReloaded), name: .configReloaded, object: nil)
    }

    @objc private func onConfigReloaded() {
        applyIcon()
        populate()
    }

    /// Sets the menu-bar icon from `settings.menu_icon`, which may be an SF Symbol
    /// name, a path to a template image, or literal text/emoji.
    private func applyIcon() {
        guard let button = statusItem.button else { return }
        let spec = Config.shared.current.settings.menuIcon
        button.image = nil
        button.title = ""

        // 1. A file path to a custom image (sized to fit the menu bar).
        let path = (spec as NSString).expandingTildeInPath
        if spec.contains("/"), let image = NSImage(contentsOfFile: path) {
            let h: CGFloat = 18
            image.size = NSSize(width: h * (image.size.width / max(image.size.height, 1)), height: h)
            image.isTemplate = true
            button.image = image
            return
        }
        // 2. An SF Symbol name.
        if let image = NSImage(systemSymbolName: spec, accessibilityDescription: "Shift") {
            image.isTemplate = true
            button.image = image
            return
        }
        // 3. Fall back to literal text / emoji.
        button.title = spec.isEmpty ? "⌗" : spec
    }

    // Rebuilds contents right before the menu is shown → always-fresh status.
    func menuNeedsUpdate(_ menu: NSMenu) {
        // If access was granted out-of-band, make sure the engine is running.
        if AXIsProcessTrusted() { HotkeyManager.shared.start() }
        populate()
    }

    @objc private func populate() {
        menu.removeAllItems()

        let header = NSMenuItem(title: "Shift (\(AppInfo.versionLabel))", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        addProblemsItem()

        if AXIsProcessTrusted() {
            // We can move windows → show the shortcuts and config actions.
            let positions = Config.shared.current.positions
            if positions.isEmpty {
                let empty = NSMenuItem(title: "No positions configured", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            } else {
                addPositionGroups(positions)
            }
            menu.addItem(.separator())
            let configMenu = NSMenu()
            addAction(title: "Reload Config", selector: #selector(reloadConfig), to: configMenu)
            addAction(title: "Open Config…", selector: #selector(openConfig), to: configMenu)
            addAction(title: "Reveal Config in Finder", selector: #selector(revealConfig), to: configMenu)
            addSubmenu(title: "Config", submenu: configMenu)

            if #available(macOS 13.0, *) {
                menu.addItem(.separator())
                let login = NSMenuItem(title: "Start at Login",
                                       action: #selector(toggleLaunchAtLogin),
                                       keyEquivalent: "")
                login.target = self
                login.state = LoginItem.isEnabled ? .on : .off
                menu.addItem(login)
            }
        } else {
            // No access → only the warning (clicking it opens System Settings).
            let warn = NSMenuItem(title: "⚠ Grant Accessibility access…", action: #selector(openAccessibility), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        addAction(title: "Quit Shift", selector: #selector(quit), keyEquivalent: "q", to: menu)
    }

    /// A warning item (only when something's wrong) whose submenu lists each
    /// problem with the config or its shortcuts, plus a shortcut to fix it.
    private func addProblemsItem() {
        let problems = Config.shared.current.warnings + HotkeyManager.shared.failures
        let loadError = Config.shared.loadError
        guard loadError != nil || !problems.isEmpty else { return }

        let submenu = NSMenu()
        if let loadError = loadError {
            addInfo(loadError, to: submenu)
            if !problems.isEmpty { submenu.addItem(.separator()) }
        }
        problems.forEach { addInfo($0, to: submenu) }
        submenu.addItem(.separator())
        addAction(title: "Open Config…", selector: #selector(openConfig), to: submenu)

        let title = loadError != nil
            ? "⚠ Config error, using last good config"
            : "⚠ \(problems.count) config \(problems.count == 1 ? "warning" : "warnings")"
        addSubmenu(title: title, submenu: submenu)
        menu.addItem(.separator())
    }

    /// A read-only line of text (enabled so it isn't greyed out, but does nothing).
    private func addInfo(_ text: String, to menu: NSMenu) {
        let item = NSMenuItem(title: text, action: #selector(noop), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func noop() {}

    /// Renders each `category` as a parent menu item whose submenu holds the
    /// positions. Separators between categories come from `MenuLayout`. An
    /// uncategorized config (empty title) is rendered as loose top-level items.
    /// Cycles get their own submenu, just before Displays.
    private func addPositionGroups(_ positions: [Position]) {
        var addedCycles = false
        for section in MenuLayout.sections(for: positions) {
            if section.title == BuiltinPositions.displaysCategory {
                addCycles()
                addedCycles = true
            }
            if section.separatorBefore { menu.addItem(.separator()) }
            if section.title.isEmpty {
                for index in section.positionIndices { addPositionItem(positions[index], index: index, to: menu) }
            } else {
                let submenu = NSMenu()
                for index in section.positionIndices { addPositionItem(positions[index], index: index, to: submenu) }
                addSubmenu(title: section.title, submenu: submenu)
            }
        }
        if !addedCycles { addCycles() }
    }

    private func addCycles() {
        let cycles = Config.shared.current.cycles
        guard !cycles.isEmpty else { return }
        let submenu = NSMenu()
        for (index, cycle) in cycles.enumerated() {
            let suffix = cycle.key.map { "   \(KeyParser.display($0))" } ?? ""
            let item = NSMenuItem(title: cycle.name + suffix, action: #selector(applyCycle(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            submenu.addItem(item)
        }
        addSubmenu(title: "Cycles", submenu: submenu)
    }

    private func addPositionItem(_ position: Position, index: Int, to menu: NSMenu) {
        let suffix = position.key.map { "   \(KeyParser.display($0))" } ?? ""
        let item = NSMenuItem(title: position.name + suffix, action: #selector(applyPosition(_:)), keyEquivalent: "")
        item.target = self
        item.tag = index
        menu.addItem(item)
    }

    private func addSubmenu(title: String, submenu: NSMenu) {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func addAction(title: String, selector: Selector, keyEquivalent: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = self
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func applyPosition(_ sender: NSMenuItem) {
        let positions = Config.shared.current.positions
        guard sender.tag >= 0, sender.tag < positions.count else { return }
        WindowManager.shared.apply(positions[sender.tag])
    }

    @objc private func applyCycle(_ sender: NSMenuItem) {
        let cycles = Config.shared.current.cycles
        guard sender.tag >= 0, sender.tag < cycles.count else { return }
        WindowManager.shared.apply(cycles[sender.tag])
    }

    @objc private func reloadConfig() {
        Config.shared.reload()
        HotkeyManager.shared.reload()
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(Config.fileURL)
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([Config.fileURL])
    }

    @available(macOS 13.0, *)
    @objc private func toggleLaunchAtLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        populate()   // refresh the checkmark
    }

    @objc private func openAccessibility() {
        AccessibilityHelper.shared.requestAccessAndPoll { granted in
            guard granted else { return }
            DispatchQueue.main.async {
                HotkeyManager.shared.start()
                self.populate()
            }
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
