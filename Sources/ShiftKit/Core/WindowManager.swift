import Cocoa
import ApplicationServices

private let kAXEnhancedUserInterface = "AXEnhancedUserInterface" as CFString

// Private but long-stable (Rectangle, Amethyst and yabai all rely on it): the
// CGWindowID behind an AX window. Looked up at runtime so a missing symbol just
// means falling back to matching windows by position.
private typealias AXUIElementGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private let _AXUIElementGetWindow: AXUIElementGetWindowFunc? = {
    guard let s = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, "_AXUIElementGetWindow") else { return nil }
    return unsafeBitCast(s, to: AXUIElementGetWindowFunc.self)
}()

/// Moves/resizes the focused window. Window detection and the SkyLight fallback
/// are adapted from Nudge (which handles AX-less apps like Electron/Catalyst).
final class WindowManager {
    static let shared = WindowManager()
    private init() {}

    /// Where each window was before Shift moved it, newest last (for Restore).
    private var history = WindowHistory()
    /// Per window: the cycle step Shift last applied and the frame it ended up with.
    private var cycleMemory: [CGWindowID: (cycle: String, index: Int, frame: CGRect)] = [:]

    // MARK: - Entry point

    func apply(_ position: Position) {
        if let window = getFocusedWindow() {
            applyToAXWindow(window, position: position)
            return
        }
        skyLightFallback(position)
    }

    /// Applies the next step of `cycle` to the focused window (see `CycleStepper`).
    func apply(_ cycle: Cycle) {
        guard let first = cycle.steps.first else { return }
        guard let window = getFocusedWindow(), let frame = getFrame(of: window) else {
            // AX-less app: we can't read where it is, so just snap to the first step.
            skyLightFallback(first)
            return
        }
        let screen = DisplayHelper.shared.currentScreen(for: frame)
        let targets = cycle.steps.map { step in
            targetFrame(for: step.kind, on: screen, current: frame).map { convertToCG(nsFrame: $0, screen: screen) }
        }
        let memory = windowID(of: window).flatMap { cycleMemory[$0] }
        let remembered = memory.flatMap { $0.cycle == cycle.code ? (index: $0.index, frame: $0.frame) : nil }
        let index = CycleStepper.nextIndex(current: frame, targets: targets, remembered: remembered)

        applyToAXWindow(window, position: cycle.steps[index])
        if let id = windowID(of: window), let newFrame = getFrame(of: window) {
            cycleMemory[id] = (cycle.code, index, newFrame)
        }
    }

    // MARK: - Target frame (NS coordinates)

    /// AppKit-coordinate target frame for frame-producing kinds, else nil.
    /// `current` is the window's frame (CG coords), which `.adjust` starts from.
    private func targetFrame(for kind: PositionKind, on screen: NSScreen, current: CGRect) -> CGRect? {
        let settings = Config.shared.current.settings
        switch kind {
        case .cell(let cell):
            return GridGeometry.frame(for: cell, on: screen, settings: settings)
        case .maximize:
            let vf = screen.visibleFrame
            return settings.screenGap > 0 ? vf.insetBy(dx: settings.screenGap, dy: settings.screenGap) : vf
        case .adjust(let delta):
            let cell = GridGeometry.nearestCell(to: convertToNS(cgFrame: current), in: screen.visibleFrame,
                                                columns: settings.columns, rows: settings.rows,
                                                gap: settings.gap, screenGap: settings.screenGap)
            let target = GridGeometry.adjusted(cell, by: delta, columns: settings.columns, rows: settings.rows)
            return GridGeometry.frame(for: target, on: screen, settings: settings)
        default:
            return nil
        }
    }

    // MARK: - AX path

    private func applyToAXWindow(_ window: AXUIElement, position: Position) {
        guard let currentFrame = getFrame(of: window) else { return }
        let screen = DisplayHelper.shared.currentScreen(for: currentFrame)

        switch position.kind {
        case .restore:
            restoreWindow(window)
        case .center:
            center(window: window, on: screen)
        case .nextDisplay:
            moveToDisplay(window: window, from: screen, next: true)
        case .previousDisplay:
            moveToDisplay(window: window, from: screen, next: false)
        case .cell, .maximize, .adjust:
            guard let nsFrame = targetFrame(for: position.kind, on: screen, current: currentFrame) else { return }
            move(window: window, to: convertToCG(nsFrame: nsFrame, screen: screen))
        }
    }

    // MARK: - SkyLight fallback (AX-less apps)

    private func skyLightFallback(_ position: Position) {
        guard SkyLight.isAvailable,
              let frontApp = NSWorkspace.shared.frontmostApplication else {
            FileLog.write("apply: no focused window and SkyLight unavailable")
            return
        }
        let pid = frontApp.processIdentifier
        guard let result = SkyLight.findMainWindowWithBounds(pid: pid) else {
            FileLog.write("apply: SkyLight found no window for \(frontApp.localizedName ?? "?")")
            return
        }
        let screen = DisplayHelper.shared.currentScreen(for: result.bounds)

        // The move comes from SkyLight; the resize via AX on the PID's focused window.
        func setFrame(_ frame: CGRect) {
            _ = SkyLight.moveWindow(windowID: result.wid, to: frame.origin)
            let axApp = AXUIElementCreateApplication(pid)
            var fw: AnyObject?
            if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &fw) == .success,
               let axWin = fw as! AXUIElement? {
                setSize(of: axWin, to: frame.size)
            }
        }

        switch position.kind {
        case .cell, .maximize, .adjust:
            guard let nsFrame = targetFrame(for: position.kind, on: screen, current: result.bounds) else { return }
            let cgFrame = convertToCG(nsFrame: nsFrame, screen: screen)
            remember(result.bounds, for: result.wid, unless: cgFrame)
            setFrame(cgFrame)
        case .restore:
            if let frame = history.pop(for: result.wid) { setFrame(frame) }
        default:
            FileLog.write("apply: '\(position.code)' not supported via SkyLight fallback")
        }
    }

    // MARK: - Special actions

    private func center(window: AXUIElement, on screen: NSScreen) {
        guard let size = getSize(of: window), let currentFrame = getFrame(of: window) else { return }
        let screenCG = convertToCG(nsFrame: screen.visibleFrame, screen: screen)
        let cgX = screenCG.minX + (screenCG.width - size.width) / 2
        let cgY = screenCG.minY + (screenCG.height - size.height) / 2
        let target = CGRect(x: cgX, y: cgY, width: size.width, height: size.height)
        if let id = windowID(of: window) { remember(currentFrame, for: id, unless: target) }
        setPosition(of: window, to: target.origin)
    }

    private func moveToDisplay(window: AXUIElement, from currentScreen: NSScreen, next: Bool) {
        guard let target = next ? DisplayHelper.shared.nextScreen(from: currentScreen)
                                 : DisplayHelper.shared.previousScreen(from: currentScreen),
              let frame = getFrame(of: window) else { return }
        let nsFrame = GridGeometry.frameOnOtherDisplay(convertToNS(cgFrame: frame),
                                                       from: currentScreen.visibleFrame,
                                                       to: target.visibleFrame,
                                                       settings: Config.shared.current.settings)
        move(window: window, to: convertToCG(nsFrame: nsFrame, screen: target))
    }

    // MARK: - Restore

    /// Steps the window back one move. Does nothing when there's nothing to undo.
    func restoreWindow(_ window: AXUIElement) {
        guard let id = windowID(of: window), let frame = history.pop(for: id) else { return }
        setFrame(of: window, to: frame)
    }

    /// Records `frame` in the window's history, unless the move won't actually
    /// change anything (so pressing the same shortcut twice doesn't need two
    /// Restores to undo). Also forgets windows that have since closed.
    private func remember(_ frame: CGRect, for id: CGWindowID, unless target: CGRect) {
        guard !frame.isClose(to: target, tolerance: 2) else { return }
        history.push(frame, for: id)

        let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let live = Set(all.compactMap { ($0[kCGWindowNumber as String] as? Int).map(CGWindowID.init) })
        history.prune(keeping: live)
        cycleMemory = cycleMemory.filter { live.contains($0.key) }
    }

    // MARK: - Focused window detection (adapted from Nudge)

    func getFocusedWindow() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)

        let pid: pid_t
        let appElement: AXUIElement
        if appResult == .success, let app = focusedApp {
            let axApp = app as! AXUIElement
            var p: pid_t = 0
            AXUIElementGetPid(axApp, &p)
            pid = p
            appElement = axApp
        } else if let frontApp = NSWorkspace.shared.frontmostApplication {
            pid = frontApp.processIdentifier
            appElement = AXUIElementCreateApplication(pid)
        } else {
            return nil
        }

        if let window = axWindow(from: appElement) { return window }
        if appResult == .success, let window = axWindow(from: AXUIElementCreateApplication(pid)) { return window }
        return windowViaCGWindowList(pid: pid)
    }

    private func axWindow(from appElement: AXUIElement) -> AXUIElement? {
        var fw: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &fw) == .success,
           let w = fw as! AXUIElement?, getPosition(of: w) != nil {
            return w
        }
        var mw: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mw) == .success,
           let w = mw as! AXUIElement?, getPosition(of: w) != nil {
            return w
        }
        var wl: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &wl) == .success,
           let windows = wl as? [AXUIElement] {
            for w in windows where getPosition(of: w) != nil && getSize(of: w) != nil {
                return w
            }
        }
        return nil
    }

    private func windowViaCGWindowList(pid: pid_t) -> AXUIElement? {
        let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var targetBounds: CGRect?
        for info in all {
            guard let wPid = info[kCGWindowOwnerPID as String] as? pid_t, wPid == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let w = bounds["Width"] ?? 0, h = bounds["Height"] ?? 0
            if w > 50 && h > 50 {
                targetBounds = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: w, height: h)
                break
            }
        }
        guard let target = targetBounds else { return nil }

        let pidApp = AXUIElementCreateApplication(pid)
        var wl: AnyObject?
        guard AXUIElementCopyAttributeValue(pidApp, kAXWindowsAttribute as CFString, &wl) == .success,
              let windows = wl as? [AXUIElement] else { return nil }
        for w in windows {
            guard let pos = getPosition(of: w), let size = getSize(of: w) else { continue }
            if abs(pos.x - target.origin.x) < 10 && abs(pos.y - target.origin.y) < 10 &&
               abs(size.width - target.width) < 10 && abs(size.height - target.height) < 10 {
                return w
            }
        }
        for w in windows where getPosition(of: w) != nil && getSize(of: w) != nil { return w }
        return nil
    }

    // MARK: - Get/set frame

    func getFrame(of window: AXUIElement) -> CGRect? {
        guard let position = getPosition(of: window), let size = getSize(of: window) else { return nil }
        return CGRect(origin: position, size: size)
    }

    func getPosition(of window: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    func getSize(of window: AXUIElement) -> CGSize? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success else { return nil }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }

    func setPosition(of window: AXUIElement, to point: CGPoint) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    func setSize(of window: AXUIElement, to size: CGSize) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    func move(window: AXUIElement, to frame: CGRect) {
        if let currentFrame = getFrame(of: window), let id = windowID(of: window) {
            remember(currentFrame, for: id, unless: frame)
        }
        setFrame(of: window, to: frame)
    }

    private func setFrame(of window: AXUIElement, to frame: CGRect) {
        disableEnhancedUI(for: window)
        setPosition(of: window, to: frame.origin)
        setSize(of: window, to: frame.size)
        // Re-apply position: some apps clamp position to old size before resizing.
        setPosition(of: window, to: frame.origin)
    }

    /// Chrome/Chromium animate AX moves when AXEnhancedUserInterface is on; disable it.
    private func disableEnhancedUI(for window: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return }
        let app = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXEnhancedUserInterface, &value) == .success,
              let enabled = value as? NSNumber, enabled.boolValue else { return }
        AXUIElementSetAttributeValue(app, kAXEnhancedUserInterface, kCFBooleanFalse)
    }

    // MARK: - Window ID + coordinates

    /// The window's CGWindowID: stable while it moves and unique per window.
    /// nil if it can't be pinned down (then nothing is recorded for it, rather
    /// than risking mixing it up with another window).
    private func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        if let fn = _AXUIElementGetWindow, fn(window, &id) == .success, id != 0 { return id }

        // Fallback: match by owner and position among on-screen windows.
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard let position = getPosition(of: window) else { return nil }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard let wPid = info[kCGWindowOwnerPID as String] as? pid_t, wPid == pid,
                  let wNumber = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            if abs((bounds["X"] ?? 0) - position.x) < 5 && abs((bounds["Y"] ?? 0) - position.y) < 5 {
                return CGWindowID(wNumber)
            }
        }
        return nil
    }

    /// Convert an AppKit (bottom-left origin) frame to CoreGraphics/AX (top-left origin).
    func convertToCG(nsFrame: CGRect, screen: NSScreen) -> CGRect {
        guard let mainScreen = NSScreen.screens.first else { return nsFrame }
        let cgY = mainScreen.frame.height - nsFrame.maxY
        return CGRect(x: nsFrame.minX, y: cgY, width: nsFrame.width, height: nsFrame.height)
    }

    /// Convert a CoreGraphics/AX (top-left origin) frame to AppKit (bottom-left origin).
    func convertToNS(cgFrame: CGRect) -> CGRect {
        guard let mainScreen = NSScreen.screens.first else { return cgFrame }
        let nsY = mainScreen.frame.height - cgFrame.maxY
        return CGRect(x: cgFrame.minX, y: nsY, width: cgFrame.width, height: cgFrame.height)
    }
}
