// @copyright André Trettin

import SwiftUI

struct ImportReviewDecisionBadge: View {
    let decision: SingleReviewDecision

    var body: some View {
        Label(decision.title, systemImage: decision.systemImage)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(decision.tint.opacity(0.15))
            .foregroundStyle(decision.tint)
            .clipShape(.capsule)
    }
}

#Preview("Decision Badge") {
    ImportReviewDecisionBadge(decision: .merge)
        .padding()
}
