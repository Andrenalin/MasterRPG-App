// @copyright André Trettin

import SwiftUI

struct ImportReviewModuleRow: View {
    let module: ImportReviewModule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(module.name, systemImage: module.id.icon)
                    .bold()
                Spacer()
                Text(module.reviewItems.count, format: .number)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if !module.addedItems.isEmpty {
                    ImportReviewCountBadge(
                        count: module.addedItems.count,
                        systemImage: "circle.fill",
                        tint: .green,
                        accessibilityLabel: Text("Added items", bundle: .module)
                    )
                }

                if !module.changedItems.isEmpty {
                    ImportReviewCountBadge(
                        count: module.changedItems.count,
                        systemImage: "circle.fill",
                        tint: .orange,
                        accessibilityLabel: Text("Changed items", bundle: .module)
                    )
                }

                if module.blockedReferenceCount > 0 {
                    ImportReviewCountBadge(
                        count: module.blockedReferenceCount,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .red,
                        accessibilityLabel: Text("Blocked references", bundle: .module)
                    )
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(
                "Module \(module.name), \(module.reviewItems.count) items, \(module.addedItems.count) added, \(module.changedItems.count) changed, \(module.blockedReferenceCount) blocked references",
                bundle: .module
            )
        )
    }
}

#Preview("Module Row") {
    ImportReviewModuleRow(module: ImportReviewModel.preview.modules[0])
        .padding()
}
