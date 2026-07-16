// @copyright André Trettin

import SwiftUI

struct SingleItemReviewEntriesSection: View {
    let model: SingleItemImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Entries", bundle: .module)
                    .font(.headline)
                Spacer()
                if model.entriesAreIdentical {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .accessibilityLabel(Text("All entries exist in both versions", bundle: .module))
                } else {
                    let existingCount = model.item.existing?.entries.count ?? 0
                    let importedCount = model.item.imported?.entries.count ?? 0
                    if existingCount != importedCount {
                        Text("\(existingCount) existing · \(importedCount) imported", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(model.entries) { entry in
                SingleReviewEntryRow(entry: entry)
            }
        }
    }
}

#Preview { SingleItemReviewEntriesSection(model: .preview).padding() }
