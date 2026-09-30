/// The emitted cells (including requested redraws) and bytes in one rendering pass.
public struct RenderStats: Sendable {
    public let changedCells: Int
    public let bytes: Int
}
