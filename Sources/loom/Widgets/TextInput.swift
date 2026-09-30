import weft

/// A view of a line editor, with configurable borders, wrapping, and a visible cursor.
///
/// The application owns and changes the editor. Create a new widget from that state when
/// drawing; height, text painting, and cursor placement use the same content geometry.
public struct TextInput: Widget {
    public let editor: LineEditor
    public var placeholder: String
    public var prompt: String
    public var maximumRows: Int
    public var minimumRows = 1

    /// Appearance of the outline, independent of the editable text.
    public var borderStyle = Style()
    public var borderType: BorderType = .rounded
    public var borders: BorderEdges = .all
    public var horizontalPadding = 1
    public var textColor = Color.terminalDefault
    public var placeholderColor = Color.indexed(8)

    /// The prompt marker's foreground, or nil to use the editable text color.
    public var promptColor: Color?

    /// Background painted on every cell of the input, including the border.
    ///
    /// An explicit color also applies to padding and text cells. The terminal
    /// default follows the terminal's background color.
    public var fill = Color.terminalDefault

    private var panel: Panel {
        Panel(
            style: carryingFill(borderStyle), borders: borders, borderType: borderType,
            padding: PanelPadding(left: horizontalPadding, right: horizontalPadding)
        )
    }

    public init(_ editor: LineEditor, placeholder: String = "", prompt: String = "❯", maximumRows: Int = 2) {
        self.editor = editor
        self.placeholder = placeholder
        self.prompt = prompt
        self.maximumRows = maximumRows
    }

    /// The preferred height including the selected borders, with at least one input row.
    public func height(width: Int) -> Int {
        let borderRows = (borders.contains(.top) ? 1 : 0) + (borders.contains(.bottom) ? 1 : 0)
        let content = contentArea(in: Rect(width: width, height: borderRows + 1))
        let (text, _) = editor.layout(width: max(1, content.width))
        return min(max(1, maximumRows), max(minimumRows, text.lines.count)) + borderRows
    }

    /// The cursor's absolute terminal cell, or nil when there is no usable input area.
    public func cursor(in area: Rect) -> Point? {
        let content = contentArea(in: area)
        guard content.width > 0, content.height > 0 else { return nil }
        let (_, cursor) = editor.layout(width: content.width)
        let scroll = max(0, cursor.y - content.height + 1)
        return Point(x: content.x + cursor.x, y: content.y + cursor.y - scroll)
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        fillBackground(in: area, buffer: &buffer)
        panel.render(in: area, buffer: &buffer)
        let inner = panel.inner(area)
        let content = contentArea(in: area)
        guard content.width > 0, content.height > 0 else { return }

        let promptArea = Rect(
            x: inner.x, y: inner.y,
            width: max(0, content.x - inner.x - 1), height: 1
        )
        Paragraph(
            TextLayout(promptLine, width: max(1, promptArea.width)),
            style: carryingFill(Style(foreground: promptColor ?? textColor, bold: true))
        )
        .render(in: promptArea, buffer: &buffer)

        if editor.text.isEmpty {
            Paragraph(
                TextLayout(placeholder, width: content.width),
                style: carryingFill(Style(foreground: placeholderColor))
            )
            .render(in: content, buffer: &buffer)
        } else {
            let (text, cursor) = editor.layout(width: content.width)
            let scroll = max(0, cursor.y - content.height + 1)
            Paragraph(text, scroll: scroll, style: carryingFill(Style(foreground: textColor)))
                .render(in: content, buffer: &buffer)
            if let selection = editor.selection {
                let lower = text.source.index(text.source.startIndex, offsetBy: selection.lowerBound)
                let upper = text.source.index(text.source.startIndex, offsetBy: selection.upperBound)
                for screenRow in 0..<content.height where text.lines.indices.contains(scroll + screenRow) {
                    for glyph in text.lines[scroll + screenRow].glyphs {
                        guard glyph.sourceRange.lowerBound < upper && glyph.sourceRange.upperBound > lower,
                            glyph.column + glyph.width <= content.width
                        else { continue }
                        buffer.highlight(at: Point(x: content.x + glyph.column, y: content.y + screenRow))
                    }
                }
            }
        }
    }

    /// Fills the input with blank cells before the border and text, so padding keeps the color.
    private func fillBackground(in area: Rect, buffer: inout Buffer) {
        guard fill != .terminalDefault else {
            return
        }
        let style = Style(background: fill)
        let bounds = buffer.area
        for y in max(area.y, bounds.y)..<min(area.maxY, bounds.maxY) {
            for x in max(area.x, bounds.x)..<min(area.maxX, bounds.maxX) {
                buffer.put(" ", width: 1, at: Point(x: x, y: y), style: style)
            }
        }
    }

    private func carryingFill(_ style: Style) -> Style {
        guard fill != .terminalDefault, style.background == .terminalDefault else {
            return style
        }
        var styled = style
        styled.background = fill
        return styled
    }

    /// The visible text region, excluding borders, padding, and the prompt label.
    public func contentArea(in area: Rect) -> Rect {
        let inner = panel.inner(area)
        let label = TextLayout(promptLine, width: max(1, inner.width))
        let labelWidth = label.lines[0].glyphs.last.map { $0.column + $0.width } ?? 0
        // Preserve at least one input cell, hiding the label if the area is too narrow.
        let promptWidth = min(labelWidth, max(0, inner.width - 2))
        let prefixWidth = promptWidth > 0 ? promptWidth + 1 : 0
        return Rect(
            x: inner.x + prefixWidth, y: inner.y,
            width: inner.width - prefixWidth, height: min(inner.height, max(1, maximumRows))
        )
    }

    private var promptLine: String {
        String(prompt.split(separator: "\n", omittingEmptySubsequences: false).first ?? "")
    }
}
