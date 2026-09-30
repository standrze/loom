import Foundation
import Markdown

/// Converts the parser's public syntax tree into terminal presentation spans.
struct MarkdownRenderer {
    private typealias Line = [TextSpan]

    private let source: String
    private let bytes: [UInt8]
    private let lineStarts: [Int]
    private let palette: MarkdownPalette

    init(_ text: String, palette: MarkdownPalette) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let sourceBytes = Array(normalized.utf8)
        source = normalized
        bytes = sourceBytes
        lineStarts = [0] + sourceBytes.indices.filter { sourceBytes[$0] == 10 }.map { $0 + 1 }
        self.palette = palette
    }

    func spans() -> [TextSpan] {
        // Preserve model punctuation instead of changing quotes, dashes, or ellipses.
        let document = Document(parsing: source, options: [.disableSmartOpts])
        let blocks = Array(document.children)
        guard !blocks.isEmpty else {
            return source.allSatisfy(\.isWhitespace) ? [TextSpan(source, style: palette.body)] : []
        }

        let lines = blockSequence(blocks, style: palette.body)
        var spans: [TextSpan] = []
        let leadingBreaks = source.prefix { $0 == "\n" }.count
        if leadingBreaks > 0 {
            spans.append(TextSpan(String(repeating: "\n", count: leadingBreaks), style: palette.body))
        }
        for (index, line) in lines.enumerated() {
            if index > 0 { spans.append(TextSpan("\n", style: palette.body)) }
            spans.append(contentsOf: line)
        }
        // An unfinished code block already includes its trailing blank lines.
        // Only retain source newlines after the final block's covered lines.
        let trailingBreaks = min(
            source.reversed().prefix { $0 == "\n" }.count,
            max(0, lineStarts.count - (blocks.last.map(lastContentLine) ?? lineStarts.count)))
        if trailingBreaks > 0 {
            spans.append(TextSpan(String(repeating: "\n", count: trailingBreaks), style: palette.body))
        }
        return spans
    }

    private func blockSequence(_ blocks: [any Markup], style: Style) -> [Line] {
        var lines: [Line] = []
        var previous: (any Markup)?
        for block in blocks {
            if let previous {
                let gap = max(1, (block.range?.lowerBound.line ?? 0) - lastContentLine(previous))
                lines.append(contentsOf: repeatElement([], count: gap - 1))
            }
            lines.append(contentsOf: renderBlock(block, style: style))
            previous = block
        }
        return lines
    }

    private func renderBlock(_ block: any Markup, style: Style) -> [Line] {
        switch block {
        case let heading as Heading:
            return splitLines(inlineChildren(heading, style: overlay(palette.heading, on: style)))
        case let paragraph as Markdown.Paragraph:
            return splitLines(inlineChildren(paragraph, style: style))
        case let quote as BlockQuote:
            let lines = blockSequence(Array(quote.children), style: overlay(palette.quote, on: style))
            return prefixed(lines, first: "│ ", continuation: "│ ", style: palette.quote)
        case let code as CodeBlock:
            return codeLines(code, style: style)
        case let list as UnorderedList:
            return listLines(Array(list.children), start: nil, style: style)
        case let list as OrderedList:
            return listLines(Array(list.children), start: list.startIndex, style: style)
        case is ThematicBreak:
            return [[TextSpan("───", style: palette.quote)]]
        default:
            // Tables, HTML, and future block kinds remain visible
            // as literal source until loom has a presentation for them.
            return splitLines([TextSpan(literal(block), style: style)])
        }
    }

    private func codeLines(_ code: CodeBlock, style: Style) -> [Line] {
        let codeStyle = overlay(palette.code, on: style)
        // Presentation omits the parser's terminating newline, while the copy payload
        // keeps genuine source newlines, including blank lines at the end of a block.
        let content = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
        guard let headerStyle = palette.codeBlockHeader else {
            guard !code.code.isEmpty else { return [] }
            return prefixed(
                splitLines([TextSpan(content, style: codeStyle)]),
                first: palette.codeBlockPrefix, continuation: palette.codeBlockPrefix, style: palette.quote)
        }

        let block = TextCodeBlock(
            id: code.range.flatMap { byteOffset($0.lowerBound) } ?? 0,
            language: code.language, code: originalCode(code), isCompact: palette.compactCodeBlocks)
        if block.isCompact {
            return (0..<3).map { row in
                [TextSpan(" ", style: palette.body, codeBlock: block, isCodeBlockHeader: row == 1)]
            }
        }
        let header = [TextSpan(" ", style: headerStyle, codeBlock: block, isCodeBlockHeader: true)]
        guard !code.code.isEmpty else { return [header] }
        let highlighted = palette.codeHighlighter?(content, code.language) ?? [TextSpan(content, style: codeStyle)]
        let lines = splitLines(
            highlighted.map {
                TextSpan($0.text, style: $0.style ?? codeStyle, link: $0.link, codeBlock: block)
            })
        return [header] + prefixed(lines, first: "│ ", continuation: "│ ", style: codeStyle)
    }

    private func originalCode(_ code: CodeBlock) -> String {
        guard code.code.hasSuffix("\n"), !source.hasSuffix("\n"),
            let range = code.range, range.upperBound.line == lineStarts.count
        else { return code.code }

        let opening = literal(code).prefix { $0 != "\n" }
        let delimiter = opening.first
        let isFenced = (delimiter == "`" || delimiter == "~") && opening.prefix { $0 == delimiter }.count >= 3
        let physicalLines = range.upperBound.line - range.lowerBound.line
        let parsedNewlines = code.code.filter { $0 == "\n" }.count
        // Each content line contributes one parser newline. A closing fence adds
        // a source line but no code newline; indented code drops trailing blank
        // source lines. Neither case has a synthetic newline on its final code line.
        let hasUnterminatedContentLine =
            isFenced ? parsedNewlines == physicalLines : parsedNewlines > physicalLines
        return hasUnterminatedContentLine ? String(code.code.dropLast()) : code.code
    }

    private func listLines(_ items: [any Markup], start: UInt?, style: Style) -> [Line] {
        var lines: [Line] = []
        var previous: (any Markup)?
        for (index, item) in items.enumerated() {
            if let previous {
                let gap = max(1, (item.range?.lowerBound.line ?? 0) - lastContentLine(previous))
                lines.append(contentsOf: repeatElement([], count: gap - 1))
            }
            let marker = start.map { "\($0 + UInt(index)). " } ?? "• "
            let checkbox: String
            switch (item as? ListItem)?.checkbox {
            case .checked: checkbox = "[x] "
            case .unchecked: checkbox = "[ ] "
            case nil: checkbox = ""
            }
            let prefix = marker + checkbox
            let content = blockSequence(Array(item.children), style: style)
            lines.append(
                contentsOf: prefixed(
                    content, first: prefix, continuation: String(repeating: " ", count: prefix.count), style: style))
            previous = item
        }
        return lines
    }

    private func inlineChildren(_ node: any Markup, style: Style, link: String? = nil) -> [TextSpan] {
        node.children.flatMap { inline($0, style: style, link: link) }
    }

    private func inline(_ node: any Markup, style: Style, link: String?) -> [TextSpan] {
        switch node {
        case let text as Markdown.Text:
            return [TextSpan(text.string, style: style, link: link)]
        case is SoftBreak:
            return [TextSpan(" ", style: style, link: link)]
        case is LineBreak:
            return [TextSpan("\n", style: style, link: link)]
        case is Strong:
            return inlineChildren(node, style: overlay(palette.strong, on: style), link: link)
        case is Emphasis:
            return inlineChildren(node, style: overlay(palette.emphasis, on: style), link: link)
        case let code as InlineCode:
            return [TextSpan(code.code, style: overlay(palette.code, on: style), link: link)]
        case let destination as Link:
            guard let value = destination.destination, let safe = safeURL(value) else {
                return [TextSpan(literal(node), style: style)]
            }
            return inlineChildren(node, style: overlay(palette.link, on: style), link: safe)
        default:
            // Images and inline HTML are text, never terminal commands or fetched resources.
            return [TextSpan(literal(node), style: style, link: link)]
        }
    }

    private func splitLines(_ spans: [TextSpan]) -> [Line] {
        var lines: [Line] = [[]]
        for span in spans {
            for (index, text) in span.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if index > 0 { lines.append([]) }
                if !text.isEmpty || span.codeBlock != nil {
                    lines[lines.count - 1].append(
                        TextSpan(
                            String(text), style: span.style, link: span.link,
                            codeBlock: span.codeBlock, isCodeBlockHeader: span.isCodeBlockHeader))
                }
            }
        }
        return lines
    }

    private func prefixed(_ lines: [Line], first: String, continuation: String, style: Style) -> [Line] {
        (lines.isEmpty ? [[]] : lines).enumerated().map { index, line in
            // Header and compact summary anchors stay one cell wide inside nested containers.
            guard !line.contains(where: { $0.isCodeBlockHeader || $0.codeBlock?.isCompact == true }) else {
                return line
            }
            let code = line.first { $0.codeBlock != nil }
            return [
                TextSpan(index == 0 ? first : continuation, style: code?.style ?? style, codeBlock: code?.codeBlock)
            ]
                + line
        }
    }

    private func overlay(_ emphasis: Style, on base: Style) -> Style {
        Style(
            foreground: emphasis.foreground == .terminalDefault ? base.foreground : emphasis.foreground,
            background: emphasis.background == .terminalDefault ? base.background : emphasis.background,
            bold: base.bold || emphasis.bold, italic: base.italic || emphasis.italic,
            underlined: base.underlined || emphasis.underlined, reversed: base.reversed || emphasis.reversed)
    }

    private func lastContentLine(_ block: any Markup) -> Int {
        // Container ranges can include the blank line after their final child.
        // Use the child boundary so the next paragraph does not lose that gap.
        if block is ListItem || block is OrderedList || block is UnorderedList || block is BlockQuote,
            let child = Array(block.children).last
        {
            return lastContentLine(child)
        }
        if block is ThematicBreak, let end = block.range?.upperBound, end.column == 1 {
            return max(0, end.line - 1)
        }
        return block.range?.upperBound.line ?? 0
    }

    private func literal(_ node: any Markup) -> String {
        guard let range = node.range, let start = byteOffset(range.lowerBound),
            let end = byteOffset(range.upperBound), start <= end
        else { return "" }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private func byteOffset(_ location: SourceLocation) -> Int? {
        // Source columns are one-based UTF-8 bytes, not Characters or terminal cells.
        guard lineStarts.indices.contains(location.line - 1), location.column > 0 else { return nil }
        let offset = lineStarts[location.line - 1] + location.column - 1
        return offset <= bytes.count ? offset : nil
    }

    private func safeURL(_ value: String) -> String? {
        guard value.utf8.count <= 2048,
            !value.unicodeScalars.contains(where: { $0.value < 32 || (0x7f...0x9f).contains($0.value) }),
            let url = URL(string: value), let scheme = url.scheme?.lowercased(),
            (scheme == "https" || scheme == "http"), url.host != nil
        else { return nil }
        return url.absoluteString
    }
}
