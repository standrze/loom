import weft

/// How text moves to a new terminal row when it reaches the available cells.
public enum TextWrapping: Equatable, Sendable {
    case grapheme
    case word
    /// Only explicit newlines start rows; paint a viewport over the full lines.
    case none
}

/// Optional wrapping controls.
///
/// Defaults preserve existing layout and literal source copying.
public struct TextWrapOptions: Equatable, Sendable {
    public var trimLeadingWhitespace: Bool
    public var breakLongWords: Bool
    /// Number of cells emitted for each tab, independent of its column.
    public var tabWidth: Int

    public init(trimLeadingWhitespace: Bool = false, breakLongWords: Bool = true, tabWidth: Int = 4) {
        self.trimLeadingWhitespace = trimLeadingWhitespace
        self.breakLongWords = breakLongWords
        self.tabWidth = max(1, tabWidth)
    }
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
        /// Changes resolved over the explicit glyph style or the inherited paint style.
        public let patch: StylePatch?
        public let link: String?
        public let copyable: Bool

        init(
            text: String, column: Int, width: Int, sourceRange: Range<String.Index>,
            style: Style?, patch: StylePatch? = nil, link: String?, copyable: Bool
        ) {
            self.text = text
            self.column = column
            self.width = width
            self.sourceRange = sourceRange
            self.style = style
            self.patch = patch
            self.link = link
            self.copyable = copyable
        }
    }
    public struct Line: Sendable {
        public var glyphs: [Glyph] = []
        /// Nil inherits the paragraph's alignment; soft wraps retain their source line's value.
        public var alignment: CellAlignment?
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
    private let nonCopyableRanges: [Range<String.Index>]

    /// Adds presentation rows without adding characters to the selectable source.
    public func paddedVertically(_ rows: Int) -> TextLayout {
        let padding = Array(repeating: Line(), count: max(0, rows))
        return TextLayout(
            source: source, width: width, lines: padding + lines + padding,
            nonCopyableRanges: nonCopyableRanges)
    }

    /// Keeps the last wrapped rows while retaining source indices for copying.
    ///
    /// Reserved header rows and the omission marker are presentation only.
    public func tailPreview(rows: Int, reservedHeaderRows: Int = 0, omissionStyle: Style? = nil) -> TextLayout {
        let headerCount = min(lines.count, max(0, reservedHeaderRows))
        let body = Array(lines.dropFirst(headerCount))
        let count = max(1, rows)
        var visible = Array(repeating: Line(), count: headerCount)
        if body.count > count {
            var omission = Line()
            omission.glyphs = [
                Glyph(
                    text: "…", column: 0, width: 1, sourceRange: source.endIndex..<source.endIndex,
                    style: omissionStyle, link: nil, copyable: false)
            ]
            visible.append(omission)
        }
        visible.append(contentsOf: body.suffix(count))
        return TextLayout(source: source, width: width, lines: visible, nonCopyableRanges: nonCopyableRanges)
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
                sourceRange: source.endIndex..<source.endIndex, style: last.glyphs.last?.style,
                patch: last.glyphs.last?.patch, link: nil,
                copyable: false))
        visible.append(last)
        visible.append(contentsOf: lines.suffix(padding))
        return TextLayout(source: source, width: width, lines: visible, nonCopyableRanges: nonCopyableRanges)
    }

    private init(
        source: String, width: Int, lines: [Line], nonCopyableRanges: [Range<String.Index>]
    ) {
        self.source = source
        self.width = width
        self.lines = lines
        self.nonCopyableRanges = nonCopyableRanges
    }

    public init(
        _ text: String, width: Int, wrapping: TextWrapping = .grapheme, options: TextWrapOptions = TextWrapOptions(),
        lineAlignments: [CellAlignment?] = [],
        measure: (Character) -> Int = terminalCellWidth
    ) {
        self.init(
            [TextSpan(text)], width: width, wrapping: wrapping, options: options,
            lineAlignments: lineAlignments, measure: measure)
    }

    /// Joins styled lines with literal newlines, retaining per-line alignment on soft wraps.
    public init(
        lines: [TextLine], width: Int, wrapping: TextWrapping = .grapheme,
        options: TextWrapOptions = TextWrapOptions(), measure: (Character) -> Int = terminalCellWidth
    ) {
        var spans: [TextSpan] = []
        var alignments: [CellAlignment?] = []
        for (index, line) in lines.enumerated() {
            if index > 0 { spans.append(TextSpan("\n")) }
            spans.append(contentsOf: line.spans)
            let newlines = line.spans.reduce(0) { count, span in
                count + span.text.unicodeScalars.filter { $0 == "\n" }.count
            }
            alignments.append(contentsOf: repeatElement(line.alignment, count: newlines + 1))
        }
        self.init(
            spans, width: width, wrapping: wrapping, options: options,
            lineAlignments: alignments, measure: measure)
    }

    /// Lays out styled spans as one source string.
    ///
    /// A grapheme crossing a span boundary uses the style and patch of its first scalar,
    /// keeping selection intact. An explicit continuation prefix overrides repeated
    /// display-only leading glyphs on soft wraps, without entering copied text.
    public init(
        _ spans: [TextSpan], width: Int, wrapping: TextWrapping = .grapheme,
        continuationPrefix: TextSpan? = nil, options: TextWrapOptions = TextWrapOptions(),
        lineAlignments: [CellAlignment?] = [],
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
        // A logical unwrapped line is limited by its input size, not the viewport.
        // Four cells per Character cover tab expansion without giant allocations.
        let capacity = sanitizedSource.count.multipliedReportingOverflow(by: max(2, options.tabWidth))
        let unwrappedWidth = capacity.overflow ? Int.max : max(2, capacity.partialValue)
        let layoutWidth = wrapping == .none ? unwrappedWidth : max(1, width)
        self.width = max(1, width)
        var nonCopyableRanges: [Range<String.Index>] = []
        var styleEnds: [(byteOffset: Int, span: TextSpan)] = []
        var endByteOffset = 0
        for (span, piece) in zip(spans, pieces) {
            let startByteOffset = endByteOffset
            endByteOffset += piece.utf8.count
            if !span.copyable && startByteOffset < endByteOffset {
                let lower = sanitizedSource.utf8.index(sanitizedSource.utf8.startIndex, offsetBy: startByteOffset)
                let upper = sanitizedSource.utf8.index(sanitizedSource.utf8.startIndex, offsetBy: endByteOffset)
                nonCopyableRanges.append(lower..<upper)
            }
            styleEnds.append((endByteOffset, span))
        }
        self.nonCopyableRanges = nonCopyableRanges
        var logicalLine = 0
        var lines = [Line(alignment: lineAlignments.first ?? nil)]
        var column = 0
        var byteOffset = 0
        var spanIndex = 0
        var startsWord = true
        var quotePrefix: [Glyph] = []
        var quotePrefixWidth = 0
        var readingPrefix = true
        var hasCopyableContent = false
        var softWrapped = false
        var longWord = false

        let explicitPrefix = continuationPrefix.map {
            TextLayout([$0], width: layoutWidth, measure: measure).lines.first?.glyphs ?? []
        }

        func beginWrappedLine() {
            softWrapped = true
            let prefix = explicitPrefix ?? quotePrefix
            let prefixWidth = explicitPrefix.map { $0.reduce(0) { $0 + $1.width } } ?? quotePrefixWidth
            let repeatsPrefix = !readingPrefix && prefixWidth + 2 <= layoutWidth
            lines.append(Line(alignment: lines.last?.alignment))
            column = 0
            hasCopyableContent = false
            guard repeatsPrefix else { return }
            for glyph in prefix {
                lines[lines.count - 1].glyphs.append(
                    Glyph(
                        text: glyph.text, column: column, width: glyph.width,
                        sourceRange: sanitizedSource.endIndex..<sanitizedSource.endIndex,
                        style: glyph.style, patch: glyph.patch, link: nil, copyable: false))
                column += glyph.width
            }
        }

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
                logicalLine += 1
                lines.append(
                    Line(alignment: lineAlignments.indices.contains(logicalLine) ? lineAlignments[logicalLine] : nil))
                column = 0
                startsWord = true
                softWrapped = false
                longWord = false
                quotePrefix = []
                quotePrefixWidth = 0
                readingPrefix = true
                hasCopyableContent = false
                continue
            }
            // Trim before creating a soft-wrap row, so trailing whitespace cannot add an empty row.
            if options.trimLeadingWhitespace && character.isWhitespace
                && ((softWrapped && !hasCopyableContent) || column >= layoutWidth)
            {
                startsWord = true
                longWord = false
                continue
            }
            if character == "\t" {
                for _ in 0..<max(1, options.tabWidth) {
                    if options.trimLeadingWhitespace && column >= layoutWidth { continue }
                    if column == layoutWidth { beginWrappedLine() }
                    if options.trimLeadingWhitespace && softWrapped && !hasCopyableContent { continue }
                    lines[lines.count - 1].recordCodeBlock(sourceSpan)
                    lines[lines.count - 1].glyphs.append(
                        Glyph(
                            text: " ", column: column, width: 1, sourceRange: range, style: glyphStyle,
                            patch: sourceSpan?.patch, link: glyphLink,
                            copyable: sourceSpan?.copyable ?? true)
                    )
                    column += 1
                    if sourceSpan?.copyable ?? true {
                        hasCopyableContent = true
                        readingPrefix = false
                    }
                }
                startsWord = true
                continue
            }
            if wrapping == .word && startsWord && !character.isWhitespace {
                var wordWidth = 0
                var wordIndex = index
                while wordIndex < sanitizedSource.endIndex {
                    let next = sanitizedSource[wordIndex]
                    if next.isWhitespace { break }
                    wordWidth += max(1, min(2, measure(next)))
                    if wordWidth > layoutWidth { break }
                    wordIndex = sanitizedSource.index(after: wordIndex)
                }
                longWord = wordWidth > layoutWidth
                if hasCopyableContent && column + wordWidth > layoutWidth
                    && (wordWidth <= layoutWidth || !options.breakLongWords)
                {
                    beginWrappedLine()
                }
            }
            let measured = min(2, max(0, measure(character)))
            let span = max(1, measured)
            if options.trimLeadingWhitespace && character.isWhitespace && column + span > layoutWidth {
                continue
            }
            if column + span > layoutWidth && column > 0
                && !(wrapping == .word && longWord && !options.breakLongWords && !character.isWhitespace)
            {
                beginWrappedLine()
            }
            if options.trimLeadingWhitespace && softWrapped && !hasCopyableContent && character.isWhitespace {
                continue
            }
            // A one-column viewport cannot display a two-column character. Use a visible replacement.
            let glyph = span > layoutWidth ? "�" : measured == 0 ? "◌" + String(character) : String(character)
            let actualWidth = min(span, layoutWidth)
            lines[lines.count - 1].recordCodeBlock(sourceSpan)
            lines[lines.count - 1].glyphs.append(
                Glyph(
                    text: glyph, column: column, width: actualWidth, sourceRange: range, style: glyphStyle,
                    patch: sourceSpan?.patch,
                    link: glyphLink, copyable: sourceSpan?.copyable ?? true))
            if readingPrefix {
                if sourceSpan?.copyable == false {
                    quotePrefix.append(
                        Glyph(
                            text: glyph, column: quotePrefixWidth, width: actualWidth,
                            sourceRange: sanitizedSource.endIndex..<sanitizedSource.endIndex,
                            style: glyphStyle, patch: sourceSpan?.patch, link: nil, copyable: false))
                    quotePrefixWidth += actualWidth
                } else {
                    readingPrefix = false
                }
            }
            if sourceSpan?.copyable ?? true { hasCopyableContent = true }
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
                guard !glyph.sourceRange.isEmpty, glyph.copyable else { continue }
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
        guard let range = sourceRange(for: selection) else { return "" }
        var result = ""
        var cursor = range.lowerBound
        for excluded in nonCopyableRanges where excluded.upperBound > cursor && excluded.lowerBound < range.upperBound {
            if excluded.lowerBound > cursor {
                result += source[cursor..<excluded.lowerBound]
            }
            cursor = min(range.upperBound, excluded.upperBound)
            if cursor == range.upperBound { break }
        }
        if cursor < range.upperBound { result += source[cursor..<range.upperBound] }
        return result
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
            point.x >= $0.column && point.x < $0.column + $0.width && !$0.sourceRange.isEmpty && $0.copyable
        }?.sourceRange.lowerBound
    }

    private func selection(for range: Range<String.Index>) -> TextSelection? {
        var first: Point?
        var last: Point?
        for (row, line) in lines.enumerated() {
            for glyph in line.glyphs
            where glyph.copyable && glyph.sourceRange.lowerBound < range.upperBound
                && glyph.sourceRange.upperBound > range.lowerBound
            {
                if first == nil { first = Point(x: glyph.column, y: row) }
                last = Point(x: glyph.column + glyph.width - 1, y: row)
            }
        }
        guard let first, let last else { return nil }
        return TextSelection(anchor: first, head: last)
    }

    /// The content-to-viewport shift for a row.
    ///
    /// Overwide lines stay start aligned.
    public func horizontalOrigin(forRow row: Int, viewportWidth: Int, alignment: CellAlignment = .left) -> Int {
        guard lines.indices.contains(row) else { return 0 }
        let lineWidth = lines[row].glyphs.last.map { $0.column + $0.width } ?? 0
        let available = max(0, viewportWidth - min(max(0, viewportWidth), lineWidth))
        switch lines[row].alignment ?? alignment {
        case .left: return 0
        case .center: return available / 2
        case .right: return available
        }
    }

    /// Converts an absolute viewport cell to the logical content coordinates used by selections.
    ///
    /// Blank alignment padding and cells without a copyable glyph return nil.
    public func contentPoint(
        at point: Point, in area: Rect, rowOffset: Int = 0, columnOffset: Int = 0,
        alignment: CellAlignment = .left
    ) -> Point? {
        guard area.contains(point) else { return nil }
        let row = rowOffset.addingReportingOverflow(point.y - area.y)
        guard !row.overflow, lines.indices.contains(row.partialValue) else { return nil }
        let origin = horizontalOrigin(forRow: row.partialValue, viewportWidth: area.width, alignment: alignment)
        let offset = max(0, columnOffset)
        let local = point.x - area.x - origin
        let column = local.addingReportingOverflow(offset)
        guard !column.overflow else { return nil }
        let content = Point(x: column.partialValue, y: row.partialValue)
        guard
            let glyph = lines[content.y].glyphs.first(where: {
                content.x >= $0.column && content.x < $0.column + $0.width && $0.copyable
            })
        else { return nil }
        let visibleColumn = glyph.column - offset + origin
        guard visibleColumn >= 0, visibleColumn + glyph.width <= area.width else { return nil }
        return content
    }

    /// Converts logical content coordinates to absolute viewport coordinates.
    public func viewportPoint(
        for point: Point, in area: Rect, rowOffset: Int = 0, columnOffset: Int = 0,
        alignment: CellAlignment = .left
    ) -> Point? {
        guard lines.indices.contains(point.y) else { return nil }
        let origin = horizontalOrigin(forRow: point.y, viewportWidth: area.width, alignment: alignment)
        let shifted = point.x.subtractingReportingOverflow(max(0, columnOffset))
        guard !shifted.overflow else { return nil }
        let x = shifted.partialValue.addingReportingOverflow(origin)
        let y = point.y.subtractingReportingOverflow(rowOffset)
        guard !x.overflow, !y.overflow, x.partialValue >= 0, x.partialValue < area.width,
            y.partialValue >= 0, y.partialValue < area.height
        else { return nil }
        if let glyph = lines[point.y].glyphs.first(where: { point.x >= $0.column && point.x < $0.column + $0.width }) {
            let leading = glyph.column - max(0, columnOffset) + origin
            guard leading >= 0, leading + glyph.width <= area.width else { return nil }
        }
        return Point(x: area.x + x.partialValue, y: area.y + y.partialValue)
    }

    public func paint(
        in area: Rect, rowOffset: Int = 0, selection: TextSelection? = nil,
        style: Style = Style(), columnOffset: Int = 0, alignment: CellAlignment = .left,
        buffer: inout Buffer
    ) {
        guard area.width > 0, area.height > 0 else { return }
        let horizontal = max(0, columnOffset)
        buffer.withClip(area) { buffer in
            for screenRow in 0..<area.height {
                let sum = rowOffset.addingReportingOverflow(screenRow)
                guard !sum.overflow, lines.indices.contains(sum.partialValue) else { continue }
                let row = sum.partialValue
                let origin = horizontalOrigin(forRow: row, viewportWidth: area.width, alignment: alignment)
                if lines[row].codeBlock != nil, let codeStyle = lines[row].codeBlockStyle,
                    codeStyle.background != .terminalDefault
                {
                    for column in 0..<area.width {
                        buffer.put(
                            " ", width: 1, at: Point(x: area.x + column, y: area.y + screenRow), style: codeStyle)
                    }
                }
                for glyph in lines[row].glyphs {
                    let column = glyph.column - horizontal + origin
                    guard column >= 0, column <= area.width - glyph.width else { continue }
                    let point = Point(x: area.x + column, y: area.y + screenRow)
                    buffer.put(
                        glyph.text, width: glyph.width, at: point,
                        style: (glyph.style ?? style).applying(glyph.patch ?? StylePatch()), link: glyph.link)
                    if let selection, glyph.copyable,
                        selection.intersects(x: glyph.column, y: row, width: glyph.width)
                    {
                        buffer.highlight(at: point)
                    }
                }
            }
        }
    }
}
