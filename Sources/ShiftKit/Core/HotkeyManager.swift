import Cocoa
import Carbon

/// Registers one global Carbon hotkey per keyed position or cycle and dispatches presses.
/// Re-registers from the current config on reload.
final class HotkeyManager {
    static let shared = HotkeyManager()
    private init() {}

    private var hotkeyRefs: [EventHotKeyRef] = []
    private enum Action {
        case position(Position)
        case cycle(Cycle)
    }

    private var actionMap: [UInt32: Action] = [:]
    private var nextID: UInt32 = 1
    private var started = false
    private var handlerInstalled = false
    private var lastEventTime: UInt64 = 0
    /// Shortcuts that couldn't be registered last time (shown in the menu).
    private(set) var failures: [String] = []

    func start() {
        guard !started else { return }
        started = true
        if !handlerInstalled {
            installEventHandler()
            handlerInstalled = true
        }
        register()
    }

    func stop() {
        guard started else { return }
        started = false
        unregister()
    }

    func reload() {
        guard started else { return }
        unregister()
        register()
    }

    // MARK: - Registration

    private func register() {
        let config = Config.shared.current
        for position in config.positions {
            guard let key = position.key else { continue }
            register(key, for: .position(position), name: position.name, code: position.code)
        }
        for cycle in config.cycles {
            guard let key = cycle.key else { continue }
            register(key, for: .cycle(cycle), name: cycle.name, code: cycle.code)
        }
        FileLog.write("registered \(hotkeyRefs.count) hotkeys")
    }

    private func register(_ key: Keybinding, for action: Action, name: String, code: String) {
        let id = nextID
        nextID += 1
        actionMap[id] = action

        let hotkeyID = EventHotKeyID(signature: OSType(0x53484654 /* 'SHFT' */), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(key.keyCode, key.modifiers, hotkeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            hotkeyRefs.append(ref)
        } else {
            failures.append("\(KeyParser.display(key)) for \(name) didn't work, macOS or another app is already using it")
            FileLog.write("FAILED to register \(code) (\(key.raw)) status=\(status) — key may be taken by the system or another app")
        }
    }

    private func unregister() {
        for ref in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
        actionMap.removeAll()
        failures.removeAll()
        nextID = 1
    }

    // MARK: - Carbon event handler

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async {
                HotkeyManager.shared.handle(id: hotKeyID.id)
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
    }

    private func handle(id: UInt32) {
        guard let action = actionMap[id] else { return }
        // Debounce duplicate events (~50ms).
        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastEventTime < 50_000_000 { return }
        lastEventTime = now
        switch action {
        case .position(let position): WindowManager.shared.apply(position)
        case .cycle(let cycle):       WindowManager.shared.apply(cycle)
        }
    }
}
