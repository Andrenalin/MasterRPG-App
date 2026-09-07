// @copyright André Trettin

import SwiftUI

extension SheetRootModel {
    // MARK: - AI generation

    public func updateAIPreview(_ entry: SheetModel?) {
        let wasNil = sheetModel.aiPreviewEntry == nil
        sheetModel.aiPreviewEntry = entry
        if wasNil, let entry {
            setScrollEntryId(source: entry.source, entryId: entry.source.itemId)
        }
    }

    public func updateAIGenerated(_ entries: [SheetModel]) {
        let previousCount = sheetModel.aiGeneratedEntries.count
        sheetModel.aiGeneratedEntries = entries
        if entries.count > previousCount, let last = entries.last {
            setScrollEntryId(source: last.source, entryId: last.source.itemId)
        }
    }

    public func clearAIState() {
        sheetModel.aiPreviewEntry = nil
        sheetModel.aiGeneratedEntries = []
    }

    public func setAIModeActive(_ isActive: Bool) {
        guard isAIModeActive != isActive else { return }
        isAIModeActive = isActive
    }

    func commitAIEntry(_ entry: SheetModel, parent: SheetModel) {
        _ = entryDataEditable(for: parent.source)?.insertEntry(
            itemId: parent.source.itemId,
            name: entry.name,
            content: entry.description,
            position: .end,
            forceSave: persistsEdits
        )
        sheetModel.aiGeneratedEntries.removeAll { $0 === entry }
        updateParent(parent)
    }
}
