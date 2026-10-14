import weft

/// The terminal footprint owned by a renderer.
///
/// Frame coordinates are always local.
public enum Viewport: Equatable, Sendable {
    case fullscreen
    /// A physical terminal rectangle, clipped to the current terminal size.
    case fixed(Rect)
    /// A full-width primary-screen region starting at a confirmed physical cursor.
    ///
    /// A nonzero cursor column starts on the following row. The renderer reserves
    /// rows with line feeds and may scroll existing primary-screen output upward.
    case inline(height: Int, anchor: Point)
}

/// An inline operation needs a newly confirmed physical cursor position.
public enum ViewportError: Error, Equatable, Sendable {
    case reanchorRequired
    case inlineViewportRequired
}
