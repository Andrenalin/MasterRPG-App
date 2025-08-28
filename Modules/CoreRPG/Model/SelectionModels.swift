// @copyright André Trettin

import Foundation

@MainActor @Observable
public final class SingleSelectionModel {
    public init(itemId: UUID? = nil, entryId: UUID? = nil) {
        self.itemId = itemId
        self.entryId = entryId
    }
    public var itemId: UUID?
    public var entryId: UUID?
}

@MainActor @Observable
public final class MultiSelectionModel {
    public init(selection: [SingleSelectionModel] = []) {
        self.selection = selection
    }
    public var selection: [SingleSelectionModel]
}
