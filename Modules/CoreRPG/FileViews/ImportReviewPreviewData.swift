// @copyright André Trettin

import SwiftUI

private extension ImportReviewModel {
    static var preview: ImportReviewModel {
        let previewItem = SingleItemImportModel.preview

        let blackKeep = ImportReviewItemModel(
            id: UUID(),
            kind: .different,
            existingStatus: "5 scenes, local notes kept",
            importedStatus: "7 scenes, new finale",
            mergedStatus: "7 scenes, local notes + imported finale",
            itemModel: previewItem
        )
        let frozenVault = ImportReviewItemModel(
            id: UUID(),
            kind: .added,
            existingStatus: "Not in library",
            importedStatus: "3 scenes, 1 map, 2 tables",
            mergedStatus: "Ready to add",
            itemModel: previewItem
        )
        let maraVenn = ImportReviewItemModel(
            id: UUID(),
            kind: .different,
            existingStatus: "Level 4, portrait set",
            importedStatus: "Level 5, new spell list",
            mergedStatus: "Level 5, existing portrait, combined notes",
            itemModel: previewItem
        )
        let captainHarl = ImportReviewItemModel(
            id: UUID(),
            kind: .added,
            existingStatus: "Not in library",
            importedStatus: "New NPC from imported adventure",
            mergedStatus: "Ready to add",
            itemModel: previewItem
        )

        return ImportReviewModel(modules: [
            ImportReviewModule(id: .adventure, reviewItems: [blackKeep, frozenVault]),
            ImportReviewModule(id: .value, reviewItems: [maraVenn, captainHarl]),
        ])
    }
}

#Preview("Import Review Split View") {
    ImportReviewSplitView(model: .preview, rootManager: nil, onCancel: {}, onApply: {})
}
