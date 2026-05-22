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

    public var hasChangedEntries: Int = 0

    public var deactivateEntryEditor: Bool = false
    
    public var cacheItemListModel: CacheItemListModel = CacheItemListModel()

    @ObservationIgnored public var undoManaged: UndoManaged<ModelType?>

    func reset() {
        if undoManaged.value != nil {
            undoManaged.resetValue(nil)
        }
        cacheItemListModel.resetItemLink()
    }
}
