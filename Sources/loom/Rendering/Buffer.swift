import weft

/// A rectangular grid of terminal cells with whole-grapheme clipping.
public struct Buffer: Sendable {
    public let width: Int
    public let height: Int

    private var cells: [Cell]
    private var clip: Rect

    public var area: Rect {
        Rect(width: width, height: height)
    }

    /// The visible symbols, with explicit newlines between buffer rows.
    public var plainText: String {
        (0..<height).map {
            row in
            (0..<width).map {
                column in
                self[column, row].symbol
            }.joined()
        }.joined(separator: "\n")
    }

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.cells = Array(repeating: Cell(), count: self.width * self.height)
        self.clip = Rect(width: self.width, height: self.height)
    }

    /// Accesses a cell at valid, zero-based buffer coordinates.

    public subscript(x: Int, y: Int) -> Cell {
        cells[y * width + x]
    }

    /// Clears every cell while retaining the allocated buffer.

    public mutating func reset() {
        for index in cells.indices {
            cells[index] = Cell()
        }
    }

    /// Restricts writes to the intersection of this area and any enclosing clip.
    ///
    /// Coordinates remain absolute. Whole graphemes crossing an edge are omitted.
    public mutating func withClip(_ area: Rect, _ draw: (inout Buffer) -> Void) {
        let previous = clip
        let left = min(clip.maxX, max(clip.x, area.x))
        let top = min(clip.maxY, max(clip.y, area.y))
        let right = max(left, min(clip.maxX, regionEnd(area.x, length: area.width)))
        let bottom = max(top, min(clip.maxY, regionEnd(area.y, length: area.height)))
        clip = Rect(x: left, y: top, width: right - left, height: bottom - top)
        defer { clip = previous }
        draw(&self)
    }

    /// Writes a whole grapheme or nothing, preventing half-wide characters at a clip edge.

    public mutating func put(
        _ symbol: String, width span: Int, at point: Point, style: Style = Style(), link: String? = nil
    ) {
        guard symbol.count == 1,
            span == 1 || span == 2,
            clip.contains(point),
            point.x + span <= clip.maxX
        else {
            return
        }

        // Widget content must not inject terminal controls into the output stream.
        guard
            !symbol.unicodeScalars.contains(where: {
                $0.value < 32 || (0x7f...0x9f).contains($0.value)
            })
        else {
            return
        }

        // Replacing part of an existing wide glyph must not erase cells outside
        // the current clip. Leave the crossing glyph intact instead.
        for column in point.x..<point.x + span {
            let occupant = cells[point.y * width + column]
            let leading = occupant.width == 0 ? column - 1 : column
            guard leading >= clip.x else { return }
            let occupantWidth = cells[point.y * width + leading].width
            guard leading + occupantWidth <= clip.maxX else { return }
        }
        for column in point.x..<point.x + span {
            clearOccupant(x: column, y: point.y)
        }

        let index = point.y * width + point.x
        cells[index] = Cell(symbol: symbol, width: span, style: style, link: link)
        if span == 2 {
            cells[index + 1] = Cell(symbol: "", width: 0, style: style, link: link)
        }
    }

    /// Highlights the entire grapheme occupying the selected cell.

    public mutating func highlight(at point: Point) {
        guard clip.contains(point) else {
            return
        }

        let leadingColumn = self[point.x, point.y].width == 0 ? point.x - 1 : point.x
        guard leadingColumn >= 0 else {
            return
        }

        let span = self[leadingColumn, point.y].width
        guard leadingColumn >= clip.x, leadingColumn + span <= clip.maxX else { return }
        for column in leadingColumn..<min(width, leadingColumn + span) {
            cells[point.y * width + column].style.reversed = true
        }
    }

    /// Fills complete glyphs inside the region and current clip.
    ///
    /// Invalid symbols are rejected by `put`.
    public mutating func fill(
        _ region: Rect, symbol: String = " ", width span: Int = 1,
        style: Style = Style(), link: String? = nil
    ) {
        guard span == 1 || span == 2 else { return }
        withClip(region) { buffer in
            for y in buffer.clip.y..<buffer.clip.maxY {
                for x in stride(from: buffer.clip.x, to: buffer.clip.maxX, by: span) {
                    buffer.put(symbol, width: span, at: Point(x: x, y: y), style: style, link: link)
                }
            }
        }
    }

    /// Clears complete glyphs inside the region and current clip.
    public mutating func clear(_ region: Rect) {
        fill(region)
    }

    /// Applies appearance changes only to complete glyphs inside the region and current clip.
    public mutating func apply(_ patch: StylePatch, to region: Rect) {
        withClip(region) { buffer in
            for y in buffer.clip.y..<buffer.clip.maxY {
                for x in buffer.clip.x..<buffer.clip.maxX {
                    let cell = buffer[x, y]
                    guard cell.width > 0, x + cell.width <= buffer.clip.maxX else { continue }
                    let style = cell.style.applying(patch)
                    for column in x..<x + cell.width {
                        buffer.cells[y * buffer.width + column].style = style
                    }
                }
            }
        }
    }

    /// Copies complete source glyphs to a destination origin, retaining styles and links.
    ///
    /// Value semantics make copies from this buffer safe even when source and destination overlap.
    public mutating func copy(from source: Buffer, region: Rect, to destination: Point) {
        let left = max(0, region.x)
        let top = max(0, region.y)
        let right = min(source.width, regionEnd(region.x, length: region.width))
        let bottom = min(source.height, regionEnd(region.y, length: region.height))
        guard left < right, top < bottom else { return }
        for y in top..<bottom {
            for x in left..<right {
                let cell = source[x, y]
                guard cell.width > 0, x + cell.width <= right else { continue }
                let dx = x.subtractingReportingOverflow(region.x)
                let dy = y.subtractingReportingOverflow(region.y)
                guard !dx.overflow, !dy.overflow else { continue }
                let targetX = destination.x.addingReportingOverflow(dx.partialValue)
                let targetY = destination.y.addingReportingOverflow(dy.partialValue)
                guard !targetX.overflow, !targetY.overflow else { continue }
                put(
                    cell.symbol, width: cell.width, at: Point(x: targetX.partialValue, y: targetY.partialValue),
                    style: cell.style, link: cell.link)
            }
        }
    }

    /// Composes the complete source grid at the supplied destination origin.
    public mutating func compose(_ source: Buffer, at destination: Point = Point(x: 0, y: 0)) {
        copy(from: source, region: source.area, to: destination)
    }

    /// Returns a resized grid, optionally retaining complete glyphs in the shared area.
    public func resized(width: Int, height: Int, preservingContents: Bool = true) -> Buffer {
        var result = Buffer(width: width, height: height)
        if preservingContents { result.compose(self) }
        return result
    }

    /// Resizes the grid.
    ///
    /// Existing glyphs crossing the new edge are omitted.
    public mutating func resize(width: Int, height: Int, preservingContents: Bool = true) {
        self = resized(width: width, height: height, preservingContents: preservingContents)
    }

    /// Returns cell-level changes, including removed cells and wide-glyph continuation cells.
    public func differences(from previous: Buffer) -> [BufferDifference] {
        var result: [BufferDifference] = []
        for y in 0..<max(height, previous.height) {
            for x in 0..<max(width, previous.width) {
                let before = x < previous.width && y < previous.height ? previous[x, y] : nil
                let after = x < width && y < height ? self[x, y] : nil
                if before != after {
                    result.append(BufferDifference(point: Point(x: x, y: y), before: before, after: after))
                }
            }
        }
        return result
    }

    /// Mutable rectangles may have negative lengths or an unrepresentable far edge.
    private func regionEnd(_ origin: Int, length: Int) -> Int {
        let end = origin.addingReportingOverflow(max(0, length))
        return end.overflow ? Int.max : end.partialValue
    }

    private mutating func clearOccupant(x: Int, y: Int) {
        let index = y * width + x
        if cells[index].width == 0 && x > 0 {
            cells[index - 1] = Cell()
        }
        if cells[index].width == 2 && x + 1 < width {
            cells[index + 1] = Cell()
        }
        cells[index] = Cell()
    }
}
