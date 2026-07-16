// @copyright André Trettin

import SwiftUI

struct SingleReviewDecisionHeaderView: View {
    let item: SingleItemImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.title2)
                .bold()
            Text(item.description)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SingleReviewDecisionHeaderView(item: .preview)
        .padding()
}
