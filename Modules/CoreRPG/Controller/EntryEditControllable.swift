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
    
    var cacheItemListModel: CacheItemListModel { get }
}

public extension EntryEditControllable {
    @MainActor func module(for itemId: UUID) -> NetworkModules {
        editControllable.itemControllable.item(for: itemId)?.module ?? .none
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
        let duplicat = entry.duplicate(name: ItemDataModel.duplicateName(from: entry.name), index: model.entries.count)
        modelContext().insert(duplicat)
        var entries = model.entries
        entries.append(duplicat)
        model.entries = entries
        try? modelContext().save()
        return duplicat.entryId
    }
    
    @MainActor func remove(entry: EditDataModel.DataModel, in model: EditDataModel) {
        var entries = model.entries
        guard let index = entries.firstIndex(where: { $0.entryId == entry.entryId }) else { return }
        entries.remove(at: index)
        model.entries = entries
        modelContext().delete(entry)
        try? modelContext().save()
    }
    
    func rowText(entry: EditDataModel.DataModel) -> String {
        entry.name.isEmpty ? entry.content : "\(entry.name.markDownText()): \(entry.content)"
    }
    
    @MainActor func linkTextModel(for entry: EditDataModel.DataModel, linkController: LinkRootController, searchModel: SearchModel) -> LinkHighlightTextModel {
        let nameText = rowText(entry: entry)
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entry.entryId) else {
            let model = LinkHighlightTextModel(linkController: linkController, text: nameText, highlightedText: searchModel.searchText)
            cacheItemListModel.setItemLink(cacheType: .row, itemId: entry.entryId, linkModel: model)
            return model
        }
        if nameText != linkModel.text {
            linkModel.reset(text: nameText)
        }
        return linkModel
    }
    
    @MainActor func update(entry: EditDataModel.DataModel, name: String, content: String) {
        var changed = entry.name != name.withoutLink()
        entry.name <=> name.withoutLink()
        let links = editControllable.linkRegisterController.linkDataModel(in: content)
        var seenIds: Set<UUID> = []
        var newContent = content
        for link in links {
            guard seenIds.contains(link.id) else {
                seenIds.insert(link.id)
                continue
            }
            let newLink = link.duplicate()
            let oldLinkText = editControllable.linkRegisterController.markDown(for: link)
            guard let range = content.firstRange(of: oldLinkText) else { continue }
            newContent = newContent.replacingOccurrences(of: oldLinkText, with: editControllable.linkRegisterController.markDown(for: newLink), range: range)
            link.modelContext?.insert(newLink)
            try? link.modelContext?.save()
        }
        changed = changed || entry.content != newContent
        entry.content <=> newContent
        if changed {
            cacheItemListModel.reset(cacheType: .row, itemId: entry.entryId, text: rowText(entry: entry))
        }
    }
}
