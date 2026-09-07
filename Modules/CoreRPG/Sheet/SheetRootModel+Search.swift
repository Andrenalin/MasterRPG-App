// @copyright André Trettin

import SwiftUI

extension SheetRootModel {
    // MARK: - Search

    func findEntry(id: UUID, in model: SheetModel) -> SheetModel? {
        if model.id == id { return model }
        for entry in model.inlineEntries {
            if let found = findEntry(id: id, in: entry) { return found }
        }
        for entry in model.entries {
            if let found = findEntry(id: id, in: entry) { return found }
        }
        return nil
    }

    func initializeLastIsShownState(sheetModel: SheetModel) {
        sheetModel.lastIsShown = sheetModel.isShown
        sheetModel.entries.forEach { initializeLastIsShownState(sheetModel: $0) }
    }

    func saveIsShownState(sheetModel: SheetModel) {
        sheetModel.lastIsShown = sheetModel.isShown
        sheetModel.entries.forEach { saveIsShownState(sheetModel: $0) }
    }

    func updateFilteredEntries(shouldRestoreState: Bool = false) {
        _ = sheetModel.filter(searchText: searchText, shouldRestoreState: shouldRestoreState)
        linkTextModel.values.forEach {
            $0.reset(highlightedText: searchText)
        }
    }
}
