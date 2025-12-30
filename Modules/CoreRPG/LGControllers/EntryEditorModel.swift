// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor @Observable
public final class EntryEditorModel: Sendable {
    public init(currentEntryId: UUID? = nil) {
        self.currentEntryId = currentEntryId
    }
    
    public var currentEntryId: UUID?
}

public protocol EntryPersistentModel: Identifiable {
    var id: UUID { get }
    var name: String { get set }
    var content: String { get set }
    
    func duplicate(name: String, index: Int) -> Self
}

public protocol EntryEditModel {
    associatedtype DataModel: (EntryDataAccessable & EntryPersistentModel)
    var id: UUID { get }
    var entries: [DataModel] { get nonmutating set }
    
    subscript(id: UUID) -> DataModel { get nonmutating set }
}

public protocol EntryEditControllable: Sendable {
    associatedtype EditDataModel: (ItemDataAccessable & EntryEditModel)
    
    var editControllable: any EditControllable { get }
    var editorModel: EntryEditorModel { get }
    
    var cacheItemListModel: CacheItemListModel { get }
}

public extension EntryEditControllable {
    @MainActor var module: NetworkModules {
        editControllable.itemControllable.config.module
    }
    
    @MainActor func remove(_ indexSet: IndexSet, from model: EditDataModel) {
        editControllable.remove(entry: indexSet, item: model)
    }
    
    @MainActor func move(_ indexSet: IndexSet, index: Int, from model: EditDataModel) {
        editControllable.moveItems(source: indexSet, destination: index, item: model)
    }
            
    @MainActor func duplicate(entry: EditDataModel.DataModel, in model: EditDataModel) -> UUID {
        //ItemDataModel.duplicateName(from: entry.name)
        let duplicat = entry.duplicate(name: entry.name + " Copy", index: model.entries.count)
        editControllable.insert(entry: duplicat, item: model)
        return duplicat.id
    }
    
    @MainActor func remove(entry: EditDataModel.DataModel, in model: EditDataModel) {
        editControllable.remove(entryId: entry.id, item: model)
    }
    
    func rowText(entry: EditDataModel.DataModel) -> String {
        entry.name.isEmpty ? entry.content : "\(entry.name.markDownText()): \(entry.content)"
    }
    
    @MainActor func linkTextModel(for entry: EditDataModel.DataModel, linkController: LinkRootController, searchModel: SearchModel) -> LinkHighlightTextModel {
        let nameText = rowText(entry: entry)
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entry.id) else {
            let model = LinkHighlightTextModel(linkControllable: linkController, text: nameText, highlightedText: searchModel.searchText)
            cacheItemListModel.setItemLink(cacheType: .row, itemId: entry.id, linkModel: model)
            return model
        }
        if nameText != linkModel.text {
            linkModel.reset(text: nameText)
        }
        return linkModel
    }
    
//    @MainActor func update(entry: EditDataModel.DataModel, name: String, content: String) {
//        var changed = entry.name != name.withoutLink()
//        entry.name <=> name.withoutLink()
//        let links = editControllable.linkRegisterController.linkDataModel(in: content)
//        var seenIds: Set<UUID> = []
//        var newContent = content
//        for link in links {
//            guard seenIds.contains(link.id) else {
//                seenIds.insert(link.id)
//                continue
//            }
//            let newLink = link.duplicate()
//            let oldLinkText = editControllable.linkRegisterController.markDown(for: link)
//            guard let range = content.firstRange(of: oldLinkText) else { continue }
//            newContent = newContent.replacingOccurrences(of: oldLinkText, with: editControllable.linkRegisterController.markDown(for: newLink), range: range)
//            link.modelContext?.insert(newLink)
//            try? link.modelContext?.save()
//        }
//        changed = changed || entry.content != newContent
//        entry.content <=> newContent
//        if changed {
//            cacheItemListModel.reset(cacheType: .row, itemId: entry.entryId, text: rowText(entry: entry))
//        }
//    }
}
