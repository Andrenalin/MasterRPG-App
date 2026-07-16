// @copyright André Trettin

import SwiftUI

struct SingleItemReviewPropertiesSection: View {
    let model: SingleItemImportModel
    var root: (any ItemRootControllable)? = nil
    var rootManager: RootManager? = nil
    var reviewModel: ImportReviewModel? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Properties", bundle: .module)
                .font(.headline)
            ForEach(model.properties) { property in
                if property.kind == .binary {
                    SingleReviewFilePropertyRow(model: model, property: property, root: root)
                } else if property.kind == .link {
                    SingleReviewLinkedPropertyRow(
                        model: model,
                        property: property,
                        rootManager: rootManager,
                        reviewModel: reviewModel
                    )
                } else {
                    SingleReviewPropertyRow(model: model, property: property)
                }
            }
        }
    }
}

#Preview { SingleItemReviewPropertiesSection(model: .preview).padding() }
