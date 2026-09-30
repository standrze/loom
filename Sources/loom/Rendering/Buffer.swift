import weft

/// A rectangular grid of terminal cells with whole-grapheme clipping.
public struct Buffer: Sendable {
    public let width: Int
    public let height: Int

    private var cells: [Cell]

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

    /// Writes a whole grapheme or nothing, preventing half-wide characters at a clip edge.

    public mutating func put(
        _ symbol: String, width span: Int, at point: Point, style: Style = Style(), link: String? = nil
    ) {
        guard symbol.count == 1,
            span == 1 || span == 2,
            area.contains(point),
            point.x + span <= width
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
        guard area.contains(point) else {
            return
        }

        let leadingColumn = self[point.x, point.y].width == 0 ? point.x - 1 : point.x
        guard leadingColumn >= 0 else {
            return
        }

        let span = self[leadingColumn, point.y].width
        for column in leadingColumn..<min(width, leadingColumn + span) {
            cells[point.y * width + column].style.reversed = true
        }
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
