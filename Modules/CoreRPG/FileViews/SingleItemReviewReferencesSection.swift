// @copyright André Trettin

import SwiftUI

struct SingleItemReviewReferencesSection: View {
    let model: SingleItemImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("References", bundle: .module)
                .font(.headline)
            ForEach(model.references) { reference in
                SingleReviewReferenceRow(reference: reference)
            }
        }
    }
}

#Preview { SingleItemReviewReferencesSection(model: .preview).padding() }
