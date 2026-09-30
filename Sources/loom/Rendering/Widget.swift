import weft

/// A value that draws its content into an assigned region of a buffer.
public protocol Widget {
    /// Renders within the supplied area without writing directly to the terminal.

    func render(in area: Rect, buffer: inout Buffer)
}
