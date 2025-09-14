// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

@MainActor @Observable
public final class EntryEditorModel: Sendable {
    public init(currentEntryId: UUID? = nil) {
        self.currentEntryId = currentEntryId
    }
    
    public var currentEntryId: UUID?
    public var zoomNamespaceId: Namespace.ID?
}

public protocol EntryPersistentModel: PersistentModel {
    var itemId: UUID { get }
    var entryId: UUID { get }
    var index: Int { get set }
    var name: String { get set }
    var content: String { get set }
    
    func duplicate(name: String, index: Int) -> Self
}

public protocol EntryEditModel {
    associatedtype DataModel: EntryPersistentModel
    var itemId: UUID { get }
    var entries: [DataModel] { get nonmutating set }
    
    subscript(id: UUID) -> DataModel { get }
}

public protocol EntryEditControllable: Sendable {
    associatedtype EditDataModel: EntryEditModel
    
    var editControllable: EditControllable { get }
    var editorModel: EntryEditorModel { get }
}

public extension EntryEditControllable {
    @MainActor func module(for itemId: UUID) -> NetworkModules {
        editControllable.itemControllable.modelSync(for: itemId)?.module ?? .none
    }
    
    @MainActor func modelContext() -> ModelContext {
        editControllable.itemControllable.container.mainContext
    }
    
    @MainActor func remove(_ indexSet: IndexSet, from model: EditDataModel) {
        indexSet.forEach { index in
            modelContext().delete(model.entries[index])
        }
        try? modelContext().save()
    }
    
    @MainActor func move(_ indexSet: IndexSet, index: Int, from model: EditDataModel) {
        var changedEntries = model.entries
        changedEntries.move(fromOffsets: indexSet, toOffset: index)
        
        changedEntries.enumerated().forEach { (index, element) in
            element.index <=> index
        }
        try? modelContext().save()
    }
    
    @MainActor func duplicate(entry: EditDataModel.DataModel, in model: EditDataModel) -> UUID {
        let duplicat = entry.duplicate(name: editControllable.duplicateName(from: entry.name), index: model.entries.count)
        modelContext().insert(duplicat)
        var entries = model.entries
        entries.append(duplicat)
        model.entries = entries
        try? modelContext().save()
        return duplicat.entryId
    }
}
