// @copyright André Trettin

import SwiftUI

struct SingleItemReviewChoicesView: View {
    let model: SingleItemImportModel
    var root: (any ItemRootControllable)? = nil
    var rootManager: RootManager? = nil
    var reviewModel: ImportReviewModel? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !model.references.isEmpty {
                SingleItemReviewReferencesSection(model: model)
            }

            SingleItemReviewPropertiesSection(
                model: model,
                root: root,
                rootManager: rootManager,
                reviewModel: reviewModel
            )

            if !model.entries.isEmpty {
                SingleItemReviewEntriesSection(model: model)
            }
        }
    }
}

#Preview { SingleItemReviewChoicesView(model: .preview) }
