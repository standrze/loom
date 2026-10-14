import weft

/// An owned logical frame captured after a successful draw, including styles and links.
///
/// Buffer uses value semantics: subsequent draws cannot change this snapshot.
/// This records renderer state, not terminal scrollback or terminal-emulator behavior.
public struct FrameSnapshot: Sendable {
    public let buffer: Buffer
    public let cursor: Point?

    public init(buffer: Buffer, cursor: Point?) {
        self.buffer = buffer
        self.cursor = cursor
    }

    /// Human-readable geometry, cursor and cell differences from another snapshot.
    public func differences(from other: FrameSnapshot) -> [String] {
        var result: [String] = []
        if buffer.width != other.buffer.width || buffer.height != other.buffer.height {
            result.append("Size: \(other.buffer.width)×\(other.buffer.height) → \(buffer.width)×\(buffer.height)")
        }
        if cursor != other.cursor {
            result.append("Cursor: \(String(describing: other.cursor)) → \(String(describing: cursor))")
        }
        for y in 0..<min(buffer.height, other.buffer.height) {
            for x in 0..<min(buffer.width, other.buffer.width) where buffer[x, y] != other.buffer[x, y] {
                result.append(
                    "Cell (\(x), \(y)): \(String(describing: other.buffer[x, y])) → \(String(describing: buffer[x, y]))"
                )
            }
        }
        return result
    }
}
