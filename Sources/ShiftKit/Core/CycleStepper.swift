import CoreGraphics

/// Picks which step of a cycle to apply next. Pure, so it's unit-testable.
///
/// There's no per-cycle counter: the window's current frame says where it is.
/// If it sits on one of the steps, move to the one after (wrapping around);
/// otherwise start from the first. `remembered` covers apps that round their
/// size (e.g. Terminal snapping to whole characters) and so never land exactly
/// on a target: it's the step Shift last applied and the frame the window
/// actually ended up with.
enum CycleStepper {
    static func nextIndex(current: CGRect,
                          targets: [CGRect?],
                          remembered: (index: Int, frame: CGRect)? = nil,
                          tolerance: CGFloat = 4) -> Int {
        guard !targets.isEmpty else { return 0 }
        if let r = remembered, r.index < targets.count, current.isClose(to: r.frame, tolerance: tolerance) {
            return (r.index + 1) % targets.count
        }
        if let i = targets.firstIndex(where: { $0.map { current.isClose(to: $0, tolerance: tolerance) } ?? false }) {
            return (i + 1) % targets.count
        }
        return 0
    }
}
