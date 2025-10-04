import Foundation

public extension UUID {
    /// A lightweight wrapper type used by macro-generated code expecting `UUID.PartiallyGenerated`.
    struct PartiallyGenerated: Equatable, Hashable, Codable, Sendable {
        public var value: UUID?
        public init(_ value: UUID? = nil) { self.value = value }
    }
}

public extension Optional where Wrapped == UUID {
    /// Allow macro-generated references to `UUID?.PartiallyGenerated` to resolve.
    typealias PartiallyGenerated = UUID.PartiallyGenerated
}
