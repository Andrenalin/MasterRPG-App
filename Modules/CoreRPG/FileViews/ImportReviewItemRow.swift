// @copyright André Trettin

import SwiftUI

struct ImportReviewItemRow: View {
    let item: ImportReviewItemModel

    var body: some View {
        HStack {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(item.kind.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if item.hasBlockingReference {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .accessibilityLabel(Text("Blocked reference", bundle: .module))
            }

            ImportReviewDecisionBadge(decision: item.itemModel.decision)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(
                "\(item.kind.title): \(item.name). Current decision: \(item.itemModel.decision.title)",
                bundle: .module
            )
        )
    }
}

#Preview("Item Row") {
    ImportReviewItemRow(item: ImportReviewModel.preview.modules[0].reviewItems[0])
        .padding()
}
