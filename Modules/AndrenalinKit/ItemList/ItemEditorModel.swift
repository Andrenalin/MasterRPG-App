// @copyright André Trettin

import Foundation
import Observation
import SwiftUI

@MainActor @Observable
public final class ItemEditorModel: Sendable {
    public init(currentListItem: ItemRowTreeModel? = nil, currentModel: (ModelType)? = nil, categorySelection: ItemListCategory = .all) {
        self.currentListItem = currentListItem
        self.undoManaged = UndoManaged(initialValue: currentModel)
        self.categoryEditModel = CategoryEditModel(selection: categorySelection)
    }

    public var currentModel: ModelType? {
        undoManaged.value
    }

    public internal(set) var currentListItem: ItemRowTreeModel?

    public internal(set) var currentItemId: UUID?
    public var currentEntryId: UUID?
    public var currentSecondaryId: UUID?

    public var zoomNamespaceId: Namespace.ID?
    
    public var activateFocus: Bool = false
    public var activateDetailEditMode: Bool = false

    public var cacheItemListModel: CacheItemListModel = CacheItemListModel()

    public var expandedEntries: [UUID: Bool] = [:]
    public var selected: Set<UUID> = []
    public var selection: [UUID] = []
    public var deleteAlertIds: [UUID] = []

    @ObservationIgnored public internal(set) var searchText: String = ""

    @ObservationIgnored var undoManaged: UndoManaged<ModelType?>

    // MARK: - Properties for the editor
    @ObservationIgnored var categoryEditModel: CategoryEditModel
    @ObservationIgnored var descriptionTextFieldModel = TextFieldModel()
    @ObservationIgnored var hiddenToggleModel = ToggleModel()
    @ObservationIgnored var nameTextFieldModel = TextFieldModel()


    func reset() {
        if undoManaged.value != nil {
            undoManaged.resetValue(nil)
        }
        currentItemId = nil
        currentListItem = nil
        currentEntryId = nil
        expandedEntries = [:]
        selected = []
        selection = []
        deleteAlertIds = []
        cacheItemListModel.resetItemLink()
    }

    public func isExpanded(for entryId: UUID) -> Binding<Bool> {
        Binding {
            self.expandedEntries[entryId, default: false]
        } set: {
            self.expandedEntries[entryId] = $0
        }
    }
}
