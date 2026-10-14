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
        streaming(isComplete: true).spans
    }

    func streaming(isComplete: Bool) -> MarkdownStreamingSnapshot {
        // Preserve model punctuation instead of changing quotes, dashes, or ellipses.
        let document = Document(parsing: source, options: [.disableSmartOpts])
        let blocks = Array(document.children)
        guard !blocks.isEmpty else {
            let spans =
                source.allSatisfy(\.isWhitespace)
                ? [TextSpan(source, style: palette.body, sourceLine: 1)] : []
            return MarkdownStreamingSnapshot(
                stableSpans: isComplete ? spans : [], pendingSpans: isComplete ? [] : spans,
                requiresFinalReflow: isComplete)
        }

        let lines = blockSequence(blocks, style: palette.body)
        // Keep the final top-level block mutable, including its entire list or quote
        // container. A later block proves that a preceding table has ended.
        let stableLineCount =
            isComplete ? lines.count : blockSequence(Array(blocks.dropLast()), style: palette.body).count
        var splitIndex = 0
        var spans: [TextSpan] = []
        let leadingBreaks = source.prefix { $0 == "\n" }.count
        if leadingBreaks > 0 {
            spans.append(TextSpan(String(repeating: "\n", count: leadingBreaks), style: palette.body, sourceLine: 1))
        }
        for (index, line) in lines.enumerated() {
            if index > 0 { spans.append(TextSpan("\n", style: palette.body)) }
            spans.append(contentsOf: line)
            if index + 1 == stableLineCount { splitIndex = spans.count }
        }
        // An unfinished code block already includes its trailing blank lines.
        // Only retain source newlines after the final block's covered lines.
        let trailingBreaks = min(
            source.reversed().prefix { $0 == "\n" }.count,
            max(0, lineStarts.count - (blocks.last.map(lastContentLine) ?? lineStarts.count)))
        if trailingBreaks > 0 {
            spans.append(
                TextSpan(
                    String(repeating: "\n", count: trailingBreaks), style: palette.body,
                    sourceLine: lineStarts.count - trailingBreaks))
        }
        if isComplete { splitIndex = spans.count }
        return MarkdownStreamingSnapshot(
            stableSpans: Array(spans[..<splitIndex]), pendingSpans: Array(spans[splitIndex...]),
            requiresFinalReflow: isComplete)
    }

    private func blockSequence(_ blocks: [any Markup], style: Style) -> [Line] {
        var lines: [Line] = []
        var previous: (any Markup)?
        for block in blocks {
            if let previous {
                let gap = max(1, (block.range?.lowerBound.line ?? 0) - lastContentLine(previous))
                lines.append(
                    contentsOf: (1..<gap).map {
                        [TextSpan("", style: style, sourceLine: lastContentLine(previous) + $0)]
                    })
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
            return prefixed(lines, first: "│ ", continuation: "│ ", style: palette.quote, copyable: false)
        case let code as CodeBlock:
            return codeLines(code, style: style)
        case let list as UnorderedList:
            return listLines(Array(list.children), start: nil, style: style)
        case let list as OrderedList:
            return listLines(Array(list.children), start: list.startIndex, style: style)
        case is ThematicBreak:
            return [[TextSpan("───", style: palette.quote, sourceLine: block.range?.lowerBound.line)]]
        default:
            // Tables, HTML, and future block kinds remain visible
            // as literal source until loom has a presentation for them.
            return splitLines([TextSpan(literal(block), style: style, sourceLine: block.range?.lowerBound.line)])
        }
    }

    private func codeLines(_ code: CodeBlock, style: Style) -> [Line] {
        let codeStyle = overlay(palette.code, on: style)
        // Presentation omits the parser's terminating newline, while the copy payload
        // keeps genuine source newlines, including blank lines at the end of a block.
        let opening = literal(code).prefix { $0 != "\n" }.trimmingCharacters(in: .whitespaces)
        let fenced = opening.hasPrefix("```") || opening.hasPrefix("~~~")
        let firstLine = (code.range?.lowerBound.line ?? 1) + (fenced ? 1 : 0)
        func located(_ spans: [TextSpan]) -> [TextSpan] {
            var line = firstLine
            return spans.map { span in
                defer { line += span.text.filter { $0 == "\n" }.count }
                return TextSpan(
                    span.text, style: span.style, link: span.link, codeBlock: span.codeBlock,
                    isCodeBlockHeader: span.isCodeBlockHeader, copyable: span.copyable, sourceLine: line,
                    patch: span.patch)
            }
        }
        let content = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
        guard let headerStyle = palette.codeBlockHeader else {
            guard !code.code.isEmpty else { return [] }
            let highlighted = palette.codeHighlighter?(content, code.language) ?? [TextSpan(content, style: codeStyle)]
            let inlineSpans = highlighted.map { span in
                let tokenStyle = span.style ?? codeStyle
                return TextSpan(
                    span.text,
                    style: Style(
                        foreground: tokenStyle.foreground == .terminalDefault
                            ? codeStyle.foreground : tokenStyle.foreground,
                        background: codeStyle.background,
                        bold: tokenStyle.bold, italic: tokenStyle.italic,
                        underlined: tokenStyle.underlined, reversed: tokenStyle.reversed,
                        dim: tokenStyle.dim, strikethrough: tokenStyle.strikethrough), patch: span.patch)
            }
            return prefixed(
                splitLines(located(inlineSpans)),
                first: palette.codeBlockPrefix, continuation: palette.codeBlockPrefix, style: palette.quote)
        }

        let block = TextCodeBlock(
            id: code.range.flatMap { byteOffset($0.lowerBound) } ?? 0,
            language: code.language, code: originalCode(code), isCompact: palette.compactCodeBlocks)
        if block.isCompact {
            return (0..<3).map { row in
                [
                    TextSpan(
                        " ", style: palette.body, codeBlock: block, isCodeBlockHeader: row == 1,
                        sourceLine: code.range?.lowerBound.line)
                ]
            }
        }
        let header = [
            TextSpan(
                " ", style: headerStyle, codeBlock: block, isCodeBlockHeader: true,
                sourceLine: code.range?.lowerBound.line)
        ]
        guard !code.code.isEmpty else { return [header] }
        let highlighted = palette.codeHighlighter?(content, code.language) ?? [TextSpan(content, style: codeStyle)]
        let lines = splitLines(
            located(
                highlighted.map {
                    TextSpan($0.text, style: $0.style ?? codeStyle, link: $0.link, codeBlock: block, patch: $0.patch)
                }))
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
                lines.append(
                    contentsOf: (1..<gap).map {
                        [TextSpan("", style: style, sourceLine: lastContentLine(previous) + $0)]
                    })
            }
            let marker = start.map { "\($0 + UInt(index)). " } ?? "• "
            let checkbox: String
            switch (item as? Markdown.ListItem)?.checkbox {
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
            return [TextSpan(text.string, style: style, link: link, sourceLine: node.range?.lowerBound.line)]
        case is SoftBreak:
            return [
                TextSpan(
                    palette.preservesSoftBreaks ? "\n" : " ", style: style, link: link,
                    sourceLine: node.range?.lowerBound.line)
            ]
        case is LineBreak:
            return [TextSpan("\n", style: style, link: link, sourceLine: node.range?.lowerBound.line)]
        case is Strong:
            return inlineChildren(node, style: overlay(palette.strong, on: style), link: link)
        case is Emphasis:
            return inlineChildren(node, style: overlay(palette.emphasis, on: style), link: link)
        case let code as InlineCode:
            return [
                TextSpan(
                    code.code, style: overlay(palette.code, on: style), link: link,
                    sourceLine: node.range?.lowerBound.line)
            ]
        case let destination as Link:
            guard let value = destination.destination, let safe = safeURL(value) else {
                return [TextSpan(literal(node), style: style, sourceLine: node.range?.lowerBound.line)]
            }
            return inlineChildren(node, style: overlay(palette.link, on: style), link: safe)
        default:
            // Images and inline HTML are text, never terminal commands or fetched resources.
            return [TextSpan(literal(node), style: style, link: link, sourceLine: node.range?.lowerBound.line)]
        }
    }

    private func splitLines(_ spans: [TextSpan]) -> [Line] {
        var lines: [Line] = [[]]
        for span in spans {
            for (index, text) in span.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if index > 0 { lines.append([]) }
                if !text.isEmpty || span.codeBlock != nil || span.sourceLine != nil {
                    lines[lines.count - 1].append(
                        TextSpan(
                            String(text), style: span.style, link: span.link,
                            codeBlock: span.codeBlock, isCodeBlockHeader: span.isCodeBlockHeader,
                            copyable: span.copyable, sourceLine: span.sourceLine.map { $0 + index }, patch: span.patch))
                }
            }
        }
        return lines
    }

    private func prefixed(
        _ lines: [Line], first: String, continuation: String, style: Style, copyable: Bool = true
    ) -> [Line] {
        (lines.isEmpty ? [[]] : lines).enumerated().map { index, line in
            // Header and compact summary anchors stay one cell wide inside nested containers.
            guard !line.contains(where: { $0.isCodeBlockHeader || $0.codeBlock?.isCompact == true }) else {
                return line
            }
            let code = line.first { $0.codeBlock != nil }
            return [
                TextSpan(
                    index == 0 ? first : continuation, style: code?.style ?? style,
                    codeBlock: code?.codeBlock, copyable: copyable)
            ]
                + line
        }
    }

    private func overlay(_ emphasis: Style, on base: Style) -> Style {
        Style(
            foreground: emphasis.foreground == .terminalDefault ? base.foreground : emphasis.foreground,
            background: emphasis.background == .terminalDefault ? base.background : emphasis.background,
            bold: base.bold || emphasis.bold, italic: base.italic || emphasis.italic,
            underlined: base.underlined || emphasis.underlined, reversed: base.reversed || emphasis.reversed,
            dim: base.dim || emphasis.dim, strikethrough: base.strikethrough || emphasis.strikethrough)
    }

    private func lastContentLine(_ block: any Markup) -> Int {
        // Container ranges can include the blank line after their final child.
        // Use the child boundary so the next paragraph does not lose that gap.
        if block is Markdown.ListItem || block is OrderedList || block is UnorderedList || block is BlockQuote,
            let child = Array(block.children).last
        {
            return lastContentLine(child)
        }
        if !(block is CodeBlock), let end = block.range?.upperBound, end.column == 1,
            end.line > (block.range?.lowerBound.line ?? 0)
        {
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
