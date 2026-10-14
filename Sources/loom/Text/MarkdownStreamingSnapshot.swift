/// A complete rendering snapshot divided at a conservative top-level block boundary.
///
/// Replace the previous snapshot on each update; these arrays are not append-only
/// deltas. Later reference definitions can change even structurally stable blocks.
/// The host owns scrollback and must rebuild it when `requiresFinalReflow` is true.
public struct MarkdownStreamingSnapshot: Sendable {
    public let stableSpans: [TextSpan]
    public let pendingSpans: [TextSpan]
    /// Completion always requests reflow, including references without a final newline.
    public let requiresFinalReflow: Bool

    /// The full rendering, identical to `MarkdownText.spans` for the same source.
    public var spans: [TextSpan] { stableSpans + pendingSpans }
}

extension MarkdownText {
    /// Renders the complete source received so far, holding its last block mutable.
    ///
    /// Pass `isComplete: true` once the response finishes to resolve references and
    /// release the final block. Swift Markdown determines block/container boundaries.
    public static func streaming(
        _ text: String, isComplete: Bool = false, palette: MarkdownPalette = MarkdownPalette()
    ) -> MarkdownStreamingSnapshot {
        MarkdownRenderer(text, palette: palette).streaming(isComplete: isComplete)
    }
}
