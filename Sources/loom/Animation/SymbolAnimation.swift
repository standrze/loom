import Foundation

/// A deterministic sequence of terminal symbols and styles, driven by the caller's clock.
///
/// This value owns no timer. Schedule only while visible, and render at frame boundaries.
public struct SymbolAnimation: Sendable {
    public struct Sample: Equatable, Sendable {
        public let symbol: String
        public let style: Style

        public init(_ symbol: String, style: Style = Style()) {
            self.symbol = symbol
            self.style = style
        }
    }

    public let frames: [Sample]
    public let frameDuration: TimeInterval

    public init(frames: [Sample], frameDuration: TimeInterval) {
        self.frames = frames.isEmpty ? [Sample(" ")] : frames
        self.frameDuration = frameDuration.isFinite && frameDuration > 0 ? frameDuration : 0.133
    }

    public func sample(at elapsed: TimeInterval) -> Sample {
        frames[index(at: elapsed)]
    }

    /// Seconds until the next frame boundary; nil for a static sequence.
    public func nextFrame(after elapsed: TimeInterval) -> TimeInterval? {
        guard frames.count > 1 else { return nil }
        let time = elapsed.isFinite ? max(0, elapsed) : 0
        return max(0.001, frameDuration - time.truncatingRemainder(dividingBy: frameDuration))
    }

    private func index(at elapsed: TimeInterval) -> Int {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        let phase = elapsed.truncatingRemainder(dividingBy: frameDuration * Double(frames.count))
        return min(frames.count - 1, Int(phase / frameDuration))
    }

    /// Braille activity indicator, approximately 7.5 frames per second.
    public static func spinner(style: Style = Style()) -> Self {
        Self(frames: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏".map { Sample(String($0), style: style) }, frameDuration: 0.133)
    }

    /// Slower background activity cycle, approximately one loop per second.
    public static func activity(style: Style = Style()) -> Self {
        Self(frames: "○◎◉◎".map { Sample(String($0), style: style) }, frameDuration: 0.267)
    }

    /// Smooth foreground brightness pulse; never changes the terminal background.
    public static func pulse(
        symbol: String = "◆", low: UInt8 = 80, high: UInt8 = 160, style: Style = Style()
    ) -> Self {
        let frames = (0..<80).map { index in
            let amount = (1 - cos(Double(index) * 2 * .pi / 80)) / 2
            let value = UInt8(clamping: Int((Double(low) + (Double(high) - Double(low)) * amount).rounded()))
            var frameStyle = style
            frameStyle.foreground = .rgb(value, value, value)
            return Sample(symbol, style: frameStyle)
        }
        return Self(frames: frames, frameDuration: 1.0 / 30)
    }
}
