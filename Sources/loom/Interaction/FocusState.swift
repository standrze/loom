/// A keyboard focus destination and optional click region in absolute terminal cells.
public struct FocusTarget<ID: Hashable> {
    public var id: ID
    public var area: Rect?
    public var isEnabled: Bool

    public init(_ id: ID, area: Rect? = nil, isEnabled: Bool = true) {
        self.id = id
        self.area = area
        self.isEnabled = isEnabled
    }
}

/// Application-owned focus traversal, hit testing, and nested modal scopes.
///
/// Only the top scope participates in traversal or mouse focus. Pop a scope to restore
/// the previous focus. The caller still decides how to open/close dialogs and routes
/// events to `focusedID`; no event loop or action dispatch is owned by this type.
public struct FocusState<ID: Hashable> {
    fileprivate struct Scope {
        var targets: [FocusTarget<ID>]
        var focusedID: ID?
    }

    private var scopes: [Scope]
    public var wraps = true
    public var focusedID: ID? { scopes.last?.focusedID }
    public var scopeDepth: Int { scopes.count }

    public init(_ targets: [FocusTarget<ID>] = [], focusedID: ID? = nil) {
        scopes = [Scope(targets: [], focusedID: focusedID)]
        update(targets)
    }

    /// Reconciles the active scope after layout/data changes, skipping disabled targets.
    public mutating func update(_ targets: [FocusTarget<ID>]) {
        precondition(Set(targets.map(\.id)).count == targets.count, "Focus IDs must be unique within a scope")
        let index = scopes.count - 1
        scopes[index].targets = targets
        if !targets.contains(where: { $0.isEnabled && $0.id == scopes[index].focusedID }) {
            scopes[index].focusedID = targets.first(where: \.isEnabled)?.id
        }
    }

    @discardableResult
    public mutating func focus(_ id: ID) -> Bool {
        let index = scopes.count - 1
        guard scopes[index].targets.contains(where: { $0.id == id && $0.isEnabled }) else { return false }
        scopes[index].focusedID = id
        return true
    }

    public mutating func moveForward() { move(backward: false) }
    public mutating func moveBackward() { move(backward: true) }

    public mutating func pushScope(_ targets: [FocusTarget<ID>], focusedID: ID? = nil) {
        scopes.append(Scope(targets: [], focusedID: focusedID))
        update(targets)
    }

    /// Returns false at the root scope, which is never removed.
    @discardableResult
    public mutating func popScope() -> Bool {
        guard scopes.count > 1 else { return false }
        scopes.removeLast()
        return true
    }

    /// Handles Tab, Shift-Tab, or a mouse press.
    ///
    /// Dispatch a press to the newly focused control too.
    @discardableResult
    public mutating func handle(_ event: InputEvent) -> Bool {
        if KeyChord(.tab).matches(event) {
            moveForward()
            return true
        }
        if KeyChord(.tab, modifiers: .shift).matches(event) {
            moveBackward()
            return true
        }
        if case let .mouse(mouse) = event, mouse.kind == .down,
            let target = scopes.last?.targets.last(where: { $0.isEnabled && $0.area?.contains(mouse.position) == true })
        {
            return focus(target.id)
        }
        return false
    }

    private mutating func move(backward: Bool) {
        let index = scopes.count - 1
        let ids = scopes[index].targets.filter(\.isEnabled).map(\.id)
        guard !ids.isEmpty else { return }
        guard let current = ids.firstIndex(where: { $0 == scopes[index].focusedID }) else {
            scopes[index].focusedID = backward ? ids.last : ids.first
            return
        }
        let next = current + (backward ? -1 : 1)
        if ids.indices.contains(next) {
            scopes[index].focusedID = ids[next]
        } else if wraps {
            scopes[index].focusedID = backward ? ids.last : ids.first
        }
    }
}

extension FocusTarget: Sendable where ID: Sendable {}
extension FocusState.Scope: Sendable where ID: Sendable {}
extension FocusState: Sendable where ID: Sendable {}
