import Foundation
import weft

/// Encodes semantic rendering operations as ANSI bytes for a weft output sink.
public struct ANSIRenderBackend<B: Backend>: RenderBackend {
    public private(set) var backend: B
    private var diff: CellDiff

    public init(
        backend: B, synchronizedOutput: Bool = true,
        colorDepth: TerminalColorDepth = .trueColor, hyperlinks: Bool = false
    ) {
        self.backend = backend
        diff = CellDiff(synchronizedOutput: synchronizedOutput, colorDepth: colorDepth, hyperlinks: hyperlinks)
    }

    public mutating func reset() { diff.reset() }

    public mutating func render(_ update: RenderUpdate) throws -> RenderStats {
        do {
            switch update {
            case let .frame(presentation): return try present(presentation)
            case let .insertion(insertion): return try insert(insertion)
            }
        } catch {
            diff.reset()
            throw error
        }
    }

    private mutating func present(_ value: RenderPresentation) throws -> RenderStats {
        var prefix = value.clears.map { boundedClear($0, size: value.terminalSize) }.joined()
        if let anchor = value.anchor,
            value.terminalSize.width > 0, value.terminalSize.height > 0, value.area.height > 0
        {
            let point = Point(
                x: min(value.terminalSize.width - 1, max(0, anchor.x)),
                y: min(value.terminalSize.height - 1, max(0, anchor.y)))
            prefix +=
                move(point) + (anchor.x > 0 ? "\r\n" : "")
                + String(repeating: "\n", count: max(0, value.area.height - 1))
        }
        // Explicit clears invalidate both logical equality and cached physical occupancy.
        // A full repaint of the retained area restores cells affected by those clears.
        if !value.clears.isEmpty || value.anchor != nil { diff.reset() }
        let (data, stats) = diff.encode(
            value.next.buffer, previous: value.clears.isEmpty && value.anchor == nil ? value.previous?.buffer : nil,
            cursor: value.next.cursor,
            origin: Point(x: value.area.x, y: value.area.y),
            clearScreen: value.clearScreen && value.clears.isEmpty && value.anchor == nil)
        var output = Data(prefix.utf8)
        output.append(data)
        if !output.isEmpty { try backend.write(output) }
        return RenderStats(changedCells: stats.changedCells, bytes: output.count)
    }

    private mutating func insert(_ value: RenderInsertion) throws -> RenderStats {
        var output = boundedClear(value.oldArea, size: value.terminalSize)
        var physicalRow = value.oldArea.y
        var rowDiff = diff
        rowDiff.reset()
        rowDiff.synchronizedOutput = false
        for row in 0..<value.content.height {
            var line = Buffer(width: value.terminalSize.width, height: 1)
            line.copy(
                from: value.content, region: Rect(y: row, width: value.content.width, height: 1),
                to: Point(x: 0, y: 0))
            let (bytes, _) = rowDiff.encode(
                line, previous: nil, cursor: nil, origin: Point(x: 0, y: physicalRow), clearScreen: false)
            output += String(decoding: bytes, as: UTF8.self)
            output += move(Point(x: 0, y: physicalRow)) + "\r\n"
            physicalRow = min(value.terminalSize.height - 1, physicalRow + 1)
        }
        output +=
            move(Point(x: 0, y: physicalRow))
            + String(repeating: "\n", count: max(0, value.oldArea.height - 1))
        var repaintDiff = diff
        repaintDiff.reset()
        let (repaint, stats) = repaintDiff.encode(
            value.retained.buffer, previous: nil, cursor: value.retained.cursor,
            origin: Point(x: value.newArea.x, y: value.newArea.y), clearScreen: false)
        var bytes = Data(output.utf8)
        bytes.append(repaint)
        try backend.write(bytes)
        diff = repaintDiff
        return RenderStats(changedCells: stats.changedCells, bytes: bytes.count)
    }

    private func boundedClear(_ area: Rect, size: RenderSize) -> String {
        let left = min(size.width, max(0, area.x))
        let top = min(size.height, max(0, area.y))
        let right = min(size.width, max(left, area.maxX))
        let bottom = min(size.height, max(top, area.maxY))
        guard right > left, bottom > top else { return "" }
        return "\u{1b}[0m"
            + (top..<bottom).map {
                move(Point(x: left, y: $0)) + String(repeating: " ", count: right - left)
            }.joined()
    }

    private func move(_ point: Point) -> String {
        "\u{1b}[\(point.y + 1);\(point.x + 1)H"
    }
}
