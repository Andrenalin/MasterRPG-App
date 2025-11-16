// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftUI
import os.log
import RPGTables
import RPGDie
import RPGPhotos

public struct LinkController: Sendable {
    weak var root: CharacterRootModel!
    let itemController: ItemController
    
    public var itemControllable: any ItemControllable {
        itemController as ItemController
    }
}

extension LinkController {
    @MainActor
    func updateValueCalculation(itemId: UUID, entryId: UUID, action: @MainActor @escaping @Sendable () -> Void) {
        let details: [LinkReplaceModel] = LinkReplaceController.links(for: itemController.itemOrEmpty(for: itemId)[entryId].value).filter {
            $0.module == itemController.itemDataModel.networkModule && $0.entryId != nil && $0.entryId != entryId && itemController.itemSync(for: $0.itemId) != nil
        }
        for detail in details {
            _ = withObservationTracking {
                itemController.itemOrEmpty(for: detail.itemId)[detail.entryId!].value
            } onChange: {
                Task { @MainActor in
                    action()
                }
            }
        }
    }
}

extension LinkController: LinkControllable {
    @MainActor
    public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            if command == LinkType.remove.rawValue {
                let url = generateLink(linkNumber: linkNumber - LinkType.remove.linkNumberAddition, itemId: itemId, entryId: entryId)
                return text.toggleLink(url: url, with: name(for: itemId, entryId: entryId), remove: true)
            }
            if command == LinkType.show.rawValue {
                Task { @MainActor in
                    await toggler?(itemId, itemControllable.itemDataModel.networkModule)
                }
                return text
            }
            Task { @MainActor in
                await shareResult?.networkActions?.shareId(root.gameController.share(id: itemId))
            }
            return text
        } else {
            if let toggler, entryId == nil, editAction == nil {
                Task { @MainActor in
                    try await Task.sleep(for: .milliseconds(100))
                    await toggler(itemId, itemController.itemDataModel.networkModule)
                }
            }
            let item = itemController.itemOrEmpty(for: itemId)
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? "\(specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.itemDataModel.networkModule)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let description: String
            if let entryId {
                description = item[entryId].value
            } else {
                description = "\(item.name) / \(item.description) / \(item.entries.count) Entries"
            }
            let result = "\(sendAction)\(showAction) \(description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor public func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String {
        var result = content
        for link in links {
            result = root.diceRoot.linkController.repairLink(link, for: result, for: [.rules, .value])
            result = root.tableRoot.linkController.repairLink(link, for: result, for: [.all])
            result = repairLink(link, for: result, for: [.all])
        }
        return result
    }
    
    @MainActor public func validateLinks() {
        for inspectedId in itemController.itemDataModel.items {
            validateLinks(on: inspectedId)
        }
        validateParentId()
    }
    
    @MainActor public func validateLinks(on itemId: UUID) {
        guard let inspectedItem = itemController.itemSync(for: itemId), let replacedItem = itemController.copy(of: itemId) else { return }
        
        replacedItem.photos = replacedItem.photos.compactMap { photoId in
            if root.photoRoot.linkController.validateLink(itemId: photoId) {
                return photoId
            } else {
                Logger.linkController.warning("Value: \(replacedItem.name, privacy: .public) --> Photo \(photoId, privacy: .public) is gone. Reset PhotoId, no recovery possible.")
                return nil
            }
        }
        
        if let photoId = replacedItem.photoId {
            if !root.photoRoot.linkController.validateLink(itemId: photoId) {
                Logger.linkController.warning("Value: \(replacedItem.name, privacy: .public) --> Photo \(photoId, privacy: .public) is gone. Reset PhotoId, no recovery possible.")
                replacedItem.photoId = nil
            }
        }
        
        for entry in inspectedItem.entries {
            var validatedEntry = entry
            
            if let diceId = validatedEntry.diceId {
                if !root.diceRoot.linkController.validateLink(itemId: diceId) {
                    Logger.linkController.warning("Value: \(replacedItem.name, privacy: .public) --> Dice \(diceId, privacy: .public) is gone. Reset DiceId, no recovery possible.")
                    validatedEntry.diceId = nil
                }
            }
            
            if let valueId = validatedEntry.valueId {
                if !validateLink(itemId: valueId) {
                    Logger.linkController.warning("Value: \(replacedItem.name, privacy: .public) --> Value \(valueId, privacy: .public) is gone. Reset ValueId, no recovery possible.")
                    validatedEntry.valueId = nil
                }
            }
            
            var links = entry.links(for: entry.name)
            validatedEntry.name = repairLinks(links, in: validatedEntry.name)
            
            links = entry.links(for: entry.value)
            validatedEntry.value = repairLinks(links, in: validatedEntry.value)
            
            if !entry.isSame(validatedEntry) {
                replacedItem[entry.id]  = validatedEntry
            }
        }
        if !replacedItem.isSame(inspectedItem) {
            Logger.linkController.info("Value: \(replacedItem.name, privacy: .public) will be replaced from reparing links.")
            itemController.replace(model: replacedItem, isInsert: false, shouldRepairLinks: true)
        }
    }
    
    @MainActor func validateParentId() {
        for inspectedId in itemController.itemDataModel.items {
            let item = itemController.itemOrEmpty(for: inspectedId)
            for entry in item.entries {
                guard let valueId = entry.valueId else { continue }
                let child = itemController.itemOrEmpty(for: valueId)
                if let parentId = child.parentId {
                    if parentId != item.id {
                        Logger.linkController.info("Value: \(child.name, privacy: .public) has a different parentId. It has \(itemController.itemOrEmpty(for: parentId).name) and now \(item.name) claim to be the parent")
                    }
                } else {
                    let updateChild = child.copy()
                    updateChild.parentId = item.id
                    itemController.replace(model: updateChild, isInsert: false, shouldRepairLinks: true)
                }
            }
        }
    }
}

public extension LinkController {
    @MainActor
    func link(for module: NetworkModules) -> [LinkEntryModel] {
        let category: ItemListCategory
        switch module {
        case .value: category = .character
        default: category = .all
        }
        
        var items = itemController.itemDataModel.items.map { itemController.itemOrEmpty(for: $0) }
        if category != .all {
            items = items.filter { $0.category == category }
        }
        return items.sorted(by: { $0.name.count > $1.name.count })
            .map { LinkEntryModel(reference: $0.name, markdownUrl: $0.url(linkNumber: 0)) }
    }
    
    @MainActor
    func linkEntries(for itemId: UUID) -> [LinkEntryModel] {
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries
            .sorted(by: { $0.name.count > $1.name.count })
            .map { LinkEntryModel(reference: $0.name.withoutLink(), markdownUrl: item.url(linkNumber: 0, entryId: $0.id)) }
    }
}

extension LinkController {
    @MainActor
    public func validate(id: UUID?, isCharacter: Bool = false, isGameMaster: Bool = false) -> UUID? {
        guard let validId = itemController.itemDataModel.items.first(where: { $0 == id }) else { return nil }
        if isCharacter {
            return itemController.itemSync(for: validId)?.category == .character ? validId : nil
        }
        if isGameMaster {
            return itemController.itemSync(for: validId)?.category == .gameMaster ? validId : nil
        }
        return validId
    }
    
    @MainActor
    public func generateItem(for name: String, parentId: UUID?, tableId: UUID?, entryId: UUID?) async -> UUID {
        guard let tableId else {
            if let itemId = itemController.itemDataModel.items.first(where: { itemController.itemSync(for: $0)?.name == name }) {
                return itemId
            }
            
            let item = ValueModel(id: UUID(), name: name, entries: [])
            itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
            return item.id
        }
        
        let item: ValueModel
        if let itemId = itemController.itemDataModel.items.first(where: { itemController.itemSync(for: $0)?.name == name }), let existItem = itemController.itemSync(for: itemId) {
            item = existItem
        } else {
            item = ValueModel(id: UUID(), name: name, entries: [])
        }
        if let parentId  {
            item.category = itemController.itemSync(for: parentId)?.category ?? .item
            item.isGroupHiddenToggle = true
        } else {
            item.category = .item
        }
        
        var url: String
        if let entryId = entryId {
            let (_, entryUrl) =  root.tableRoot.linkController.generateItem(for: tableId, entryId: entryId)
            url = entryUrl
        } else {
            url =  root.tableRoot.linkController.generateLinks(itemId: tableId, entryId: entryId, into: "")
        }
        url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let valueEntry = ValueEntryModel(id: UUID(), name:  root.tableRoot.linkController.name(for: tableId).withoutLink(), type: .text, value: url)
        item.entries = item.entries + [valueEntry]
        
        itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
        
        if let parentId, let parentItem = itemController.itemSync(for: parentId), !parentItem.entries.contains(where: { $0.valueId == item.id }) {
            let valueEntry = ValueEntryModel(id: UUID(), name: "Group", type: .text, value: "", valueId: item.id)
            root.editController(type: .main).add(entry: valueEntry, into: parentId)
            itemController.replace(model: parentItem, isInsert: false, shouldRepairLinks: true)
        }
        
        return item.id
    }
    
    @MainActor
    public func generateItem(from itemId: UUID, name: String, value: String, list: [ItemRowModel]) async -> (UUID?, UUID?) {
        let entries = list.map {
            let (value, _) =  root.tableRoot.linkController.generateItem(for: $0.itemId, entryId: $0.entryId ?? UUID())
            return ValueEntryModel(id: UUID(), name:  root.tableRoot.linkController.name(for: $0.itemId), type: .text, value: value)
        }
        let newValue = ValueModel(id: UUID(), name: name.withoutLink(), description: value, entries: entries)
        itemController.replace(model: newValue, isInsert: false, shouldRepairLinks: true)
        return (nil, newValue.id)
    }
}

extension LinkController {
    @MainActor
    func linkText(model: ValueModel, entryId: UUID, withoutName: Bool = false) -> String {
        var otherValue = ""
        if let valueId = model[entryId].valueId {
            otherValue = itemController.itemOrEmpty(for: valueId).url(linkNumber: 0)
        }
        
        if let valueText = calculate(entry: model[entryId], deep: 0), model[entryId].value != valueText {
            otherValue = "= \(valueText)"
        }
        return model[entryId].valueLinkText(otherValue: " \(otherValue)", withoutName: withoutName)
    }
    
    @MainActor
    func calculate(entry: ValueEntryModel, deep: Int = 0) -> String? {
        guard entry.canCalculate else { return nil }
        let links = entry.links(for: entry.value)
        var result = entry.value
        var valid = true
        
        links.forEach { link in
            guard link.module == .value, let entryId = link.entryId else {
                valid = false
                return
            }
            guard deep < 10, let linkValue = calculate(itemId: link.itemId, entryId: entryId, deep: deep + 1) else {
                valid = false
                return
            }
            let linkTable = itemController.itemOrEmpty(for: link.itemId)
            result = result.replacingOccurrences(of: linkTable.url(linkNumber: link.linkNumber, entryId: entryId), with: "\(linkValue)")
        }
        
        guard valid else { return result }
        result = result.replacingOccurrences(of: "|", with: "+")
        return entry.calculate(on: result)
    }
    
    @MainActor
    private func calculate(itemId: UUID, entryId: UUID, deep: Int) -> String? {
        let entry = itemController.itemOrEmpty(for: itemId)[entryId]
        return calculate(entry: entry, deep: deep)
    }
}

// repair links
extension LinkController {
    @MainActor
    func repairDuplicateLinks(models: [ValueModel], mapper: [UUID: UUID]) {
        for model in models {
            for (index, entry) in model.entries.enumerated() {
                let newValue = repairValueLinks(models: models, mapper: mapper, text: entry.value)
                if newValue != entry.value {
                    model.entries[index].value = newValue
                }
                let newName = repairValueLinks(models: models, mapper: mapper, text: entry.name)
                if newName != entry.name {
                    model.entries[index].name = newName
                }
            }
        }
    }
    
    @MainActor
    func repairValueLinks(models: [ValueModel], mapper: [UUID: UUID], text: String) -> String {
        let links = LinkReplaceController.links(for: text).filter { $0.module == .value && mapper[$0.itemId] != nil }
        var result = text
        for link in links {
            let originalModel = root.itemController.itemOrEmpty(for: link.itemId)
            guard let newId = mapper[link.itemId], let newModel = models.first(where: { $0.id == newId }) else { continue }
            
            let markDown: String
            if let entryId = link.entryId {
                guard let index = originalModel.entries.firstIndex(where: { $0.id == entryId }), index < newModel.entries.count else { continue }
                markDown = newModel.url(linkNumber: link.linkNumber, entryId: newModel.entries[index].id)
            } else {
                markDown = newModel.url(linkNumber: link.linkNumber)
            }
            result = result.replacingOccurrences(of: link.markDown, with: markDown)
        }
        return result
    }
}

public extension LinkController {
    @MainActor func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel? {
        switch module {
        case .table:
            return root.tableRoot.sheet(for: itemId, level: level)
        case .value:
            return SheetController(root: root).sheet(for: itemId, level: level)
        default:
            return nil
        }
    }
}

public extension LinkController {
    @MainActor func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] {
        guard let item = root.itemController.itemSync(for: itemId) else { return [] }
        return item.photos
    }
}
