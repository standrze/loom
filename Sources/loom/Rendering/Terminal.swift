import Foundation
import weft

/// Ratatui-style immediate rendering: draw a complete logical frame; emit just its cell diff.
public struct Terminal<B: Backend> {
    public private(set) var backend: B
    private var front: Buffer
    private var frame: Frame
    private var presented = false
    private var diff: CellDiff

    public init(
        backend: B, width: Int, height: Int, synchronizedOutput: Bool = true,
        colorDepth: TerminalColorDepth = .trueColor, hyperlinks: Bool = false
    ) {
        self.backend = backend
        front = Buffer(width: width, height: height)
        frame = Frame(width: width, height: height)
        diff = CellDiff(synchronizedOutput: synchronizedOutput, colorDepth: colorDepth, hyperlinks: hyperlinks)
    }

    public mutating func resize(width: Int, height: Int) {
        guard width != front.width || height != front.height else {
            return
        }
        front = Buffer(width: width, height: height)
        frame = Frame(width: width, height: height)
        presented = false
        // Keep cursor visibility history until the next full repaint.
    }
    /// Repaints every cell on the next draw after native code writes outside the renderer.
    public mutating func invalidate() {
        presented = false
        diff.reset()
    }

    @discardableResult
    public mutating func draw(_ render: (inout Frame) -> Void) throws -> RenderStats {
        frame.reset()
        render(&frame)
        let (data, stats) = diff.encode(
            frame.buffer, previous: presented ? front : nil, cursor: frame.cursor
        )
        do {
            if !data.isEmpty {
                try backend.write(data)
            }
        } catch {
            presented = false
            diff.reset()
            throw error
        }
        swap(&front, &frame.buffer)
        presented = true
        return stats
    }
}
