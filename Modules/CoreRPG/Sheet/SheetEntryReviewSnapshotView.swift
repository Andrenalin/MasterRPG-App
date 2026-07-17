// @copyright André Trettin

import SwiftUI

struct SheetEntryReviewSnapshotView: View {
    let sheetModel: SheetModel

    var body: some View {
        VStack(alignment: .leading) {
            if sheetModel.sheetType == .group {
                Label {
                    Text(sheetModel.name.withoutLink())
                } icon: {
                    Image(systemName: "folder")
                }
                .font(.headline)
            } else if !sheetModel.name.isEmpty {
                Text(sheetModel.name.withoutLink())
                    .font(.headline)
            }

            if !sheetModel.description.isEmpty {
                Text(sheetModel.description.withoutLink())
                    .font(.body)
            }

            ForEach(sheetModel.inlineEntries) { inlineSheet in
                SheetEntryReviewInlineSnapshotView(sheetModel: inlineSheet)
            }
        }
    }
}

#Preview("Entry Review Snapshot") {
    let fixture = SheetEntryReviewPreviewFixture()
    SheetEntryReviewSnapshotView(sheetModel: fixture.sheetModel)
        .padding()
}
