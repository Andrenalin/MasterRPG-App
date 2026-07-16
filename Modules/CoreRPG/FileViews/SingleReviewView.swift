// @copyright André Trettin

import SwiftUI

struct SingleItemReviewAccordionView: View {
    let model: SingleItemImportModel
    var root: (any ItemRootControllable)? = nil
    var rootManager: RootManager? = nil
    var reviewModel: ImportReviewModel? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SingleReviewDecisionCardsView(model: model)

                SingleItemReviewChoicesView(
                    model: model,
                    root: root,
                    rootManager: rootManager,
                    reviewModel: reviewModel
                )
            }
            .padding()
        }
        .navigationTitle(model.name)
    }
}

#Preview { SingleItemReviewAccordionView(model: .preview) }
