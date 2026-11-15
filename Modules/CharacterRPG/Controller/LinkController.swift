// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import os.log
import TableRPG
import DiceRPG
import PdfRPG
import PhotoRPG

struct LinkController: Sendable {
    let root: CharacterRootModel
    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    let itemController: ItemController

    public var itemControllable: any ItemControllable { itemController }

    /// Brief delay before toggling a tapped value link's visibility, giving the tap's own
    /// feedback animation a moment first. See CODE_AUDIT §9.14.
    private static let linkToggleDelay: Duration = .milliseconds(100)
}

extension LinkController: LinkControllable {
    @MainActor public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            if let handled = standardCommand(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command, in: text, toggler: toggler) {
                return handled
            }
            return text
        } else {
            if let toggler, entryId == nil, editAction == nil {
                LinkActionTasks.run {
                    // A cancelled action (the game ended) must not toggle after the delay.
                    try await Task.sleep(for: Self.linkToggleDelay)
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
            result = pdfRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = photoRoot.linkControllable.repairLink(link, for: result, for: [.all])
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
        guard let inspectedItem = itemController.itemSync(for: itemId), !inspectedItem.isHidden, let replacedItem = itemController.copy(of: itemId) else { return }

        replacedItem.photos = replacedItem.photos.compactMap { photoId in
            if photoRoot.linkControllable.validateLink(itemId: photoId) {
                return photoId
            } else {
                Logger.linkController.warning("Value: \(replacedItem.name, privacy: .private) --> Photo \(photoId, privacy: .private) is gone. Reset PhotoId, no recovery possible.")
                return nil
            }
        }

        if let photoId = replacedItem.photoId {
            if !photoRoot.linkControllable.validateLink(itemId: photoId) {
                Logger.linkController.warning("Value: \(replacedItem.name, privacy: .private) --> Photo \(photoId, privacy: .private) is gone. Reset PhotoId, no recovery possible.")
                replacedItem.photoId = nil
            }
        }

        for entry in inspectedItem.entries {
            var validatedEntry = entry

            if let diceId = validatedEntry.diceId {
                if !diceRoot.linkControllable.validateLink(itemId: diceId) {
                    Logger.linkController.warning("Value: \(replacedItem.name, privacy: .private) --> Dice \(diceId, privacy: .private) is gone. Reset DiceId, no recovery possible.")
                    validatedEntry.diceId = nil
                }
            }

            if let valueId = validatedEntry.valueId {
                if !validateLink(itemId: valueId) {
                    Logger.linkController.warning("Value: \(replacedItem.name, privacy: .private) --> Value \(valueId, privacy: .private) is gone. Reset ValueId, no recovery possible.")
                    validatedEntry.valueId = nil
                }
            }

            var links = LinkReplaceController.links(for: entry.name)
            validatedEntry.name = repairLinks(links, in: validatedEntry.name)

            links = LinkReplaceController.links(for: entry.value)
            validatedEntry.value = repairLinks(links, in: validatedEntry.value)

            if !entry.isSame(validatedEntry) {
                replacedItem[entry.id]  = validatedEntry
            }
        }
        if !replacedItem.isSame(inspectedItem) {
            Logger.linkController.info("Value: \(replacedItem.name, privacy: .private) will be replaced from repairing links.")
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
                        Logger.linkController.info("Value: \(child.name, privacy: .private) has a different parentId. It has \(itemController.itemOrEmpty(for: parentId).name) and now \(item.name) claim to be the parent")
                    }
                } else {
                    let updateChild = child.copy()
                    updateChild.parentId = item.id
                    updateChild.displayState = DisplayStateMask.groupHidden.rawValue
                    itemController.replace(model: updateChild, isInsert: false)
                }
            }
        }
    }
}

extension LinkController {
    @MainActor public func validate(id: UUID?) -> UUID? {
        guard let itemId = itemController.itemDataModel.items.first(where: { $0 == id }) else { return nil }
        return itemId
    }
}

private struct LinkMemoKey: Hashable {
    let itemId: UUID
    let entryId: UUID
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
        // One memo per top-level call, keyed by (itemId, entryId), threaded through the
        // recursion below. A diamond-shaped link fan-out (several entries linking to the
        // same shared entry) previously re-evaluated that shared entry once per path —
        // b^10 evaluations at the full recursion depth — instead of once. See
        // CODE_AUDIT_17 §5.18.
        var memo: [LinkMemoKey: String?] = [:]
        return calculate(entry: entry, deep: deep, memo: &memo)
    }

    @MainActor
    private func calculate(entry: ValueEntryModel, deep: Int, memo: inout [LinkMemoKey: String?]) -> String? {
        guard entry.canCalculate else { return nil }
        let links = LinkReplaceController.links(for: entry.value)
        var result = entry.value
        var valid = true

        for link in links {
            guard link.module == .value, let entryId = link.entryId else {
                valid = false
                continue
            }
            let key = LinkMemoKey(itemId: link.itemId, entryId: entryId)
            let linkValue: String?
            if let cached = memo[key] {
                linkValue = cached
            } else if deep < RecursionLimits.maxValueLinkDepth {
                let computed = calculate(itemId: link.itemId, entryId: entryId, deep: deep + 1, memo: &memo)
                memo[key] = computed
                linkValue = computed
            } else {
                linkValue = nil
            }
            guard let linkValue else {
                valid = false
                continue
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
    private func calculate(itemId: UUID, entryId: UUID, deep: Int, memo: inout [LinkMemoKey: String?]) -> String? {
        let entry = itemController.itemOrEmpty(for: itemId)[entryId]
        return calculate(entry: entry, deep: deep, memo: &memo)
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
    /// The calculated number an entry's attached dice compares against (and scales its
    /// die count by, via `DiceModel.addDiceEvery`), or `nil` for a non-number entry.
    /// Resolves the entry's formula links through `calculate(entry:)`, so reading it
    /// inside a view's `body` lets Observation track every entry the formula depends on,
    /// at any link depth.
    @MainActor
    func diceCompareValue(itemId: UUID, entryId: UUID) -> Int? {
        let entry = itemController.itemOrEmpty(for: itemId)[entryId]
        guard entry.type == .number else { return nil }
        guard let valueText = calculate(entry: entry) else { return nil }
        return Int(valueText)
    }
}
