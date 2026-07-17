// @copyright André Trettin

import SwiftUI

struct SheetEntryReviewAlternativesView: View {
    let reviewModel: SheetEntryReviewModel

    var body: some View {
        if reviewModel.isExpanded {
            VStack(alignment: .leading) {
                ForEach(reviewModel.versions) { version in
                    SheetEntryReviewVersionButton(
                        version: version,
                        isSelected: reviewModel.decision == version.decision,
                        selectAction: { reviewModel.select(version.decision) }
                    )
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview("Entry Review Alternatives") {
    let fixture = SheetEntryReviewPreviewFixture()
    SheetEntryReviewAlternativesView(reviewModel: fixture.reviewModel)
        .padding()
}
