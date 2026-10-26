import CoreGraphics

/// Per-window undo stacks for Restore, keyed by CGWindowID. Pure, so it's
/// unit-testable.
struct WindowHistory {
    let limit: Int
    private(set) var frames: [UInt32: [CGRect]] = [:]

    init(limit: Int = 10) {
        self.limit = max(1, limit)
    }

    /// Records where a window was before Shift moved it. Oldest entries fall off
    /// past `limit`.
    mutating func push(_ frame: CGRect, for window: UInt32) {
        var stack = frames[window, default: []]
        stack.append(frame)
        if stack.count > limit { stack.removeFirst(stack.count - limit) }
        frames[window] = stack
    }

    /// The most recent frame for `window`, removed from its history.
    mutating func pop(for window: UInt32) -> CGRect? {
        guard var stack = frames[window], let frame = stack.popLast() else { return nil }
        frames[window] = stack.isEmpty ? nil : stack
        return frame
    }

    /// Drops the history of windows that no longer exist.
    mutating func prune(keeping live: Set<UInt32>) {
        frames = frames.filter { live.contains($0.key) }
    }
}
