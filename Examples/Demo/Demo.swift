import loom

@main
struct Demo {
    @MainActor
    static func main() async throws {
        let session = try TerminalSession(
            options: TerminalOptions(alternateScreen: true, hideCursor: true))
        defer { session.close() }
        let input = TerminalEvents(session: session)
        defer { input.stop() }
        let size = TerminalSession.size()
        var terminal = Terminal(backend: ANSIBackend(), width: size.width, height: size.height)
        var message = "Hello, 世界"

        func render(_ frame: inout Frame) {
            let text = "loom / a canvas made of cells\n\n\(message)\n\nType something. Escape or Ctrl-C exits."
            let paragraph = Paragraph(
                TextLayout(text, width: frame.area.width),
                style: Style(foreground: .rgb(255, 189, 102)))
            frame.render(paragraph, in: frame.area)
        }

        try terminal.draw(render)
        for try await batch in input.events {
            for event in batch {
                if let key = event.keyboardEvent?.key, [.escape, .interrupt, .endOfInput].contains(key) {
                    return
                }
                switch event {
                case .signal:
                    return
                case let .resize(width, height):
                    terminal.resize(width: width, height: height)
                case let .text(text), let .paste(text):
                    message += text
                case let .key(.character(text)):
                    message += text
                case .key(.backspace):
                    if !message.isEmpty { message.removeLast() }
                default:
                    break
                }
            }
            try terminal.draw(render)
        }
    }
}
