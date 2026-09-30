import Foundation

/// A slow diagonal sheen for a braille mark.
///
/// Opacity is 0 at the resting color and 1 at the highlight. A raised-cosine band
/// travels from the lower left to the upper right, then rests off the mark. A shallow
/// pulse remains during that rest. The phase is wall-clock time, so the speed does not
/// follow the redraw rate. `framesPerSecond` is only the cadence at which a caller
/// needs to sample it.
public enum DiagonalShine {
    public static let framesPerSecond = 12.0

    public static func frame(at seconds: Double) -> Int {
        let time = seconds.isFinite ? max(0, seconds) : 0
        return Int(time * framesPerSecond)
    }

    /// Seconds until the next quantized sample.
    ///
    /// Callers sleep this long instead of redrawing continuously.
    public static func delayUntilNextFrame(after seconds: Double) -> Double {
        let time = seconds.isFinite ? max(0, seconds) : 0
        let duration = 1 / framesPerSecond
        let into = time.truncatingRemainder(dividingBy: duration)
        return max(0.001, duration - into)
    }

    /// `diagonal` is 0 at the lower left and 1 at the upper right.
    public static func opacity(diagonal: Double, seconds: Double) -> Double {
        let band = 0.38
        let cycle = 4.0
        let sweepFraction = 0.32
        let shine = 0.33
        let pulseAmount = 0.06
        let pulseSeconds = 5.0
        let time = seconds.isFinite ? max(0, seconds) : 0
        let progress = time.truncatingRemainder(dividingBy: cycle) / cycle
        let sweep = min(1, progress / sweepFraction)
        let bandPosition = -band + sweep * (1 + 2 * band)
        let pulse = pulseAmount * (0.5 - 0.5 * cos(2 * .pi * time / pulseSeconds))
        let distance = abs(diagonal - bandPosition)
        let shineAmount = distance < band ? 0.5 * (1 + cos(.pi * distance / band)) : 0
        return min(1, max(0, pulse + shine * shineAmount))
    }
}
