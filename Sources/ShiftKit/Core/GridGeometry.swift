import Cocoa

/// Pure geometry: maps a `CellRect` to an AppKit-coordinate frame (bottom-left
/// origin, screen-local) within a visible frame. No window APIs are touched here,
/// so this is fully unit-testable.
///
/// The grid uses a TOP-LEFT origin (row 0 = top). Each grid *line* is rounded to
/// a whole pixel and frames are derived from the differences, so adjacent cells
/// tile perfectly with no gaps or overlaps.
enum GridGeometry {
    static func frame(for cell: CellRect,
                      in visibleFrame: CGRect,
                      columns: Int,
                      rows: Int,
                      gap: CGFloat = 0,
                      screenGap: CGFloat = 0) -> CGRect {
        let cols = max(1, columns)
        let rws = max(1, rows)

        // Outer margin first, then divide what's left into cells.
        let vf = screenGap > 0 ? visibleFrame.insetBy(dx: screenGap, dy: screenGap) : visibleFrame

        // Clamp the cell into the grid defensively (bad config shouldn't crash).
        let cx = clamp(cell.x, lo: 0, hi: cols - 1)
        let cy = clamp(cell.y, lo: 0, hi: rws - 1)
        let cw = clamp(cell.w, lo: 1, hi: cols - cx)
        let ch = clamp(cell.h, lo: 1, hi: rws - cy)

        let cellW = vf.width / CGFloat(cols)
        let cellH = vf.height / CGFloat(rws)

        let left   = vf.minX + (cellW * CGFloat(cx)).rounded()
        let right  = vf.minX + (cellW * CGFloat(cx + cw)).rounded()
        // y is measured from the top; AppKit's top edge is maxY.
        let top    = vf.maxY - (cellH * CGFloat(cy)).rounded()
        let bottom = vf.maxY - (cellH * CGFloat(cy + ch)).rounded()

        var rect = CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
        if gap > 0 {
            rect = rect.insetBy(dx: gap / 2, dy: gap / 2)
        }
        return rect
    }

    /// Convenience overload using an `NSScreen` and `GridSettings`.
    static func frame(for cell: CellRect, on screen: NSScreen, settings: GridSettings) -> CGRect {
        frame(for: cell,
              in: screen.visibleFrame,
              columns: settings.columns,
              rows: settings.rows,
              gap: settings.gap,
              screenGap: settings.screenGap)
    }

    // MARK: - Frame → cell

    /// The inverse of `frame(for:)`: the cell whose grid lines are nearest to
    /// `frame`'s edges. Always inside the grid and at least 1×1.
    static func nearestCell(to frame: CGRect,
                            in visibleFrame: CGRect,
                            columns: Int,
                            rows: Int,
                            gap: CGFloat = 0,
                            screenGap: CGFloat = 0) -> CellRect {
        let cols = max(1, columns)
        let rws = max(1, rows)
        let vf = screenGap > 0 ? visibleFrame.insetBy(dx: screenGap, dy: screenGap) : visibleFrame
        // Undo the gap inset so edges line up with grid lines again.
        let f = gap > 0 ? frame.insetBy(dx: -gap / 2, dy: -gap / 2) : frame

        let cellW = vf.width / CGFloat(cols)
        let cellH = vf.height / CGFloat(rws)
        let left   = clamp(Int(((f.minX - vf.minX) / cellW).rounded()), lo: 0, hi: cols - 1)
        let right  = clamp(Int(((f.maxX - vf.minX) / cellW).rounded()), lo: left + 1, hi: cols)
        let top    = clamp(Int(((vf.maxY - f.maxY) / cellH).rounded()), lo: 0, hi: rws - 1)
        let bottom = clamp(Int(((vf.maxY - f.minY) / cellH).rounded()), lo: top + 1, hi: rws)
        return CellRect(x: left, y: top, w: right - left, h: bottom - top)
    }

    /// The cell `frame` is sitting on, if it's within `tolerance` px of one.
    static func cell(matching frame: CGRect, in visibleFrame: CGRect, settings: GridSettings,
                     tolerance: CGFloat = 10) -> CellRect? {
        let cell = nearestCell(to: frame, in: visibleFrame, columns: settings.columns, rows: settings.rows,
                               gap: settings.gap, screenGap: settings.screenGap)
        let snapped = self.frame(for: cell, in: visibleFrame, columns: settings.columns, rows: settings.rows,
                                 gap: settings.gap, screenGap: settings.screenGap)
        return frame.isClose(to: snapped, tolerance: tolerance) ? cell : nil
    }

    // MARK: - Throwing between displays

    /// Where a window lands when it's thrown from one display to another (all
    /// AppKit coords; `source`/`target` are the screens' visible frames).
    /// Maximized stays maximized, a window on a grid cell lands on the same cell,
    /// and anything else keeps its relative position and size, kept on screen.
    static func frameOnOtherDisplay(_ window: CGRect, from source: CGRect, to target: CGRect,
                                    settings: GridSettings, tolerance: CGFloat = 10) -> CGRect {
        let inset = settings.screenGap
        let src = inset > 0 ? source.insetBy(dx: inset, dy: inset) : source
        let dst = inset > 0 ? target.insetBy(dx: inset, dy: inset) : target

        if window.isClose(to: src, tolerance: tolerance) {
            return dst
        }
        if let cell = cell(matching: window, in: source, settings: settings, tolerance: tolerance) {
            return frame(for: cell, in: target, columns: settings.columns, rows: settings.rows,
                         gap: settings.gap, screenGap: settings.screenGap)
        }

        // Free-floating: scale into the target, then keep it fully on screen.
        let width = min((window.width / src.width * dst.width).rounded(), dst.width)
        let height = min((window.height / src.height * dst.height).rounded(), dst.height)
        let x = dst.minX + ((window.minX - src.minX) / src.width * dst.width).rounded()
        let y = dst.minY + ((window.minY - src.minY) / src.height * dst.height).rounded()
        return CGRect(x: min(max(x, dst.minX), dst.maxX - width),
                      y: min(max(y, dst.minY), dst.maxY - height),
                      width: width, height: height)
    }

    private static func clamp(_ v: Int, lo: Int, hi: Int) -> Int {
        max(lo, min(max(lo, hi), v))
    }
}

extension CGRect {
    /// Every edge within `tolerance` px of `other`'s.
    func isClose(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
