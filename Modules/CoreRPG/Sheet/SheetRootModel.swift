// @copyright André Trettin

import SwiftUI

enum LinkHighlightTextModelId: Hashable {
    case item(UUID)
    case entry(UUID)
}

@MainActor @Observable
public final class SheetRootModel: Sendable {
    init(linkControllable: any LinkControllable, sheetControllable: SheetControllable, itemId: UUID) {
        self.linkControllable = linkControllable
        self.sheetModel = sheetControllable.sheet(root: linkControllable.rootManager, itemId: itemId, destination: nil, level: 0, isShown: true)
        updateFilteredEntries()
    }

    private(set)var sheetModel: SheetModel

    var searchText: String = "" {
        didSet {
            let wasEmpty = oldValue.isEmpty
            let isEmpty = searchText.isEmpty

            // Save state when starting search
            if wasEmpty && !isEmpty {
                saveIsShownState(sheetModel: sheetModel)
            }

            updateFilteredEntries()
        }
    }


    @ObservationIgnored let linkControllable: any LinkControllable
    @ObservationIgnored private var linkTextModel: [LinkHighlightTextModelId: LinkHighlightTextModel] = [:]

    var linkRootController: LinkControllable? {
        rootController(for: .adventure)?.linkControllable
    }
    
    func rootController(for module: NetworkModules) -> ItemRootController? {
        linkControllable.rootManager.itemRootController(for: module)
    }

    func description(for sheetModel: SheetModel) -> String? {
        guard !searchText.isEmpty else { return sheetModel.description }
        return sheetModel.description.localizedCaseInsensitiveContains(searchText) ? sheetModel.description : nil
    }

    
    func linkTextModel(for id: LinkHighlightTextModelId, text: String, shareResults: ShareValueResult? = nil) -> LinkHighlightTextModel {
        guard let model = linkTextModel[id] else {
            let model = LinkHighlightTextModel(linkControllable: linkRootController, text: text, highlightedText: searchText, toggler: { self.toggle(id: id, itemId: $0, module: $1) }, shareResult: shareResults)
            linkTextModel[id] = model
            return model
        }
        return model
    }
    
    func toggle(id: LinkHighlightTextModelId, itemId: UUID, module: NetworkModules) {
        withAnimation {
            switch id {
            case .item:
                break
            case .entry(let uuid):
                _ = toggleShown(sheetModel: sheetModel, entryId: uuid, linkId: itemId, module: module)
            }
        }
    }

    func toggleShown(sheetModel: SheetModel, entryId: UUID, linkId: UUID, module: NetworkModules) -> Bool {
        for entrySheetModel in sheetModel.entries {
            if entrySheetModel.id == entryId {
                // Check if link already exists in entries
                if let existingIndex = entrySheetModel.entries.firstIndex(where: { $0.source.itemId == linkId }) {
                    let existingSheet = entrySheetModel.entries[existingIndex]
                    // If it has an entryId, it's an entry link - remove it instead of toggling
                    if existingSheet.source.entryId != nil {
                        entrySheetModel.entries.remove(at: existingIndex)
                    } else {
                        // Module link - just toggle visibility
                        existingSheet.isShown.toggle()
                    }
                    return true
                } else {
                    // Link doesn't exist - add it using SheetController
                    if let rootModel = linkControllable.rootManager.rootModel(for: module) {
                        let newSheet = rootModel.sheetControllable.sheet(
                            root: linkControllable.rootManager,
                            itemId: linkId,
                            destination: entrySheetModel.destination,
                            level: entrySheetModel.level + 1,
                            isShown: true
                        )
                        entrySheetModel.entries.append(newSheet)
                        return true
                    }
                }
                return true
            }
            if toggleShown(sheetModel: entrySheetModel, entryId: entryId, linkId: linkId, module: module) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Search

    private func saveIsShownState(sheetModel: SheetModel) {
        sheetModel.lastIsShown = sheetModel.isShown
        sheetModel.entries.forEach { saveIsShownState(sheetModel: $0) }
    }

    private func updateFilteredEntries() {
        _ = sheetModel.filter(searchText: searchText)
        linkTextModel.values.forEach {
            $0.reset(highlightedText: searchText)
        }
    }
}
