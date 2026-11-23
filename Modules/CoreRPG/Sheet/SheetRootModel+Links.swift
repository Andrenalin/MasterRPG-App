// @copyright André Trettin

import SwiftUI

extension SheetRootModel {
    func description(for sheetModel: SheetModel) -> String? {
        guard !searchText.isEmpty else { return sheetModel.description }
        return sheetModel.description.localizedStandardContains(searchText) ? sheetModel.description : nil
    }

    func linkTextModel(for id: LinkHighlightTextModelId, text: String, shareResults: ShareValueResult? = nil) -> LinkHighlightTextModel {
        guard let model = linkTextModel[id] else {
            let model = LinkHighlightTextModel(linkControllable: linkRootController, text: text, highlightedText: searchText, toggler: { [weak self] in self?.toggle(id: id, itemId: $0, module: $1, linkNumber: $2) }, shareResult: shareResults)
            linkTextModel[id] = model
            return model
        }
        return model
    }

    /// Resets every cached model of `kinds` for `sourceId` (one per occurrence of the item).
    func resetLinkText(_ kinds: Set<LinkHighlightTextModelId.Kind>, sourceId: UUID, text: String) {
        for (id, model) in linkTextModel where id.sourceId == sourceId && kinds.contains(id.kind) {
            model.reset(text: text)
        }
    }

    func removeLinkText(_ kinds: Set<LinkHighlightTextModelId.Kind>, sourceId: UUID) {
        for id in linkTextModel.keys where id.sourceId == sourceId && kinds.contains(id.kind) {
            linkTextModel[id] = nil
        }
    }

    /// The row with this occurrence id, searched depth-first from `sheet`.
    func sheet(withOccurrence occurrence: UUID, in sheet: SheetModel) -> SheetModel? {
        if sheet.id == occurrence { return sheet }
        for entry in sheet.entries {
            if let found = self.sheet(withOccurrence: occurrence, in: entry) { return found }
        }
        return nil
    }

    func toggle(id: LinkHighlightTextModelId, itemId: UUID, module: NetworkModules, linkNumber: Int) {
        withAnimation {
            // A tap inside a known row acts on that row, also when the same item is listed again
            // elsewhere in the tree.
            if let occurrence = id.occurrence, let target = sheet(withOccurrence: occurrence, in: sheetModel) {
                _ = toggleLink(in: target, linkId: itemId, module: module, linkNumber: linkNumber)
                return
            }
            switch id {
            case .item(let uuid, _), .itemContent(let uuid, _):
                _ = toggleItemLink(
                    sheetModel: sheetModel,
                    sourceItemId: uuid,
                    linkId: itemId,
                    module: module,
                    linkNumber: linkNumber
                )
            case .entry(let uuid, _):
                _ = toggleShown(sheetModel: sheetModel, entryId: uuid, linkId: itemId, module: module, linkNumber: linkNumber)
            case .entryContent(let uuid, _):
                _ = toggleShown(sheetModel: sheetModel, entryId: uuid, linkId: itemId, module: module, linkNumber: linkNumber)
            }
        }
    }

    func toggleItemLink(
        sheetModel: SheetModel,
        sourceItemId: UUID,
        linkId: UUID,
        module: NetworkModules,
        linkNumber: Int
    ) -> Bool {
        if sheetModel.source.itemId == sourceItemId {
            return toggleLink(in: sheetModel, linkId: linkId, module: module, linkNumber: linkNumber)
        }
        for entry in sheetModel.entries where toggleItemLink(
            sheetModel: entry,
            sourceItemId: sourceItemId,
            linkId: linkId,
            module: module,
            linkNumber: linkNumber
        ) {
            return true
        }
        return false
    }

    /// Expands or collapses the sheet `linkId` shown under `sheet`, adding it when it is not there.
    func toggleLink(in sheet: SheetModel, linkId: UUID, module: NetworkModules, linkNumber: Int) -> Bool {
        if let existingSheet = linkedSheet(in: sheet.entries, itemId: linkId, linkNumber: linkNumber) {
            unfold(sheetModel: existingSheet)
            existingSheet.isShown.toggle()
            return true
        }
        guard let rootModel = rootManager.rootModel(for: module) else { return false }
        let newSheet = rootModel.sheetControllable.sheet(
            root: rootManager,
            itemId: linkId,
            destination: sheet.destination,
            level: sheet.level + 1,
            isShown: true,
            moduleDepth: 0,
            isEditor: isEditor
        )
        newSheet.linkNumber = linkNumber
        unfold(sheetModel: newSheet)
        sheet.entries.append(newSheet)
        return true
    }

    func toggleShown(sheetModel: SheetModel, entryId: UUID, linkId: UUID, module: NetworkModules, linkNumber: Int) -> Bool {
        for entrySheetModel in sheetModel.entries {
            // Compare entryId (UUID) with source.entryId or source.itemId
            let matchesEntry = entrySheetModel.source.entryId == entryId || entrySheetModel.source.itemId == entryId
            if matchesEntry {
                if let existingSheet = linkedSheet(
                    in: entrySheetModel.entries,
                    itemId: linkId,
                    linkNumber: linkNumber
                ) {
                    unfold(sheetModel: existingSheet)
                    existingSheet.isShown.toggle()
                    return true
                } else {
                    // Link doesn't exist - add it using SheetController
                    if let rootModel = rootManager.rootModel(for: module) {
                        let newSheet = rootModel.sheetControllable.sheet(
                            root: rootManager,
                            itemId: linkId,
                            destination: entrySheetModel.destination,
                            level: entrySheetModel.level + 1,
                            isShown: true,
                            moduleDepth: 0,
                            isEditor: isEditor
                        )
                        newSheet.linkNumber = linkNumber
                        unfold(sheetModel: newSheet)
                        entrySheetModel.entries.append(newSheet)
                        return true
                    }
                }
                return true
            }
            if toggleShown(sheetModel: entrySheetModel, entryId: entryId, linkId: linkId, module: module, linkNumber: linkNumber) {
                return true
            }
        }
        return false
    }

    private func linkedSheet(
        in entries: [SheetModel],
        itemId: UUID,
        linkNumber: Int
    ) -> SheetModel? {
        if let exactMatch = entries.first(where: {
            $0.source.itemId == itemId && $0.linkNumber == linkNumber
        }) {
            return exactMatch
        }

        let unnumberedMatches = entries.filter {
            $0.source.itemId == itemId && $0.linkNumber == nil
        }
        return unnumberedMatches.count == 1 ? unnumberedMatches[0] : nil
    }

    func unfold(sheetModel: SheetModel) {
        guard let sheetController = rootManager.rootModel(for: sheetModel.source.typeId)?.sheetControllable else { return }
        sheetController.unfold(root: rootManager, sheetModel: sheetModel)
    }
}
