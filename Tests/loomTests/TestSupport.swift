import Foundation
import Testing

@testable import loom

struct MemoryBackend: Backend {
    var writes: [Data] = []

    mutating func write(_ data: Data) {
        writes.append(data)
    }
}
