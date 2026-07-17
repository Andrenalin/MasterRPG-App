// @copyright André Trettin

import SwiftUI

struct SheetEntryReviewPlaceholderView: View {
    let entryModel: SheetModel
    let reviewModel: SheetEntryReviewModel

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label {
                    Text(entryModel.name.withoutLink())
                        .font(.headline)
                } icon: {
                    Image(systemName: "minus.circle")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                SheetEntryReviewButton(model: reviewModel)
            }

            Text("Not present or shown in the selected version", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Entry Review Placeholder") {
    let fixture = SheetEntryReviewPreviewFixture()
    SheetEntryReviewPlaceholderView(
        entryModel: fixture.sheetModel,
        reviewModel: fixture.reviewModel
    )
    .padding()
}
