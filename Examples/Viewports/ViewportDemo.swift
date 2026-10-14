import Foundation
import loom
import weft

/// A primary-screen example.
///
/// TerminalSession and one TerminalEvents stream own all input.
@main
struct ViewportDemo {
    @MainActor
    static func main() async throws {
        let session = try TerminalSession(options: TerminalOptions(hideCursor: true))
        defer { session.close() }
        let events = TerminalEvents(session: session)
        defer { events.stop() }
        let size = TerminalSession.size()
        var application = ViewportApplication(fixed: CommandLine.arguments.contains("--fixed"), size: size)
        defer { application.leaveCursorBelowUi() }
        try application.start(session: session)
        for try await batch in events.events {
            for event in batch {
                let running = try application.handle(event, session: session)
                if !running { return }
            }
            try application.draw()
        }
    }
}

@MainActor
private struct ViewportApplication {
    let fixed: Bool
    var size: Rect
    var terminal: Terminal<ANSIBackend>?
    var query: UUID?
    var input = ""
    var committed = 0
    var submissions: [String] = []
    var moved = false
    var small = false

    mutating func start(session: TerminalSession) throws {
        if fixed {
            writeSentinels()
            terminal = Terminal(
                backend: ANSIBackend(), width: size.width, height: size.height,
                viewport: .fixed(fixedArea))
            try draw()
        } else {
            query = try session.requestQuery(.cursorPosition, timeoutMilliseconds: 1000)
        }
    }

    mutating func handle(_ event: InputEvent, session: TerminalSession) throws -> Bool {
        switch event {
        case let .resize(width, height):
            size = Rect(width: width, height: height)
            terminal?.resize(width: width, height: height)
            if fixed {
                let area = fixedArea
                terminal?.setViewport(.fixed(area))
                writeSentinels()
            } else {
                if let query { _ = session.cancelQuery(query) }
                query = try session.requestQuery(.cursorPosition, timeoutMilliseconds: 1000)
            }
            return true
        case let .queryResult(result):
            guard result.id == query else { return true }
            query = nil
            switch result.outcome {
            case let .reply(.cursorPosition(point)):
                if terminal == nil {
                    terminal = Terminal(
                        backend: ANSIBackend(), width: size.width, height: size.height,
                        viewport: .inline(height: 3, anchor: point))
                } else {
                    try terminal?.reanchor(at: point)
                }
                try draw()
                try flushSubmissions()
            case .reply:
                discardSubmissions()
                return false
            case .timedOut:
                write("\r\nCursor query timed out; exiting.\r\n")
                discardSubmissions()
                return false
            case .cancelled:
                write("\r\nCursor query cancelled; exiting.\r\n")
                discardSubmissions()
                return false
            }
            return true
        case .signal:
            return false
        case let .paste(text):
            input += text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            return true
        default:
            break
        }
        guard let key = event.keyboardEvent?.key else {
            if case let .text(text) = event { input += text }
            return true
        }
        switch key {
        case .escape, .interrupt, .endOfInput:
            return false
        case .enter, .newline:
            if input == "q" { return false }
            guard !fixed, !input.isEmpty else { return true }
            submissions.append(input)
            input = ""
            try flushSubmissions()
        case .backspace:
            if !input.isEmpty { input.removeLast() }
        case let .character(text):
            if fixed {
                switch text {
                case "q": return false
                case "m": moved.toggle()
                case "s": small.toggle()
                case "r": terminal?.invalidate()
                default: break
                }
                let area = fixedArea
                terminal?.setViewport(.fixed(area))
            } else {
                input += text
            }
        default:
            break
        }
        return true
    }

    mutating func flushSubmissions() throws {
        guard query == nil, terminal != nil else { return }
        while !submissions.isEmpty {
            // Admission happens once. A failed insertion may have partially committed;
            // never leave it queued for automatic replay.
            let message = "committed: " + submissions.removeFirst()
            try terminal?.insertBefore(height: 1) { frame in
                frame.render(
                    Paragraph(TextLayout([TextSpan(message, patch: StylePatch(bold: true))], width: frame.area.width)),
                    in: frame.area)
            }
            committed += 1
        }
    }

    mutating func discardSubmissions() {
        guard !submissions.isEmpty else { return }
        write("Pending submissions discarded without insertion: \(submissions.count).\r\n")
        submissions.removeAll()
    }

    mutating func draw() throws {
        guard query == nil else { return }
        let lines: [String]
        if fixed {
            lines = ["FIXED viewport", "m move | s shrink", "r repaint | q quit"]
        } else {
            lines = ["INLINE viewport | Enter commits | q Enter quits", "committed rows: \(committed)", "> " + input]
        }
        let fixed = fixed
        let input = input
        try terminal?.draw { frame in
            let layout = TextLayout(lines.joined(separator: "\n"), width: frame.area.width)
            frame.render(Paragraph(layout), in: frame.area)
            if !fixed, frame.area.width > 0, frame.area.height > 0 {
                let column = min(frame.area.width - 1, 2 + input.reduce(0) { $0 + loom.terminalCellWidth($1) })
                frame.cursor = Point(x: column, y: frame.area.height - 1)
            }
        }
    }

    var fixedArea: Rect {
        Rect(
            x: moved ? 4 : 2, y: moved ? 4 : 2,
            width: min(max(0, size.width - 6), small ? 18 : 40),
            height: min(max(0, size.height - 6), small ? 2 : 4))
    }

    func writeSentinels() {
        guard size.width > 0, size.height > 0 else { return }
        write("\u{1b}[1;1HTOP-SENTINEL\u{1b}[\(max(1, size.height - 1));1HBOTTOM-SENTINEL")
    }

    func leaveCursorBelowUi() {
        guard let terminal, !terminal.requiresReanchor else { return }
        let row = min(size.height, terminal.viewportArea.maxY + 1)
        write("\u{1b}[0m\u{1b}[\(max(1, row));1H\r\n\u{1b}[?25h")
    }

    private func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}
