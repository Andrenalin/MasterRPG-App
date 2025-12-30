// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor @Observable
public final class ItemEditorModel: Sendable {
    public init() {
        self.undoManaged = UndoManaged(initialValue: nil)
    }

    public var currentModel: ModelType? {
        undoManaged.value
    }

    public internal(set) var currentItemId: UUID?
    public var currentEntryId: UUID?
    public var scrollEntryId: UUID?
    
    public var cacheItemListModel: CacheItemListModel = CacheItemListModel()

    @ObservationIgnored var undoManaged: UndoManaged<ModelType?>

    func reset() {
        if undoManaged.value != nil {
            undoManaged.resetValue(nil)
        }
        currentItemId = nil
        currentEntryId = nil
        cacheItemListModel.resetItemLink()
    }
}
