// @copyright André Trettin

import Foundation

public protocol EntryDataAccessable {
    var id: UUID { get }
    var name: String { get }
    var parentId: UUID? { get }
    var childId: UUID? { get }
}

public extension EntryDataAccessable {
    var childId: UUID? { nil }
    var parentId: UUID? { nil }
}
