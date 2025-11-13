// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation
import RegexBuilder
import SwiftUI
import RPGAudios
import RPGDie
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGValues
import RPGWeathers

@MainActor @Observable
final class AdventureEditModel: Sendable {
    var contentLinks: [UUID: LinkReplaceController] = [:]
    
    let photoSelectionModel = SelectionModel(id: UUID(), filter: .adventure)
    let pdfSelectionModel = SelectionModel(id: UUID(), filter: .all)
    
    func resetCurrentModel() {
        contentLinks = [:]
    }
}

struct EditController: Sendable {
    @MainActor
    init(root: AdventureRoot, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.root = root
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
        self.adventureEditModel = AdventureEditModel()
    }

    weak var root: AdventureRoot!
    var fileUrlDataController: FileUrlDataController? = nil
    let editorModel: ItemEditorModel
    let adventureEditModel: AdventureEditModel
}

extension EditController: EntryDataEditable {
    typealias Model = AdventureModel

    var itemControllable: any ItemControllable {
        root.itemController as (any ItemControllable)
    }

    var linkRegisterControllable: any LinkRegisterControllable {
        root.linkRegisterControllable
    }

    @MainActor func didSetModel() {
        guard let id = editorModel.currentItemId else { return }
        if adventureEditModel.photoSelectionModel.id != id {
            adventureEditModel.photoSelectionModel.id = id
            if adventureEditModel.photoSelectionModel.currentValue != model.photoId {
                adventureEditModel.photoSelectionModel.currentValue = model.photoId
            }
        }

        if adventureEditModel.pdfSelectionModel.id != id {
            adventureEditModel.pdfSelectionModel.id = id
        }
    }
    
    @MainActor func resetCurrentModel() {
        adventureEditModel.resetCurrentModel()
    }

    @MainActor func submitChanges() {
        adventureEditModel.resetCurrentModel()
    }
}

// MARK: - Selection

extension EditController {
    @MainActor func selection(for module: NetworkModules) -> [ItemRowModel] {
        guard module == .photo else { return [] }
        if let id = model.photoId {
            return [ItemRowModel(itemId: id, typeId: .photo)]
        }
        return []
    }
    
    @MainActor func toggle(for module: NetworkModules, itemRowModel: ItemRowModel) async {
        guard module == .photo else { return }
        model.photoId = itemRowModel.itemId
        save(with: String(localized: "Change Photo").localizedString)
    }
    
    @MainActor @ViewBuilder
    func selectAdventure(for entryId: UUID, linkKeyPath: WritableKeyPath<AdventureModel, String>, dismissAction: @escaping () -> Void) -> some View {
        root.viewController.viewSelect(filter: .all) {
            let text = self.model[keyPath: linkKeyPath]
            return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .adventure) }
        } toggleSelection: { sel, _ in
            self.model[keyPath: linkKeyPath] = self.root.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
            self.save(with: String(localized: "Change adventure links").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }
    
    @MainActor @ViewBuilder
    func selectAudio(for entryId: UUID, linkKeyPath: WritableKeyPath<AdventureModel, String>, dismissAction: @escaping () -> Void) -> some View {
        root.audioRoot.viewController.viewSelect(root: root.audioRoot, filter: .all) {
            let text = self.model[keyPath: linkKeyPath]
            return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .audio) }
        } toggleSelection: { sel, _ in
            self.model[keyPath: linkKeyPath] = self.root.audioRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
            self.save(with: String(localized: "Change audio links").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }
    
    @MainActor @ViewBuilder
    func selectDice(for entryId: UUID, linkKeyPath: WritableKeyPath<AdventureModel, String>, dismissAction: @escaping () -> Void) -> some View {
        root.diceRoot.viewController.viewSelect(filter: .all) {
            let text = self.model[keyPath: linkKeyPath]
            return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .dice) }
        } toggleSelection: { sel, _ in
            self.model[keyPath: linkKeyPath] = self.root.diceRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
            self.save(with: String(localized: "Change dice links").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }
    
    @MainActor @ViewBuilder
    func selectMap(for entryId: UUID, linkKeyPath: WritableKeyPath<AdventureModel, String>, dismissAction: @escaping () -> Void) -> some View {
        root.mapRoot.viewController.viewSelect(filter: .all) {
            let text = self.model[keyPath: linkKeyPath]
            return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .map) }
        } toggleSelection: { sel, _ in
            self.model[keyPath: linkKeyPath] = self.root.mapRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
            self.save(with: String(localized: "Change map links").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }
    
    @MainActor @ViewBuilder
    func selectPdf(for entryId: UUID, linkKeyPath: WritableKeyPath<AdventureModel, String>, dismissAction: @escaping () -> Void) -> some View {
        root.pdfRoot.viewController.viewSelect(root: root.pdfRoot, filter: .all) {
            let text = self.model[keyPath: linkKeyPath]
            return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .pdf) }
        } toggleSelection: { sel, _ in
            self.model[keyPath: linkKeyPath] = self.root.pdfRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
            self.save(with: String(localized: "Change pdf links").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }
    
    @MainActor @ViewBuilder
    func selectPhoto(for entryId: UUID, linkKeyPath: WritableKeyPath<AdventureModel, String>, dismissAction: @escaping () -> Void) -> some View {
        root.photoRoot.viewController.viewSelect(filter: .all) {
            let text = self.model[keyPath: linkKeyPath]
            return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .photo) }
        } toggleSelection: { sel, _ in
            self.model[keyPath: linkKeyPath] = self.root.photoRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
            self.save(with: String(localized: "Change photo links").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }

    @MainActor @ViewBuilder
    func selectSpace(for entryId: UUID, linkKeyPath: WritableKeyPath<AdventureModel, String>, dismissAction: @escaping () -> Void) -> some View {
        root.spaceRoot.viewController.viewSelect(root: root.spaceRoot, filter: .all) {
            let text = self.model[keyPath: linkKeyPath]
            return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .space) }
        } toggleSelection: { sel, _ in
            self.model[keyPath: linkKeyPath] = self.root.spaceRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
            self.save(with: String(localized: "Change space links").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }

    @MainActor @ViewBuilder
    func selectTable(for entryId: UUID, linkKeyPath: WritableKeyPath<AdventureModel, String>, dismissAction: @escaping () -> Void) -> some View {
        root.tableRoot.viewController.viewSelect(filter: .all) {
            let text = self.model[keyPath: linkKeyPath]
            return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .table) }
        } toggleSelection: { sel, _ in
            self.model[keyPath: linkKeyPath] = self.root.tableRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
            self.save(with: String(localized: "Change table links").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }
    
    @MainActor @ViewBuilder
    func selectValue(for entryId: UUID, linkKeyPath: WritableKeyPath<AdventureModel, String>, dismissAction: @escaping () -> Void) -> some View {
        root.valueRoot.viewController.viewSelect(filter: .all) {
            let text = self.model[keyPath: linkKeyPath]
            return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .value) }
        } toggleSelection: { sel, _ in
            self.model[keyPath: linkKeyPath] = self.root.valueRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
            self.save(with: String(localized: "Change value links").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }
    
    @MainActor @ViewBuilder
    func selectWeather(for entryId: UUID, linkKeyPath: WritableKeyPath<AdventureModel, String>, dismissAction: @escaping () -> Void) -> some View {
        root.weatherRoot.viewController.viewSelect(filter: .all) {
            let text = self.model[keyPath: linkKeyPath]
            return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .weather) }
        } toggleSelection: { sel, _ in
            self.model[keyPath: linkKeyPath] = self.root.weatherRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
            self.save(with: String(localized: "Change weather links").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }
}

// MARK: - Link Editor

extension EditController {
    @MainActor func contentEditLink(for entryId: UUID) -> LinkReplaceController {
        guard let controller = adventureEditModel.contentLinks[entryId] else {
            let controller = LinkReplaceController {
                model[entryId].content
            } setter: {
                update(entryId: entryId, content: $0)
            }
            adventureEditModel.contentLinks[entryId] = controller
            return controller
        }
        return controller
    }
    
    @MainActor func updateContent(_ content: String, for entryId: UUID) {
        if let contentLink = adventureEditModel.contentLinks[entryId] {
            contentLink.editValue.wrappedValue = content
        } else {
            update(entryId: entryId, content: content)
        }
        save(with: String(localized: "Add link").localizedString)
    }
    
    @MainActor func update(entryId: UUID, content: String) {
        model[entryId].content = content
        editorModel.cacheItemListModel.reset(cacheType: .content, itemId: entryId, text: content)
        editorModel.cacheItemListModel.reset(cacheType: .row, itemId: entryId, text: model[entryId].textLinkContent)
    }
}

// MARK: - Quick Link Editor

extension EditController {
    @MainActor
    func merge(entries: [AdventureEntryModel], recoverEntries: [ItemRowModel]?) async -> [ItemRowModel] {
        let item = model
        var newEntries = entries.map { entry in
            var foundEntry = item.entries.first(where: { $0.name == entry.name })
            foundEntry?.content = entry.content
            return foundEntry ?? entry
        }
        let removedIds = Set(item.entries.map { $0.id }).subtracting(newEntries.map { $0.id })
        let module = root.itemController.itemDataModel.networkModule
        let itemRowModels = removedIds.map { ItemRowModel(itemId: item.id, entryId: $0, typeId: module) }

        var effectedLinks = true
        for itemRowModel in itemRowModels {
            if !root.itemController.usedLinks(for: itemRowModel).isEmpty {
                effectedLinks = false
                break;
            }
        }
        if recoverEntries != nil || effectedLinks {
            if let recoverEntries {
                newEntries.append(contentsOf: recoverEntries.compactMap { $0.entryId }.map { item[$0] })
            }
            item.entries = newEntries
            save(with: String(localized: "Entries replaced").localizedString)
            return []
        }
        return itemRowModels
    }

    @MainActor
    func scan(itemId: UUID, with anotherIds: [UUID]?, module: NetworkModules, caseInsensitive: Bool, words: Bool) -> [AdventureEntryModel] {
        guard let anotherIds else {
            let otherEntries: [LinkEntryModel]
            switch module {
            case .dice:
                otherEntries = root.diceRoot.linkController.link(for: .table)
            case .map:
                otherEntries = root.mapRoot.linkController.link(for: .adventure)
            case .table:
                otherEntries = root.tableRoot.linkController.link(for: .adventure)
            case .value:
                otherEntries = root.valueRoot.linkController.link(for: .adventure)
            default:
                otherEntries = root.linkController.link(for: .adventure)
            }
            return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
        }
        let otherEntries: [LinkEntryModel] = anotherIds.flatMap { anotherId in
            switch module {
            case .adventure:
                return root.linkController.linkEntries(for: anotherId)
            case .dice:
                return root.diceRoot.linkController.linkEntries(for: anotherId)
            case .map:
                return root.mapRoot.linkController.linkEntries(for: anotherId)
            case .table:
                return root.tableRoot.linkController.linkEntries(for: anotherId)
            case .value:
                return root.valueRoot.linkController.linkEntries(for: anotherId)
            default:
                return []
            }
        }
        return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
    }

    @MainActor
    func scan(itemId: UUID, with linkEntries: [LinkEntryModel], caseInsensitive: Bool, words: Bool) -> [AdventureEntryModel] {
        guard let entries = root.itemController.itemSync(for: itemId)?.entries else { return [] }
        return entries.map { entry in
            var replacedEntry = entry
            linkEntries.forEach { linkEntry in
                replacedEntry = scanReplace(entry: replacedEntry, linkEntry: linkEntry, getLink: { $0.content }, setLink: { var result = $1; result.content = $0; return result }, caseInsensitive: caseInsensitive, words: words)
            }
            return replacedEntry
        }
    }
}

extension EditController {
    
    @MainActor func collectPhotos(entryId: UUID) {
        let photoIds = root.linkController.collectLinks(of: .photo, from: model.id)
        let links = photoIds.map {
            root.photoRoot.linkController.generateLink(itemId: $0)
        }.sorted()
        update(entryId: entryId, content: links.joined(separator: "\n"))
    }
}
