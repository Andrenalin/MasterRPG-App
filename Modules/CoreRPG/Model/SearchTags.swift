// @copyright André Trettin

public struct SearchTags: Hashable, Equatable, Identifiable, Sendable {
    public let tag: String
    public var id: String { tag }

    static public let allCategory = SearchTags(tag: "All")
}
