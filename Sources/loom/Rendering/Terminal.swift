import weft

/// ANSI terminal rendering over a weft byte sink.
///
/// This compatible facade shares viewport and failure behavior with `RenderTerminal`.
/// The caller owns terminal modes and input reading.
public struct Terminal<B: Backend> {
    private var renderer: RenderTerminal<ANSIRenderBackend<B>>

    public var backend: B { renderer.backend.backend }
    public var viewport: Viewport { renderer.viewport }
    public var viewportArea: Rect { renderer.viewportArea }
    public var requiresReanchor: Bool { renderer.requiresReanchor }
    public var snapshot: FrameSnapshot? { renderer.snapshot }

    public init(
        backend: B, width: Int, height: Int, synchronizedOutput: Bool = true,
        colorDepth: TerminalColorDepth = .trueColor, hyperlinks: Bool = false,
        viewport: Viewport = .fullscreen
    ) {
        renderer = RenderTerminal(
            backend: ANSIRenderBackend(
                backend: backend, synchronizedOutput: synchronizedOutput, colorDepth: colorDepth,
                hyperlinks: hyperlinks),
            width: width, height: height, viewport: viewport)
    }

    public func localPoint(from physicalPoint: Point) -> Point? { renderer.localPoint(from: physicalPoint) }
    public func physicalPoint(from localPoint: Point) -> Point? { renderer.physicalPoint(from: localPoint) }
    public mutating func resize(width: Int, height: Int) { renderer.resize(width: width, height: height) }
    public mutating func setViewport(_ viewport: Viewport) { renderer.setViewport(viewport) }
    public mutating func reanchor(at anchor: Point) throws { try renderer.reanchor(at: anchor) }
    public mutating func invalidate() { renderer.invalidate() }

    @discardableResult
    public mutating func draw(_ render: (inout Frame) -> Void) throws -> RenderStats {
        try renderer.draw(render)
    }

    public mutating func insertBefore(_ content: Buffer) throws { try renderer.insertBefore(content) }
    public mutating func insertBefore(height: Int, render: (inout Frame) -> Void) throws {
        try renderer.insertBefore(height: height, render: render)
    }
}
