import loom

@main
struct BrowserDemo {
    @MainActor
    static func main() async throws {
        let session = try TerminalSession(
            options: TerminalOptions(alternateScreen: true, hideCursor: true, mouseCapture: true))
        defer { session.close() }
        let events = TerminalEvents(session: session)
        defer { events.stop() }
        let size = TerminalSession.size()
        var terminal = Terminal(backend: ANSIBackend(), width: size.width, height: size.height)
        var browser = BrowserApplication()
        try terminal.draw { browser.render(&$0) }
        for try await batch in events.events {
            for event in batch {
                if case let .resize(width, height) = event {
                    terminal.resize(width: width, height: height)
                }
                if !browser.handle(event) { return }
            }
            try terminal.draw { browser.render(&$0) }
        }
    }
}
