// @copyright André Trettin

import SwiftUI

public struct FakeEntryModel: Identifiable, Equatable, Hashable, Codable, @unchecked Sendable {
    init(id: UUID, name: String, content: String, displayState: Int = 0) {
        self.id = id
        self.name = name
        self.content = content
        self.displayState = displayState
    }
    public var id: UUID
    public var name: String
    var content: String
    public var displayState: Int
}

extension FakeEntryModel: EntryDataAccessable {
    public static var empty: FakeEntryModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> FakeEntryModel {
        FakeEntryModel(id: id, name: "", content: "")
    }

    public func duplicate() -> FakeEntryModel {
        FakeEntryModel(id: UUID(), name: name, content: content, displayState: displayState)
    }
}

extension FakeEntryModel: ItemDiffComparable {
    public func merge(_ other: FakeEntryModel) -> FakeEntryModel {
        self
    }

    public func isSame(_ other: FakeEntryModel) -> Bool {
        name == other.name &&
        content == other.content
    }
}

extension FakeEntryModel: ItemLinkEditable {
    public var textLinkContent: String {
        content
    }
}

extension FakeEntryModel: ItemReferencable {}
