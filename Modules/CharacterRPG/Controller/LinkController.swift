// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import os.log
import TableRPG
import DiceRPG
import PhotoRPG

struct LinkController: Sendable {
    let root: CharacterRootModel
    let diceRoot: DiceRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    let itemController: ItemController

    public var itemControllable: any ItemControllable { itemController }
}

extension LinkController: LinkControllable {
    @MainActor public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            if command == LinkType.remove.rawValue {
                let url = generateLink(linkNumber: linkNumber - LinkType.remove.linkNumberAddition, itemId: itemId, entryId: entryId)
                return text.toggleLink(url: url, with: name(for: itemId, entryId: entryId), remove: true)
            }
            if command == LinkType.show.rawValue {
                Task { @MainActor in
                    await toggler?(itemId, itemControllable.config.module)
                }
                return text
            }
            return text
        } else {
            if let toggler, entryId == nil, editAction == nil {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    await toggler(itemId, itemController.config.module)
                }
            }
            let item = itemController.itemOrEmpty(for: itemId)
            // Character values never offer a per-link "Share" affordance —
            // there is nothing for a player to share to on their own sheet,
            // and it made no player/master distinction on its own.
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.config.module)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let description: String
            if let entryId {
                description = item[entryId].value
            } else {
                description = formatInlineDescription(description: item.description, entryCount: item.entries.count)
            }
            let result = "\(showAction) \(description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor public func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String {
        var result = content
        for link in links {
            result = diceRoot.linkControllable.repairLink(link, for: result, for: [.rules, .value])
            result = tableRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = repairLink(link, for: result, for: [.all])
        }
        return result
    }
    
    @MainActor public func validateLinks(reportModel: ValidateRepairModel) async {
        reportModel.update(phase: .validateLinks)
        for inspectedId in itemController.itemDataModel.items {
            reportModel.increaseCurrent()
            await Task.yield()
            guard !Task.isCancelled else { return }
            validateLinks(on: inspectedId)
        }
        validateParentId()
    }
    
    @MainActor public func validateLinks(on itemId: UUID) {
        guard let inspectedItem = itemController.itemSync(for: itemId), inspectedItem.displayState != 2, let replacedItem = itemController.copy(of: itemId) else { return }
        
        replacedItem.photos = replacedItem.photos.compactMap { photoId in
            if photoRoot.linkControllable.validateLink(itemId: photoId) {
                return photoId
            } else {
                Logger.linkController.warning("Value: \(replacedItem.name, privacy: .public) --> Photo \(photoId, privacy: .public) is gone. Reset PhotoId, no recovery possible.")
                return nil
            }
        }

        if let photoId = replacedItem.photoId {
            if !photoRoot.linkControllable.validateLink(itemId: photoId) {
                Logger.linkController.warning("Value: \(replacedItem.name, privacy: .public) --> Photo \(photoId, privacy: .public) is gone. Reset PhotoId, no recovery possible.")
                replacedItem.photoId = nil
            }
        }
        
        for entry in inspectedItem.entries {
            var validatedEntry = entry
            
            if let diceId = validatedEntry.diceId {
                if !diceRoot.linkControllable.validateLink(itemId: diceId) {
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
            itemController.replace(model: replacedItem, isInsert: false)
        }
        resetLinkRegister(replacedItem)
    }

    @MainActor func validateParentId() {
        for inspectedId in itemController.itemDataModel.items {
            let item = itemController.itemOrEmpty(for: inspectedId)
            for entry in item.entries {
                guard let valueId = entry.valueId else { continue }
                let child = itemController.itemOrEmpty(for: valueId)
                // Groups express their parent relationship via groupId, never parentId.
                // Skipping them here keeps parentId nil and avoids folder-maintenance churn on import.
                guard child.groupId == nil else { continue }
                if let parentId = child.parentId {
                    if parentId != item.id {
                        Logger.linkController.info("Value: \(child.name, privacy: .public) has a different parentId. It has \(itemController.itemOrEmpty(for: parentId).name) and now \(item.name) claim to be the parent")
                    }
                } else {
                    let updateChild = child.copy()
                    updateChild.parentId = item.id
                    updateChild.displayState = 1
                    itemController.replace(model: updateChild, isInsert: false)
                }
            }
        }
    }
}

extension LinkController {
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
    @MainActor public func validate(id: UUID?) -> UUID? {
        guard let itemId = itemController.itemDataModel.items.first(where: { $0 == id }) else { return nil }
        return itemId
    }
}

extension LinkController {
    @MainActor
    func linkText(model: ValueModel, entry: ValueEntryModel, withoutName: Bool = false) -> String {
        var otherValue = ""
        if let valueId = entry.valueId {
            otherValue = itemController.itemOrEmpty(for: valueId).url(linkNumber: 0)
        }
        
        if let valueText = calculate(entry: entry, deep: 0), entry.value != valueText {
            otherValue = "= \(valueText)"
        }
        
        let rowText = entry.valueLinkText(otherValue: " \(otherValue)", withoutName: withoutName)
        return rowText
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
            guard deep < RecursionLimits.maxValueLinkDepth, let linkValue = calculate(itemId: link.itemId, entryId: entryId, deep: deep + 1) else {
                valid = false
                return
            }
            let linkTable = itemController.itemOrEmpty(for: link.itemId)
            result = result.replacing(linkTable.url(linkNumber: link.linkNumber, entryId: entryId), with: "\(linkValue)")
        }
        
        guard valid else {
            // A link outside the `.value` module (e.g. a Table roll kept for
            // provenance) can't be re-evaluated here, but the entry still
            // carries its last rolled result after the "|" separator — the
            // same cached-value convention `valueCalculated` reads.
            let cached = entry.valueCalculated
            return cached == "0" ? result : cached
        }
        result = result.replacing("|", with: "+")
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
            let originalModel = itemController.itemOrEmpty(for: link.itemId)
            guard let newId = mapper[link.itemId], let newModel = models.first(where: { $0.id == newId }) else { continue }
            
            let markDown: String
            if let entryId = link.entryId {
                guard let index = originalModel.entries.firstIndex(where: { $0.id == entryId }), index < newModel.entries.count else { continue }
                markDown = newModel.url(linkNumber: link.linkNumber, entryId: newModel.entries[index].id)
            } else {
                markDown = newModel.url(linkNumber: link.linkNumber)
            }
            result = result.replacing(link.markDown, with: markDown)
        }
        return result
    }
}

extension LinkController {
    @MainActor func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] {
        guard let item = itemController.itemSync(for: itemId) else { return [] }
        return item.photos
    }
}

extension LinkController {
    @MainActor
    func updateValueCalculation(itemId: UUID, entryId: UUID, action: @MainActor @escaping @Sendable () -> Void) {
        let details: [LinkReplaceModel] = LinkReplaceController.links(for: itemController.itemOrEmpty(for: itemId)[entryId].value).filter {
            $0.module == itemController.config.module && $0.entryId != nil && $0.entryId != entryId && itemController.itemSync(for: $0.itemId) != nil
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
