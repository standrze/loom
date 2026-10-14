import Foundation
import weft

/// A byte backend for ordinary importing clients to inspect terminal output.
public struct RecordingBackend: Backend {
    public private(set) var writes: [Data] = []
    public var data: Data { writes.reduce(into: Data()) { $0.append($1) } }

    public init() {}

    public mutating func write(_ data: Data) {
        writes.append(data)
    }

    public mutating func reset() {
        writes.removeAll(keepingCapacity: true)
    }
}
