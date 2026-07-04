// @copyright André Trettin

import SwiftUI

struct ImportReviewItemListView: View {
    let module: ImportReviewModule
    @Binding var selectedID: ImportReviewItemModel.ID?

    var body: some View {
        List(selection: $selectedID) {
            if !module.addedItems.isEmpty {
                Section {
                    ForEach(module.addedItems) { item in
                        ImportReviewItemRow(item: item)
                    }
                } header: {
                    Text("Added", bundle: .module)
                }
            }

            if !module.changedItems.isEmpty {
                Section {
                    ForEach(module.changedItems) { item in
                        ImportReviewItemRow(item: item)
                    }
                } header: {
                    Text("Changed", bundle: .module)
                }
            }
        }
    }
}

private struct ImportReviewItemRow: View {
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
