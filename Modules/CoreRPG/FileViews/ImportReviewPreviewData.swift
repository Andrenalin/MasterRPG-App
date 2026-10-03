// @copyright André Trettin

import SwiftUI

extension ImportReviewModel {
    static var preview: ImportReviewModel {
        let previewItem = SingleItemImportModel.preview

        let blackKeep = ImportReviewItemModel(
            id: UUID(),
            kind: .different,
            itemModel: previewItem
        )
        let frozenVault = ImportReviewItemModel(
            id: UUID(),
            kind: .added,
            itemModel: previewItem
        )
        let maraVenn = ImportReviewItemModel(
            id: UUID(),
            kind: .different,
            itemModel: previewItem
        )
        let captainHarl = ImportReviewItemModel(
            id: UUID(),
            kind: .added,
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
