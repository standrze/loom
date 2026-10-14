import Foundation
import weft

/// An identity that remains stable when entries before it change height or are removed.
public struct TextDocumentEntryID: Equatable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// Cached entry layouts used for drawing, scrolling, selection, and navigation.
///
/// Appending or replacing text rebuilds only the affected entry. Scrolling and
/// selection reuse cached geometry. Entry IDs survive reflow and folding.
public struct TextDocument: Sendable {
    public private(set) var layouts: [TextLayout] = []
    public private(set) var starts: [Int] = []
    public private(set) var width: Int
    public private(set) var layoutBuildCount = 0

    private struct Entry: Sendable {
        let id: TextDocumentEntryID
        var spans: [TextSpan]
        var background: Color
        let wrapping: TextWrapping
        var wrapOptions = TextWrapOptions()
        var verticalPadding = 0
        var collapsedSummary: [TextSpan]?
        var widthLimit: Int?
        var trailingReservedColumns = 0
        var displayPrefix: TextSpan?
        var continuationPrefix = ""
        var tailRows: Int?
        var headRows: Int?
        var reservedHeaderRows = 0
        var tailOmissionStyle: Style?
        var hidden = false
    }

    private var entries: [Entry] = []
    private var nextID = 0

    public var rowCount: Int {
        guard let lastLayout = layouts.last else { return 0 }
        return starts.last! + (entries.last?.hidden == true ? 0 : lastLayout.lines.count)
    }

    public init(width: Int) {
        self.width = max(1, width)
    }

    /// Appends an entry, separated from its predecessor by one blank row.
    @discardableResult
    public mutating func append(
        _ text: String, wrapping: TextWrapping = .grapheme, options: TextWrapOptions = TextWrapOptions()
    ) -> TextDocumentEntryID {
        append([TextSpan(text)], wrapping: wrapping, options: options)
    }

    /// Appends styled text and returns a stable identity for later updates.
    @discardableResult
    public mutating func append(
        _ spans: [TextSpan], background: Color = .terminalDefault,
        wrapping: TextWrapping = .grapheme, verticalPadding: Int = 0, options: TextWrapOptions = TextWrapOptions()
    ) -> TextDocumentEntryID {
        let id = TextDocumentEntryID(rawValue: nextID)
        nextID += 1
        let entry = Entry(
            id: id, spans: spans, background: background, wrapping: wrapping, wrapOptions: options,
            verticalPadding: max(0, verticalPadding))
        starts.append(0)
        entries.append(entry)
        layouts.append(makeLayout(entry))
        layoutBuildCount += 1
        rebuildStarts(after: entries.count - 2)
        return id
    }

    /// Inserts styled text before an existing entry without changing any existing identities.
    @discardableResult
    public mutating func insert(
        _ spans: [TextSpan], before target: TextDocumentEntryID, background: Color = .terminalDefault,
        wrapping: TextWrapping = .grapheme, options: TextWrapOptions = TextWrapOptions()
    ) -> TextDocumentEntryID? {
        guard let index = entries.firstIndex(where: { $0.id == target }) else { return nil }
        let id = TextDocumentEntryID(rawValue: nextID)
        nextID += 1
        let entry = Entry(id: id, spans: spans, background: background, wrapping: wrapping, wrapOptions: options)
        entries.insert(entry, at: index)
        layouts.insert(makeLayout(entry), at: index)
        starts.insert(0, at: index)
        layoutBuildCount += 1
        rebuildStarts(after: index - 1)
        return id
    }

    /// Removes an entry while leaving every other entry identity unchanged.
    public mutating func remove(_ id: TextDocumentEntryID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index)
        layouts.remove(at: index)
        starts.remove(at: index)
        rebuildStarts(after: index - 1)
    }

    /// Replaces the last entry, or appends it when the document is empty.
    public mutating func replaceLast(_ text: String) {
        replaceLast([TextSpan(text)])
    }

    /// Replaces the last entry while retaining its background, wrapping, and identity.
    public mutating func replaceLast(_ spans: [TextSpan]) {
        guard let id = entries.last?.id else {
            append(spans)
            return
        }
        replace(id, with: spans)
    }

    /// Replaces one entry without changing its identity or collapse state.
    public mutating func replace(_ id: TextDocumentEntryID, with spans: [TextSpan]) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let old = entries[index].spans
        let unchanged =
            old.count == spans.count
            && zip(old, spans).allSatisfy {
                $0.text == $1.text && $0.style == $1.style && $0.link == $1.link
                    && $0.codeBlock == $1.codeBlock && $0.isCodeBlockHeader == $1.isCodeBlockHeader
            }
        guard !unchanged else { return }
        entries[index].spans = spans
        if entries[index].collapsedSummary == nil {
            layouts[index] = makeLayout(entries[index])
            layoutBuildCount += 1
            rebuildStarts(after: index)
        }
    }

    /// Changes presentation spacing without changing source text or entry identity.
    public mutating func setVerticalPadding(_ rows: Int, for id: TextDocumentEntryID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
            entries[index].verticalPadding != max(0, rows)
        else { return }
        entries[index].verticalPadding = max(0, rows)
        layouts[index] = makeLayout(entries[index])
        layoutBuildCount += 1
        rebuildStarts(after: index)
    }

    /// Caps an entry's wrapping width independently of the document viewport.
    public mutating func setWidthLimit(_ columns: Int?, for id: TextDocumentEntryID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let limit = columns.map { max(1, $0) }
        guard entries[index].widthLimit != limit else { return }
        entries[index].widthLimit = limit
        layouts[index] = makeLayout(entries[index])
        layoutBuildCount += 1
        rebuildStarts(after: index)
    }

    /// Reserves terminal cells at the right edge when wrapping an entry.
    ///
    /// The reservation follows document resizes and never changes the selectable source.
    public mutating func setTrailingReservedColumns(_ columns: Int, for id: TextDocumentEntryID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let reserved = max(0, columns)
        guard entries[index].trailingReservedColumns != reserved else { return }
        entries[index].trailingReservedColumns = reserved
        layouts[index] = makeLayout(entries[index])
        layoutBuildCount += 1
        rebuildStarts(after: index)
    }

    /// Adds a visible, non-copyable prefix to each display line of an entry.
    ///
    /// Wrapped and explicit new lines use the continuation prefix. The stored spans,
    /// search text, and copied selections remain the original source.
    public mutating func setDisplayPrefix(
        _ prefix: TextSpan, continuation: String, for id: TextDocumentEntryID
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].displayPrefix = TextSpan(prefix.text, style: prefix.style, copyable: false, patch: prefix.patch)
        entries[index].continuationPrefix = continuation
        layouts[index] = makeLayout(entries[index])
        layoutBuildCount += 1
        rebuildStarts(after: index)
    }

    /// Shows a one-line summary in place of an entry while retaining its full source.
    public mutating func setCollapsed(
        _ collapsed: Bool, for id: TextDocumentEntryID, summary: [TextSpan] = [TextSpan("▶ Collapsed")]
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        guard collapsed != (entries[index].collapsedSummary != nil) else { return }
        entries[index].collapsedSummary = collapsed ? summary : nil
        layouts[index] = makeLayout(entries[index])
        layoutBuildCount += 1
        rebuildStarts(after: index)
    }

    /// Reports whether the entry is currently represented by a summary.
    public func isCollapsed(_ id: TextDocumentEntryID) -> Bool {
        entries.first(where: { $0.id == id })?.collapsedSummary != nil
    }

    /// Removes an entry from layout without removing its source, identity, or fold state.
    public mutating func setHidden(_ hidden: Bool, for id: TextDocumentEntryID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].hidden != hidden else { return }
        entries[index].hidden = hidden
        rebuildStarts(after: index - 1)
    }

    public func isHidden(_ id: TextDocumentEntryID) -> Bool {
        entries.first(where: { $0.id == id })?.hidden == true
    }

    /// Limits expanded presentation to the last wrapped rows; nil restores all rows.
    ///
    /// Full source remains available through spans and search, including after resize.
    public mutating func setTailPreview(
        _ rows: Int?, for id: TextDocumentEntryID, reservedHeaderRows: Int = 0, omissionStyle: Style? = nil
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let rows = rows.map { max(1, $0) }
        let headers = max(0, reservedHeaderRows)
        guard
            entries[index].tailRows != rows || entries[index].reservedHeaderRows != headers
                || entries[index].tailOmissionStyle != omissionStyle
        else { return }
        entries[index].tailRows = rows
        entries[index].reservedHeaderRows = headers
        entries[index].tailOmissionStyle = omissionStyle
        layouts[index] = makeLayout(entries[index])
        layoutBuildCount += 1
        rebuildStarts(after: index)
    }

    /// Limits a prompt to its first wrapped rows while retaining its full source and padding.
    public mutating func setHeadPreview(_ rows: Int?, for id: TextDocumentEntryID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let rows = rows.map { max(1, $0) }
        guard entries[index].headRows != rows else { return }
        entries[index].headRows = rows
        if entries[index].collapsedSummary == nil {
            layouts[index] = makeLayout(entries[index])
            layoutBuildCount += 1
            rebuildStarts(after: index)
        }
    }

    public func hasHeadPreview(_ id: TextDocumentEntryID) -> Bool {
        entries.first(where: { $0.id == id })?.headRows != nil
    }

    /// Returns the entry that contains or immediately precedes a document row.
    public func entryID(at row: Int) -> TextDocumentEntryID? {
        guard !entries.isEmpty else { return nil }
        return entries[firstEntry(at: row)].id
    }

    /// Returns the identity at a layout index, including hidden entries.
    public func entryID(atIndex index: Int) -> TextDocumentEntryID? {
        guard entries.indices.contains(index) else { return nil }
        return entries[index].id
    }

    /// Returns the current first row for an entry identity.
    public func row(for id: TextDocumentEntryID) -> Int? {
        entries.firstIndex(where: { $0.id == id && !$0.hidden }).map { starts[$0] }
    }

    /// Returns an entry's position even when its rows are hidden.
    public func entryIndex(for id: TextDocumentEntryID) -> Int? {
        entries.firstIndex(where: { $0.id == id })
    }

    /// Returns the full styled content, including when the entry is collapsed.
    public func spans(for id: TextDocumentEntryID) -> [TextSpan]? {
        entries.first(where: { $0.id == id })?.spans
    }

    /// Returns the entry's wrapping policy.
    public func wrapping(for id: TextDocumentEntryID) -> TextWrapping? {
        entries.first(where: { $0.id == id })?.wrapping
    }

    /// Finds the next entry containing text, wrapping around at the end.
    ///
    /// Search covers the full source of collapsed entries. The caller can expand
    /// a found entry before showing its contents.
    public func find(_ query: String, after row: Int = -1) -> TextDocumentEntryID? {
        guard !query.isEmpty, !entries.isEmpty else { return nil }
        let first = row < 0 ? 0 : (firstEntry(at: row) + 1) % entries.count
        for offset in 0..<entries.count {
            let entry = entries[(first + offset) % entries.count]
            if entry.spans.map(\.text).joined().range(of: query, options: .caseInsensitive) != nil {
                return entry.id
            }
        }
        return nil
    }

    /// Reflows all entries when the available width changes.
    public mutating func resize(width: Int) {
        let newWidth = max(1, width)
        guard self.width != newWidth else { return }
        self.width = newWidth
        layouts = entries.map { makeLayout($0) }
        layoutBuildCount += entries.count
        rebuildStarts(after: -1)
    }

    /// Restyles cached source and collapsed summaries without changing entry identities or text metadata.
    ///
    /// A theme change must rebuild layouts already on screen. This also retains folding,
    /// tail previews, wrapping, links, and code-block source for later expansion and copying.
    public mutating func restyle(
        style transformStyle: (Style) -> Style, background transformBackground: (Color) -> Color
    ) {
        guard !entries.isEmpty else { return }
        for index in entries.indices {
            entries[index].spans = entries[index].spans.map { restyled($0, using: transformStyle) }
            entries[index].collapsedSummary = entries[index].collapsedSummary?.map {
                restyled($0, using: transformStyle)
            }
            entries[index].tailOmissionStyle = entries[index].tailOmissionStyle.map(transformStyle)
            entries[index].displayPrefix = entries[index].displayPrefix.map { restyled($0, using: transformStyle) }
            entries[index].background = transformBackground(entries[index].background)
        }
        layouts = entries.map { makeLayout($0) }
        layoutBuildCount += entries.count
        rebuildStarts(after: -1)
    }

    public mutating func clear() {
        entries = []
        layouts = []
        starts = []
    }

    /// Copies visible source text across entries, retaining their separation.
    public func selectedText(_ selection: TextSelection) -> String {
        var pieces: [String] = []
        for index in firstEntry(at: selection.first.y)..<layouts.count {
            if starts[index] > selection.last.y { break }
            if entries[index].hidden { continue }
            let entrySelection = TextSelection(
                anchor: Point(x: selection.anchor.x, y: selection.anchor.y - starts[index]),
                head: Point(x: selection.head.x, y: selection.head.y - starts[index])
            )
            let text = layouts[index].selectedText(entrySelection)
            if !text.isEmpty { pieces.append(text) }
        }
        return pieces.joined(separator: "\n\n")
    }

    /// Finds a word under a document cell, retaining entry-relative wrapping and padding.
    public func wordSelection(at point: Point) -> TextSelection? {
        selection(at: point) { $0.wordSelection(at: $1) }
    }

    /// Finds a source paragraph under a document cell, even when it soft-wraps.
    public func paragraphSelection(at point: Point) -> TextSelection? {
        selection(at: point) { $0.paragraphSelection(at: $1) }
    }

    private func selection(
        at point: Point, in layout: (TextLayout, Point) -> TextSelection?
    ) -> TextSelection? {
        guard !entries.isEmpty else { return nil }
        let index = firstEntry(at: point.y)
        let row = point.y - starts[index]
        guard row >= 0, row < layouts[index].lines.count,
            let local = layout(layouts[index], Point(x: point.x, y: row))
        else { return nil }
        return TextSelection(
            anchor: Point(x: local.anchor.x, y: local.anchor.y + starts[index]),
            head: Point(x: local.head.x, y: local.head.y + starts[index]))
    }

    /// Draws the visible document rows into the supplied area.
    public func paint(in area: Rect, scroll: Int, selection: TextSelection?, buffer: inout Buffer) {
        guard !layouts.isEmpty else { return }
        for index in firstEntry(at: scroll)..<layouts.count {
            if entries[index].hidden { continue }
            let entryStart = starts[index]
            if entryStart >= scroll + area.height { break }
            let skippedRows = max(0, scroll - entryStart)
            let visibleOffset = max(0, entryStart - scroll)
            let visibleArea = Rect(
                x: area.x,
                y: area.y + visibleOffset,
                width: area.width,
                height: min(area.height - visibleOffset, layouts[index].lines.count - skippedRows)
            )
            let entrySelection = selection.map { selection in
                TextSelection(
                    anchor: Point(x: selection.anchor.x, y: selection.anchor.y - entryStart),
                    head: Point(x: selection.head.x, y: selection.head.y - entryStart)
                )
            }
            paintBackground(entries[index].background, in: visibleArea, buffer: &buffer)
            layouts[index].paint(in: visibleArea, rowOffset: skippedRows, selection: entrySelection, buffer: &buffer)
        }
    }

    private func makeLayout(_ entry: Entry) -> TextLayout {
        let layout = fullLayout(entry)
        guard entry.collapsedSummary == nil else { return layout }
        if let rows = entry.headRows {
            return layout.headPreview(rows: rows, verticalPadding: entry.verticalPadding)
        }
        guard let rows = entry.tailRows else { return layout }
        return layout.tailPreview(
            rows: rows, reservedHeaderRows: entry.reservedHeaderRows, omissionStyle: entry.tailOmissionStyle)
    }

    private func restyled(_ span: TextSpan, using transform: (Style) -> Style) -> TextSpan {
        TextSpan(
            span.text, style: span.style.map(transform), link: span.link,
            codeBlock: span.codeBlock, isCodeBlockHeader: span.isCodeBlockHeader, copyable: span.copyable,
            sourceLine: span.sourceLine, patch: span.patch)
    }

    private func fullLayout(_ entry: Entry) -> TextLayout {
        let available = max(1, width - entry.trailingReservedColumns)
        let width = min(available, entry.widthLimit ?? available)
        let spans = presentationSpans(entry.collapsedSummary ?? entry.spans, for: entry)
        let continuation = entry.displayPrefix.map {
            TextSpan(entry.continuationPrefix, style: $0.style, copyable: false, patch: $0.patch)
        }
        guard entry.background != .terminalDefault else {
            return TextLayout(
                spans, width: width, wrapping: entry.wrapping, continuationPrefix: continuation,
                options: entry.wrapOptions
            )
            .paddedVertically(entry.verticalPadding)
        }
        let filled = spans.map { span in
            var style = span.style ?? Style()
            if style.background == .terminalDefault { style.background = entry.background }
            return TextSpan(
                span.text, style: style, link: span.link,
                codeBlock: span.codeBlock, isCodeBlockHeader: span.isCodeBlockHeader, copyable: span.copyable,
                sourceLine: span.sourceLine, patch: span.patch)
        }
        return TextLayout(
            filled, width: width, wrapping: entry.wrapping, continuationPrefix: continuation, options: entry.wrapOptions
        )
        .paddedVertically(entry.verticalPadding)
    }

    private func presentationSpans(_ spans: [TextSpan], for entry: Entry) -> [TextSpan] {
        guard let prefix = entry.displayPrefix else { return spans }
        var result = [prefix]
        for span in spans {
            let parts = span.text.components(separatedBy: "\n")
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    result.append(TextSpan("\n", style: span.style, copyable: span.copyable, patch: span.patch))
                    result.append(
                        TextSpan(entry.continuationPrefix, style: prefix.style, copyable: false, patch: prefix.patch))
                }
                if !part.isEmpty {
                    result.append(
                        TextSpan(
                            part, style: span.style, link: span.link, codeBlock: span.codeBlock,
                            isCodeBlockHeader: span.isCodeBlockHeader, copyable: span.copyable,
                            sourceLine: span.sourceLine, patch: span.patch))
                }
            }
        }
        return result
    }

    private mutating func rebuildStarts(after index: Int) {
        guard !entries.isEmpty else {
            starts = []
            return
        }
        if starts.count != entries.count {
            starts = Array(repeating: 0, count: entries.count)
        }
        let first = max(0, index + 1)
        for current in first..<entries.count {
            guard current > 0 else {
                starts[current] = 0
                continue
            }
            let previous = current - 1
            let ending = starts[previous] + (entries[previous].hidden ? 0 : layouts[previous].lines.count)
            starts[current] = ending + (!entries[current].hidden && ending > 0 ? 1 : 0)
        }
    }

    private func paintBackground(_ background: Color, in area: Rect, buffer: inout Buffer) {
        guard background != .terminalDefault else { return }
        let left = max(0, area.x)
        let top = max(0, area.y)
        let right = min(buffer.width, area.maxX)
        let bottom = min(buffer.height, area.maxY)
        guard left < right, top < bottom else { return }
        let style = Style(background: background)
        for y in top..<bottom {
            for x in left..<right {
                buffer.put(" ", width: 1, at: Point(x: x, y: y), style: style)
            }
        }
    }

    private func firstEntry(at row: Int) -> Int {
        guard !starts.isEmpty else { return 0 }
        var lowerBound = 0
        var upperBound = starts.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if starts[middle] <= row { lowerBound = middle + 1 } else { upperBound = middle }
        }
        return max(0, lowerBound - 1)
    }
}
