// © André Trettin

import Foundation

public struct ReferenceUuidLink: Equatable, Hashable {
    public let name: String
    public let id: UUID

    public init(name: String, id: UUID) {
        self.name = name
        self.id = id
    }

    public func url(for scheme: String) -> String {
        "(\(scheme)://\(id.uuidString))"
    }

    public func markDown(for scheme: String) -> String {
        "[\(name)]\(url(for: scheme))"
    }
}

