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

    func toggle(id: LinkHighlightTextModelId, itemId: UUID, module: NetworkModules, linkNumber: Int) {
        withAnimation {
            switch id {
            case .item(let uuid), .itemContent(let uuid):
                _ = toggleItemLink(
                    sheetModel: sheetModel,
                    sourceItemId: uuid,
                    linkId: itemId,
                    module: module,
                    linkNumber: linkNumber
                )
            case .entry(let uuid):
                _ = toggleShown(sheetModel: sheetModel, entryId: uuid, linkId: itemId, module: module, linkNumber: linkNumber)
            case .entryContent(let uuid):
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
            if let existingSheet = linkedSheet(
                in: sheetModel.entries,
                itemId: linkId,
                linkNumber: linkNumber
            ) {
                unfold(sheetModel: existingSheet)
                existingSheet.isShown.toggle()
                return true
            }
            guard let rootModel = rootManager.rootModel(for: module) else { return false }
            let newSheet = rootModel.sheetControllable.sheet(
                root: rootManager,
                itemId: linkId,
                destination: sheetModel.destination,
                level: sheetModel.level + 1,
                isShown: true,
                moduleDepth: 0,
                isEditor: isEditor
            )
            newSheet.linkNumber = linkNumber
            unfold(sheetModel: newSheet)
            sheetModel.entries.append(newSheet)
            return true
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
