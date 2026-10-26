import CoreGraphics
@testable import ShiftKit

func runGridGeometryTests() {
    R.suite("GridGeometry")

    let vf = CGRect(x: 0, y: 0, width: 2400, height: 1200)  // each cell = 100x100
    func frame(_ x: Int, _ y: Int, _ w: Int, _ h: Int,
               in visible: CGRect? = nil, gap: CGFloat = 0, screenGap: CGFloat = 0) -> CGRect {
        GridGeometry.frame(for: CellRect(x: x, y: y, w: w, h: h),
                           in: visible ?? vf, columns: 24, rows: 12, gap: gap, screenGap: screenGap)
    }

    R.equal(frame(0, 0, 12, 12), CGRect(x: 0, y: 0, width: 1200, height: 1200), "left half")
    R.equal(frame(12, 0, 12, 12), CGRect(x: 1200, y: 0, width: 1200, height: 1200), "right half")

    // Top of screen (row 0) → HIGH y in AppKit coords.
    R.equal(frame(0, 0, 24, 6), CGRect(x: 0, y: 600, width: 2400, height: 600), "top half is upper")
    R.equal(frame(0, 6, 24, 6), CGRect(x: 0, y: 0, width: 2400, height: 600), "bottom half is lower")

    // Quarters tile exactly.
    let tl = frame(0, 0, 12, 6), tr = frame(12, 0, 12, 6)
    let bl = frame(0, 6, 12, 6), br = frame(12, 6, 12, 6)
    R.equal(tl.width + tr.width, vf.width, "quarters cover width")
    R.equal(bl.height + tl.height, vf.height, "quarters cover height")
    R.ok(tl.maxX == tr.minX, "no horizontal gap between quarters")
    R.ok(bl.maxY == tl.minY, "no vertical gap between quarters")
    R.ok(tr.minX == br.minX, "right quarters aligned")

    // Thirds.
    let l = frame(0, 0, 8, 12), c = frame(8, 0, 8, 12), r = frame(16, 0, 8, 12)
    R.equal(l.width + c.width + r.width, vf.width, "thirds cover width")
    R.ok(l.maxX == c.minX && c.maxX == r.minX, "thirds tile with no gaps")

    R.equal(frame(0, 0, 24, 12), vf, "maximize cell fills visible frame")

    // Non-integral width still tiles with no gaps.
    let odd = CGRect(x: 0, y: 0, width: 2401, height: 1200)
    let oLeft = frame(0, 0, 12, 12, in: odd), oRight = frame(12, 0, 12, 12, in: odd)
    R.ok(oLeft.maxX == oRight.minX, "odd width: halves touch")
    R.equal(oLeft.width + oRight.width, odd.width, "odd width: full coverage")

    // Offset visible frame (menu bar / Dock insets).
    let inset = CGRect(x: 100, y: 50, width: 2400, height: 1100)
    R.equal(frame(0, 0, 24, 12, in: inset), inset, "offset frame respects origin")

    // Gaps and outer margin.
    R.equal(frame(0, 0, 12, 12, gap: 20),
            CGRect(x: 0, y: 0, width: 1200, height: 1200).insetBy(dx: 10, dy: 10), "gap insets each window")
    R.equal(frame(0, 0, 24, 12, screenGap: 10), vf.insetBy(dx: 10, dy: 10), "screen_gap adds outer margin")

    // Defensive clamping.
    let clamped = frame(20, 0, 12, 12)
    R.ok(clamped.maxX <= vf.maxX + 0.5 && clamped.minX >= vf.minX - 0.5, "out-of-bounds cell clamps inside grid")

    runFrameToCellTests()
    runDisplayThrowTests()
    runAdjustTests()
}

private func runAdjustTests() {
    R.suite("GridGeometry: move & resize by a cell")

    func adj(_ c: CellRect, _ d: CellDelta) -> CellRect { GridGeometry.adjusted(c, by: d, columns: 24, rows: 12) }
    let mid = CellRect(x: 6, y: 3, w: 8, h: 4)

    R.equal(adj(mid, CellDelta(dx: -1)), CellRect(x: 5, y: 3, w: 8, h: 4), "move left")
    R.equal(adj(mid, CellDelta(dx: 1)), CellRect(x: 7, y: 3, w: 8, h: 4), "move right")
    R.equal(adj(mid, CellDelta(dy: -1)), CellRect(x: 6, y: 2, w: 8, h: 4), "move up")
    R.equal(adj(mid, CellDelta(dy: 1)), CellRect(x: 6, y: 4, w: 8, h: 4), "move down")
    R.equal(adj(mid, CellDelta(dw: 1)), CellRect(x: 6, y: 3, w: 9, h: 4), "grow width pushes the right edge")
    R.equal(adj(mid, CellDelta(dw: -1)), CellRect(x: 6, y: 3, w: 7, h: 4), "shrink width")
    R.equal(adj(mid, CellDelta(dh: 1)), CellRect(x: 6, y: 3, w: 8, h: 5), "grow height pushes the bottom edge")
    R.equal(adj(mid, CellDelta(dh: -1)), CellRect(x: 6, y: 3, w: 8, h: 3), "shrink height")

    // Edges.
    let leftHalf = CellRect(x: 0, y: 0, w: 12, h: 12)
    R.equal(adj(leftHalf, CellDelta(dx: -1)), leftHalf, "can't move past the left edge")
    R.equal(adj(leftHalf, CellDelta(dy: 1)), leftHalf, "full height can't move down")
    let rightHalf = CellRect(x: 12, y: 0, w: 12, h: 12)
    R.equal(adj(rightHalf, CellDelta(dx: 1)), rightHalf, "can't move past the right edge")
    R.equal(adj(rightHalf, CellDelta(dw: 1)), CellRect(x: 11, y: 0, w: 13, h: 12),
            "at the right edge, grow width grows leftwards")
    R.equal(adj(CellRect(x: 0, y: 8, w: 24, h: 4), CellDelta(dh: 1)), CellRect(x: 0, y: 7, w: 24, h: 5),
            "at the bottom edge, grow height grows upwards")
    let full = CellRect(x: 0, y: 0, w: 24, h: 12)
    R.equal(adj(full, CellDelta(dw: 1, dh: 1)), full, "full screen can't grow")

    // Minimum size.
    let tiny = CellRect(x: 3, y: 3, w: 1, h: 1)
    R.equal(adj(tiny, CellDelta(dw: -1, dh: -1)), tiny, "never smaller than one cell")

    // Off-grid window: snap to the nearest cell first, then nudge.
    let vf = CGRect(x: 0, y: 0, width: 2400, height: 1200)
    let snapped = GridGeometry.nearestCell(to: CGRect(x: 130, y: 640, width: 940, height: 470), in: vf,
                                           columns: 24, rows: 12)
    R.equal(adj(snapped, CellDelta(dx: 1)), CellRect(x: 2, y: 1, w: 10, h: 5), "off-grid snaps then moves")
}

private func runFrameToCellTests() {
    R.suite("GridGeometry: frame → cell")

    let vf = CGRect(x: 0, y: 0, width: 2400, height: 1200)  // each cell = 100x100
    func nearest(_ f: CGRect, gap: CGFloat = 0, screenGap: CGFloat = 0) -> CellRect {
        GridGeometry.nearestCell(to: f, in: vf, columns: 24, rows: 12, gap: gap, screenGap: screenGap)
    }

    // Round-trips every built-in exactly.
    for spec in BuiltinPositions.specs {
        guard case .cell(let cell) = spec.kind else { continue }
        let f = GridGeometry.frame(for: cell, in: vf, columns: 24, rows: 12)
        R.equal(nearest(f), cell, "\(spec.code) round-trips")
        let g = GridGeometry.frame(for: cell, in: vf, columns: 24, rows: 12, gap: 16, screenGap: 12)
        R.equal(nearest(g, gap: 16, screenGap: 12), cell, "\(spec.code) round-trips with gaps")
    }

    R.equal(nearest(CGRect(x: 130, y: 640, width: 940, height: 470)), CellRect(x: 1, y: 1, w: 10, h: 5),
            "off-grid frame snaps to nearest lines")
    R.equal(nearest(CGRect(x: 1210, y: 0, width: 20, height: 20)).w, 1, "tiny window still at least 1 cell")
    R.equal(nearest(CGRect(x: -500, y: -500, width: 4000, height: 4000)), CellRect(x: 0, y: 0, w: 24, h: 12),
            "oversized window clamps to the grid")

    let settings = GridSettings()
    R.equal(GridGeometry.cell(matching: CGRect(x: 0, y: 0, width: 1195, height: 1200), in: vf, settings: settings),
            CellRect(x: 0, y: 0, w: 12, h: 12), "within tolerance matches (e.g. Terminal rounding)")
    R.ok(GridGeometry.cell(matching: CGRect(x: 130, y: 640, width: 940, height: 470), in: vf, settings: settings) == nil,
         "free-floating window matches no cell")
}

private func runDisplayThrowTests() {
    R.suite("GridGeometry: display throws")

    let landscape = CGRect(x: 0, y: 0, width: 2400, height: 1200)
    let portrait = CGRect(x: 2400, y: -600, width: 1200, height: 2400)  // to the right, taller
    let small = CGRect(x: -1200, y: 0, width: 1200, height: 600)
    let settings = GridSettings()
    func thrown(_ w: CGRect, _ from: CGRect, _ to: CGRect, _ s: GridSettings = GridSettings()) -> CGRect {
        GridGeometry.frameOnOtherDisplay(w, from: from, to: to, settings: s)
    }
    func cellFrame(_ c: CellRect, _ screen: CGRect, _ s: GridSettings = GridSettings()) -> CGRect {
        GridGeometry.frame(for: c, in: screen, columns: 24, rows: 12, gap: s.gap, screenGap: s.screenGap)
    }

    let leftHalf = CellRect(x: 0, y: 0, w: 12, h: 12)
    R.equal(thrown(cellFrame(leftHalf, landscape), landscape, portrait), cellFrame(leftHalf, portrait),
            "left half stays left half (landscape → portrait)")
    let topRight = CellRect(x: 12, y: 0, w: 12, h: 6)
    R.equal(thrown(cellFrame(topRight, portrait), portrait, small), cellFrame(topRight, small),
            "top right quarter stays put (portrait → small)")

    R.equal(thrown(landscape, landscape, portrait), portrait, "maximized stays maximized")

    var gappy = settings
    gappy.gap = 20
    gappy.screenGap = 10
    R.equal(thrown(landscape.insetBy(dx: 10, dy: 10), landscape, small, gappy), small.insetBy(dx: 10, dy: 10),
            "maximized with screen_gap keeps the margin")
    R.equal(thrown(cellFrame(leftHalf, landscape, gappy), landscape, small, gappy), cellFrame(leftHalf, small, gappy),
            "grid position with gaps keeps the gaps")

    // Free-floating: 10% from the left, 25% wide etc. on a 2400×1200 screen.
    let floating = CGRect(x: 240, y: 300, width: 650, height: 450)
    R.equal(thrown(floating, landscape, small), CGRect(x: -1080, y: 150, width: 325, height: 225),
            "free window keeps relative position and size")

    // Hanging off the right edge of the source: it gets pulled fully on screen.
    let offEdge = CGRect(x: 2150, y: 130, width: 650, height: 450)
    R.ok(GridGeometry.cell(matching: offEdge, in: landscape, settings: settings) == nil, "really is free-floating")
    let result = thrown(offEdge, landscape, small)
    R.ok(small.contains(result), "stays fully on the target screen, got \(result)")
    R.equal(result.maxX, small.maxX, "pushed back to the right edge")
}
