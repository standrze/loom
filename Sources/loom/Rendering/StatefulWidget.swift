/// A widget whose caller-owned state is synchronized with its rendered geometry.
///
/// State may update selection and scroll metrics during drawing. The widget never reads
/// terminal events, starts tasks, or changes terminal modes.
public protocol StatefulWidget {
    associatedtype State
    func render(in area: Rect, buffer: inout Buffer, state: inout State)
}

public extension Frame {
    mutating func render<W: StatefulWidget>(_ widget: W, in area: Rect, state: inout W.State) {
        widget.render(in: area, buffer: &buffer, state: &state)
    }
}
