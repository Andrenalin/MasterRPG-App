// @copyright André Trettin

import Foundation

@MainActor
struct SheetEntryReviewPreviewFixture {
    init(isExpanded: Bool = true) {
        let itemId = UUID()
        var existingEntry = EmtpyEntryViewModel.empty
        existingEntry.id = UUID()
        existingEntry.name = "Hidden Door"
        existingEntry.content = "A concealed stone passage."

        var importedEntry = existingEntry
        importedEntry.content = "A concealed passage marked with silver runes."
        let mergedEntry = importedEntry
        let singleEntryModel = SingleEntryImportModel(
            entry: SingleReviewEntry(
                existing: existingEntry,
                imported: importedEntry,
                merged: mergedEntry
            ),
            properties: [],
            references: []
        )

        let source = ItemRowModel(
            itemId: itemId,
            entryId: existingEntry.id,
            typeId: .adventure
        )
        let inlineSource = ItemRowModel(
            itemId: UUID(),
            entryId: UUID(),
            typeId: .dice
        )
        let inlineModel = SheetModel(
            source: inlineSource,
            type: .dice,
            name: "Perception Check",
            description: "1d20 + 4",
            entries: []
        )
        let row = SheetModel(
            source: source,
            name: importedEntry.name,
            description: importedEntry.content,
            inlineEntries: [inlineModel],
            entries: []
        )
        let versions = SingleReviewDecision.allCases.map { decision in
            SheetReviewVersion(
                id: SheetReviewVersionID(
                    itemId: itemId,
                    entryID: existingEntry.id,
                    decision: decision
                ),
                decision: decision,
                sheetModel: row,
                entry: singleEntryModel.materializedEntry(for: decision)
            )
        }

        sheetModel = row
        inlineSheetModel = inlineModel
        reviewModel = SheetEntryReviewModel(
            itemId: itemId,
            entryModel: singleEntryModel,
            versions: versions,
            isExpanded: isExpanded
        )
        version = SheetReviewVersion(
            id: SheetReviewVersionID(
                itemId: itemId,
                entryID: existingEntry.id,
                decision: .merge
            ),
            decision: .merge,
            sheetModel: row,
            entry: mergedEntry
        )
    }

    let sheetModel: SheetModel
    let inlineSheetModel: SheetModel
    let reviewModel: SheetEntryReviewModel
    let version: SheetReviewVersion
}
