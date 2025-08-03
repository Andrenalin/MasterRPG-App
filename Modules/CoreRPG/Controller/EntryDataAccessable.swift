// @copyright André Trettin

import Foundation

public protocol EntryDataAccessable {
    var id: UUID { get }
    var index: Int { get set }
    var name: String { get }
    var parentId: UUID? { get }
    var childId: UUID? { get }
}

public extension EntryDataAccessable {
    var childId: UUID? { nil }
    var parentId: UUID? { nil }
    var index: Int {
        get { 0 }
        set {}
    }
}
