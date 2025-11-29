// @copyright André Trettin

import Foundation

public struct ChildEntryModel: Identifiable, Equatable, Hashable, Codable {
    public init(id: UUID, childId: UUID, displayState: Int = 0) {
        self.id = id
        self.childId = childId
        self.displayState = displayState
    }

    public let id: UUID
    public let childId: UUID

    public var displayState: Int = 0
}

extension ChildEntryModel: EntryDataAccessable {
    public var name: String {
        get { "Photo" }
        set {}
    }
        
    public static var empty: ChildEntryModel { empty(UUID()) }
    public static func newChild(id: UUID) -> Self {
        ChildEntryModel(id: UUID(), childId: id)
    }

    static public func empty(_ id: UUID) -> ChildEntryModel {
        ChildEntryModel(id: id, childId: UUID())
    }

    public func duplicate() -> ChildEntryModel {
        ChildEntryModel(id: UUID(), childId: childId)
    }
    
    public func filter(with search: String) -> Bool {
        true
    }
}

extension ChildEntryModel: ItemDiffComparable {
    public func merge(_ other: ChildEntryModel) -> ChildEntryModel {
        ChildEntryModel(id: id, childId: other.childId)
    }

    public func isSame(_ other: ChildEntryModel) -> Bool {
        childId == other.childId
    }
}
