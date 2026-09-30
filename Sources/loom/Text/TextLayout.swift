import weft

/// How text moves to a new terminal row when it reaches the available cells.
public enum TextWrapping: Equatable, Sendable {
    case grapheme
    case word
}

/// The single source of geometry for painting, hit testing, highlighting, and copying.
///
/// Construct once when text or available width changes. Mouse movement never lays out text.
public struct TextLayout: Sendable {
    public struct Glyph: Sendable {
        public let text: String
        public let column: Int
        public let width: Int
        public let sourceRange: Range<String.Index>
        public let style: Style?
        public let link: String?
    }
    public struct Line: Sendable {
        public var glyphs: [Glyph] = []
        /// Original code and panel styling for this laid-out row, including soft wraps.
        public private(set) var codeBlock: TextCodeBlock?
        public private(set) var isCodeBlockHeader = false
        public private(set) var codeBlockStyle: Style?

        mutating func recordCodeBlock(_ span: TextSpan?) {
            guard let span, let block = span.codeBlock else { return }
            codeBlock = block
            isCodeBlockHeader = span.isCodeBlockHeader
            codeBlockStyle = span.style
        }
    }
    public let source: String
    public let width: Int
    public let lines: [Line]

    /// Adds presentation rows without adding characters to the selectable source.
    public func paddedVertically(_ rows: Int) -> TextLayout {
        let padding = Array(repeating: Line(), count: max(0, rows))
        return TextLayout(source: source, width: width, lines: padding + lines + padding)
    }

    /// Keeps the last wrapped rows while retaining source indices for copying.
    ///
    /// Reserved header rows and the omission marker are presentation only.
    public func tailPreview(rows: Int, reservedHeaderRows: Int = 0) -> TextLayout {
        let headerCount = min(lines.count, max(0, reservedHeaderRows))
        let body = Array(lines.dropFirst(headerCount))
        let count = max(1, rows)
        var visible = Array(repeating: Line(), count: headerCount)
        if body.count > count {
            var omission = Line()
            omission.glyphs = [
                Glyph(
                    text: "…", column: 0, width: 1, sourceRange: source.endIndex..<source.endIndex,
                    style: nil, link: nil)
            ]
            visible.append(omission)
        }
        visible.append(contentsOf: body.suffix(count))
        return TextLayout(source: source, width: width, lines: visible)
    }

    /// Keeps the first wrapped content rows and any vertical padding, with a display-only omission mark.
    public func headPreview(rows: Int, verticalPadding: Int = 0) -> TextLayout {
        let padding = max(0, verticalPadding)
        let visibleContent = max(1, rows)
        guard lines.count > visibleContent + padding * 2 else { return self }

        var visible = Array(lines.prefix(padding + visibleContent))
        var last = visible.removeLast()
        let textLimit = max(0, width - 2)
        last.glyphs.removeAll { $0.column + $0.width > textLimit }
        let nextColumn = last.glyphs.last.map { $0.column + $0.width } ?? 0
        let ellipsisColumn = min(width - 1, nextColumn + (nextColumn < width - 1 ? 1 : 0))
        last.glyphs.append(
            Glyph(
                text: "…", column: ellipsisColumn, width: 1,
                sourceRange: source.endIndex..<source.endIndex, style: last.glyphs.last?.style, link: nil))
        visible.append(last)
        visible.append(contentsOf: lines.suffix(padding))
        return TextLayout(source: source, width: width, lines: visible)
    }

    private init(source: String, width: Int, lines: [Line]) {
        self.source = source
        self.width = width
        self.lines = lines
    }

    public init(
        _ text: String, width: Int, wrapping: TextWrapping = .grapheme,
        measure: (Character) -> Int = terminalCellWidth
    ) {
        self.init([TextSpan(text)], width: width, wrapping: wrapping, measure: measure)
    }

    /// Lays out styled spans as one source string.
    ///
    /// A grapheme crossing a span boundary uses the style of its first scalar,
    /// keeping selection intact.
    public init(
        _ spans: [TextSpan], width: Int, wrapping: TextWrapping = .grapheme,
        measure: (Character) -> Int = terminalCellWidth
    ) {
        // Keep literal newlines and tabs for copying, remove terminal-control characters.
        let pieces = spans.map { span in
            String(
                span.text.unicodeScalars.filter {
                    $0 == "\n" || $0 == "\t" || ($0.value >= 32 && !(0x7f...0x9f).contains($0.value))
                })
        }
        let sanitizedSource = pieces.joined()
        source = sanitizedSource
        self.width = max(1, width)
        var styleEnds: [(byteOffset: Int, span: TextSpan)] = []
        var endByteOffset = 0
        for (span, piece) in zip(spans, pieces) {
            endByteOffset += piece.utf8.count
            styleEnds.append((endByteOffset, span))
        }
        var lines = [Line()]
        var column = 0
        var byteOffset = 0
        var spanIndex = 0
        var startsWord = true
        for index in sanitizedSource.indices {
            let character = sanitizedSource[index]
            let range = index..<sanitizedSource.index(after: index)
            while spanIndex < styleEnds.count && byteOffset >= styleEnds[spanIndex].byteOffset {
                spanIndex += 1
            }
            let sourceSpan = spanIndex < styleEnds.count ? styleEnds[spanIndex].span : nil
            let glyphStyle = sourceSpan?.style
            let glyphLink = sourceSpan?.link
            defer { byteOffset += sanitizedSource[range].utf8.count }
            if character == "\n" {
                lines[lines.count - 1].recordCodeBlock(sourceSpan)
                lines.append(Line())
                column = 0
                startsWord = true
                continue
            }
            if character == "\t" {
                let spaces = 4 - column % 4
                for _ in 0..<spaces {
                    if column == self.width {
                        lines.append(Line())
                        column = 0
                    }
                    lines[lines.count - 1].recordCodeBlock(sourceSpan)
                    lines[lines.count - 1].glyphs.append(
                        Glyph(
                            text: " ", column: column, width: 1, sourceRange: range, style: glyphStyle, link: glyphLink)
                    )
                    column += 1
                }
                startsWord = true
                continue
            }
            if wrapping == .word && startsWord && !character.isWhitespace && column > 0 {
                var wordWidth = 0
                var wordIndex = index
                while wordIndex < sanitizedSource.endIndex {
                    let next = sanitizedSource[wordIndex]
                    if next.isWhitespace { break }
                    wordWidth += max(1, min(2, measure(next)))
                    if wordWidth > self.width { break }
                    wordIndex = sanitizedSource.index(after: wordIndex)
                }
                if wordWidth <= self.width && column + wordWidth > self.width {
                    lines.append(Line())
                    column = 0
                }
            }
            let measured = min(2, max(0, measure(character)))
            let span = max(1, measured)
            if column + span > self.width && column > 0 {
                lines.append(Line())
                column = 0
            }
            // A one-column viewport cannot display a two-column character. Use a visible replacement.
            let glyph = span > self.width ? "�" : measured == 0 ? "◌" + String(character) : String(character)
            let actualWidth = min(span, self.width)
            lines[lines.count - 1].recordCodeBlock(sourceSpan)
            lines[lines.count - 1].glyphs.append(
                Glyph(
                    text: glyph, column: column, width: actualWidth, sourceRange: range, style: glyphStyle,
                    link: glyphLink))
            column += actualWidth
            startsWord = character.isWhitespace
        }
        self.lines = lines
    }

    public func sourceRange(for selection: TextSelection) -> Range<String.Index>? {
        var lower: String.Index?
        var upper: String.Index?
        let start = max(0, selection.first.y)
        let end = min(lines.count - 1, selection.last.y)
        guard start <= end else {
            return nil
        }
        for row in start...end {
            for glyph in lines[row].glyphs where selection.intersects(x: glyph.column, y: row, width: glyph.width) {
                guard !glyph.sourceRange.isEmpty else { continue }
                if lower == nil {
                    lower = glyph.sourceRange.lowerBound
                }
                upper = glyph.sourceRange.upperBound
            }
        }
        guard let lower, let upper else {
            return nil
        }
        return lower..<upper
    }

    public func selectedText(_ selection: TextSelection) -> String {
        sourceRange(for: selection).map {
            String(source[$0])
        } ?? ""
    }

    /// Selects the word or punctuation run under a laid-out cell, across soft wraps.
    public func wordSelection(at point: Point) -> TextSelection? {
        guard let index = sourceIndex(at: point), index < source.endIndex else { return nil }
        let character = source[index]
        guard !character.isWhitespace else { return nil }
        let isWord = character.isLetter || character.isNumber || character == "_"
        func matches(_ character: Character) -> Bool {
            !character.isWhitespace && (character.isLetter || character.isNumber || character == "_") == isWord
        }
        var lower = index
        var upper = source.index(after: index)
        while lower > source.startIndex {
            let previous = source.index(before: lower)
            guard matches(source[previous]) else { break }
            lower = previous
        }
        while upper < source.endIndex, matches(source[upper]) { upper = source.index(after: upper) }
        return selection(for: lower..<upper)
    }

    /// Selects the source line under a cell, including any soft-wrapped display rows.
    public func paragraphSelection(at point: Point) -> TextSelection? {
        guard let index = sourceIndex(at: point), index < source.endIndex else { return nil }
        var lower = index
        var upper = source.index(after: index)
        while lower > source.startIndex {
            let previous = source.index(before: lower)
            guard source[previous] != "\n" else { break }
            lower = previous
        }
        while upper < source.endIndex, source[upper] != "\n" { upper = source.index(after: upper) }
        return selection(for: lower..<upper)
    }

    private func sourceIndex(at point: Point) -> String.Index? {
        guard lines.indices.contains(point.y) else { return nil }
        return lines[point.y].glyphs.first {
            point.x >= $0.column && point.x < $0.column + $0.width && !$0.sourceRange.isEmpty
        }?.sourceRange.lowerBound
    }

    private func selection(for range: Range<String.Index>) -> TextSelection? {
        var first: Point?
        var last: Point?
        for (row, line) in lines.enumerated() {
            for glyph in line.glyphs
            where glyph.sourceRange.lowerBound < range.upperBound
                && glyph.sourceRange.upperBound > range.lowerBound
            {
                if first == nil { first = Point(x: glyph.column, y: row) }
                last = Point(x: glyph.column + glyph.width - 1, y: row)
            }
        }
        guard let first, let last else { return nil }
        return TextSelection(anchor: first, head: last)
    }

    public func paint(
        in area: Rect, rowOffset: Int = 0, selection: TextSelection? = nil,
        style: Style = Style(), buffer: inout Buffer
    ) {
        guard area.width > 0, area.height > 0 else {
            return
        }
        for screenRow in 0..<area.height {
            let row = rowOffset + screenRow
            guard lines.indices.contains(row) else {
                continue
            }
            if lines[row].codeBlock != nil, let codeStyle = lines[row].codeBlockStyle,
                codeStyle.background != .terminalDefault
            {
                for column in 0..<area.width {
                    buffer.put(
                        " ", width: 1, at: Point(x: area.x + column, y: area.y + screenRow), style: codeStyle)
                }
            }
            for glyph in lines[row].glyphs {
                guard glyph.column + glyph.width <= area.width else {
                    continue
                }
                let point = Point(x: area.x + glyph.column, y: area.y + screenRow)
                buffer.put(glyph.text, width: glyph.width, at: point, style: glyph.style ?? style, link: glyph.link)
                if let selection, selection.intersects(x: glyph.column, y: row, width: glyph.width) {
                    buffer.highlight(at: point)
                }
            }
        }
    }
}
