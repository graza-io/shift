import CoreGraphics
@testable import ShiftKit

func runWindowHistoryTests() {
    R.suite("WindowHistory")

    let a = CGRect(x: 0, y: 0, width: 100, height: 100)
    let b = CGRect(x: 100, y: 0, width: 200, height: 100)
    let c = CGRect(x: 0, y: 100, width: 300, height: 300)

    var history = WindowHistory()
    R.ok(history.pop(for: 1) == nil, "nothing to undo → nil")

    history.push(a, for: 1)
    history.push(b, for: 1)
    history.push(c, for: 1)
    R.equal(history.pop(for: 1), c, "steps back: newest first")
    R.equal(history.pop(for: 1), b, "then the one before")
    R.equal(history.pop(for: 1), a, "then the oldest")
    R.ok(history.pop(for: 1) == nil, "then nothing")
    R.ok(history.frames.isEmpty, "empty stacks are dropped")

    history.push(a, for: 1)
    history.push(b, for: 2)
    R.equal(history.pop(for: 2), b, "windows don't share history")
    R.equal(history.pop(for: 1), a, "each window has its own")

    var capped = WindowHistory(limit: 3)
    for i in 0..<5 { capped.push(CGRect(x: CGFloat(i), y: 0, width: 10, height: 10), for: 7) }
    R.equal(capped.frames[7]?.count, 3, "capped at the limit")
    R.equal(capped.pop(for: 7)?.minX, 4, "keeps the newest")
    R.equal(capped.frames[7]?.first?.minX, 2, "oldest ones fell off")

    var pruned = WindowHistory()
    pruned.push(a, for: 1)
    pruned.push(b, for: 2)
    pruned.push(c, for: 3)
    pruned.prune(keeping: [1, 3])
    R.equal(Set(pruned.frames.keys), [1, 3], "closed windows are forgotten")
}
