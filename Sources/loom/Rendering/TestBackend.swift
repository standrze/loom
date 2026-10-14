import weft

/// Deterministic failure points within a semantic update, using one-based primitive step numbers.
public enum TestBackendFailure: Equatable, Sendable {
    case beforeStep(Int)
    case afterStep(Int)
}

/// A simulated output failure.
///
/// Earlier primitive mutations remain visible for recovery tests.
public struct TestBackendError: Error, Equatable, Sendable {
    public let failure: TestBackendFailure

    public init(failure: TestBackendFailure) {
        self.failure = failure
    }
}

/// A headless physical terminal surface with scrollback and injectable partial-output failures.
///
/// Each resize, clear, cursor move, row paint and line feed is one primitive step.
/// The failure counter restarts for each update; attempted updates are retained in history.
/// This models semantic presentation and scrolling, not arbitrary ANSI terminal input.
public struct TestBackend: RenderBackend, Sendable {
    public private(set) var screen: Buffer
    public private(set) var cursor: Point?
    public private(set) var scrollback: [Buffer] = []
    public private(set) var operations: [RenderUpdate] = []
    public var failure: TestBackendFailure?
    public private(set) var completedSteps: Int = 0
    private var nextStep = 1

    public init(width: Int = 80, height: Int = 24, failure: TestBackendFailure? = nil) {
        screen = Buffer(width: width, height: height)
        self.failure = failure
    }

    /// Resets encoder state.
    ///
    /// This semantic backend has no encoder and retains its diagnostic history.
    public mutating func reset() {}

    /// Clears diagnostic history while retaining the physical terminal contents and failure plan.
    public mutating func clearHistory() {
        operations.removeAll()
        scrollback.removeAll()
        completedSteps = 0
        nextStep = 1
    }

    /// Applies an update or throws at the configured primitive boundary.
    public mutating func render(_ update: RenderUpdate) throws -> RenderStats {
        operations.append(update)
        nextStep = 1
        completedSteps = 0
        let before = screen
        switch update {
        case .frame(let frame):
            try resize(frame.terminalSize)
            for area in frame.clears {
                try step { $0.screen.clear(area) }
            }
            if let anchor = frame.anchor,
                frame.terminalSize.width > 0, frame.terminalSize.height > 0, frame.area.height > 0
            {
                try move(to: anchor)
                if anchor.x > 0 { try lineFeed() }
                for _ in 0..<max(0, frame.area.height - 1) { try lineFeed() }
            }
            let sameSize =
                frame.previous?.buffer.width == frame.next.buffer.width
                && frame.previous?.buffer.height == frame.next.buffer.height
            if frame.clearScreen && !sameSize {
                try step { $0.screen.reset() }
            }
            try paint(frame.next.buffer, at: Point(x: frame.area.x, y: frame.area.y), clip: frame.area)
            try placeCursor(frame.next.cursor, area: frame.area, buffer: frame.next.buffer)
        case .insertion(let insertion):
            try resize(insertion.terminalSize)
            try step { $0.screen.clear(insertion.oldArea) }
            try move(to: Point(x: 0, y: insertion.oldArea.y))
            for row in 0..<insertion.content.height {
                let y = cursor?.y ?? 0
                var line = Buffer(width: insertion.terminalSize.width, height: 1)
                line.copy(
                    from: insertion.content, region: Rect(y: row, width: insertion.content.width, height: 1),
                    to: Point(x: 0, y: 0))
                try paintRow(line, row: 0, at: Point(x: 0, y: y), clip: screen.area)
                try lineFeed()
            }
            for _ in 0..<max(0, insertion.oldArea.height - 1) { try lineFeed() }
            try paint(
                insertion.retained.buffer,
                at: Point(x: insertion.newArea.x, y: insertion.newArea.y), clip: insertion.newArea)
            try placeCursor(insertion.retained.cursor, area: insertion.newArea, buffer: insertion.retained.buffer)
        }
        return RenderStats(changedCells: screen.differences(from: before).count, bytes: 0)
    }

    private mutating func step(_ mutation: (inout TestBackend) -> Void) throws {
        let number = nextStep
        if failure == .beforeStep(number) { throw TestBackendError(failure: .beforeStep(number)) }
        mutation(&self)
        completedSteps += 1
        nextStep += 1
        if failure == .afterStep(number) { throw TestBackendError(failure: .afterStep(number)) }
    }

    private mutating func resize(_ size: RenderSize) throws {
        guard size.width != screen.width || size.height != screen.height else { return }
        try step { backend in
            backend.screen.resize(width: size.width, height: size.height)
            if let point = backend.cursor {
                backend.cursor = backend.clamped(point)
            }
        }
    }

    private func clamped(_ point: Point) -> Point? {
        guard screen.width > 0, screen.height > 0 else { return nil }
        return Point(x: min(screen.width - 1, max(0, point.x)), y: min(screen.height - 1, max(0, point.y)))
    }

    private mutating func move(to point: Point) throws {
        try step { $0.cursor = $0.clamped(point) }
    }

    private mutating func placeCursor(_ point: Point?, area: Rect, buffer: Buffer) throws {
        guard let point, point.x >= 0, point.y >= 0, point.x < min(area.width, buffer.width),
            point.y < min(area.height, buffer.height)
        else {
            try step { $0.cursor = nil }
            return
        }
        let x = area.x.addingReportingOverflow(point.x)
        let y = area.y.addingReportingOverflow(point.y)
        guard !x.overflow, !y.overflow,
            screen.area.contains(Point(x: x.partialValue, y: y.partialValue))
        else {
            try step { $0.cursor = nil }
            return
        }
        try move(to: Point(x: x.partialValue, y: y.partialValue))
    }

    private mutating func paint(_ buffer: Buffer, at origin: Point, clip: Rect) throws {
        for row in 0..<buffer.height {
            try paintRow(buffer, row: row, at: Point(x: origin.x, y: origin.y + row), clip: clip)
        }
    }

    private mutating func paintRow(_ buffer: Buffer, row: Int, at point: Point, clip: Rect) throws {
        try step { backend in
            backend.screen.withClip(clip) { screen in
                screen.copy(
                    from: buffer, region: Rect(y: row, width: buffer.width, height: 1), to: point)
            }
        }
    }

    private mutating func lineFeed() throws {
        try step { backend in
            guard backend.screen.width > 0, backend.screen.height > 0 else { return }
            let y = backend.cursor?.y ?? 0
            if y + 1 < backend.screen.height {
                backend.cursor = Point(x: 0, y: y + 1)
                return
            }
            var row = Buffer(width: backend.screen.width, height: 1)
            row.copy(from: backend.screen, region: Rect(width: backend.screen.width, height: 1), to: Point(x: 0, y: 0))
            backend.scrollback.append(row)
            var shifted = Buffer(width: backend.screen.width, height: backend.screen.height)
            shifted.copy(
                from: backend.screen,
                region: Rect(y: 1, width: backend.screen.width, height: max(0, backend.screen.height - 1)),
                to: Point(x: 0, y: 0))
            backend.screen = shifted
            backend.cursor = Point(x: 0, y: backend.screen.height - 1)
        }
    }
}
