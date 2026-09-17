// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGenerationOccurrenceView: View {
    let model: TableGenerationModel
    let occurrence: TableGenerationOccurrence
    let controller: TableGenerationController

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading) {
            TableGenerationOccurrenceHeaderView(
                model: model,
                occurrence: occurrence,
                controller: controller
            )

            if occurrence.allowsMultipleSelection {
                Text(
                    "Select every entry you need. Hide any unwanted entries.",
                    bundle: .module
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach(occurrence.visibleEntries) { entry in
                VStack(alignment: .leading) {
                    TableGenerationEntryRow(
                        entry: entry,
                        occurrence: occurrence,
                        model: model,
                        controller: controller
                    )

                    ForEach(childOccurrences(for: entry)) { child in
                        TableGenerationOccurrenceView(
                            model: model,
                            occurrence: child,
                            controller: controller
                        )
                    }
                }
            }

            if !occurrence.ignoredCycleNames.isEmpty {
                Label {
                    Text(
                        "Skipped recursive link: \(occurrence.ignoredCycleNames.joined(separator: ", "))",
                        bundle: .module
                    )
                } icon: {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            theme.tint(for: .table).opacity(0.08),
            in: .rect(cornerRadius: TableGenerationLayout.groupRadius, style: .continuous)
        )
    }

    private func childOccurrences(
        for entry: TableGenerationEntry
    ) -> [TableGenerationOccurrence] {
        occurrence.children.filter { $0.sourceEntryId == entry.id }
    }
}

#Preview("Dice table", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.preview
    ScrollView {
        TableGenerationOccurrenceView(
            model: model,
            occurrence: model.root,
            controller: .preview
        )
    }
}

#Preview("Multi-select list", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.previewList
    ScrollView {
        TableGenerationOccurrenceView(
            model: model,
            occurrence: model.root,
            controller: .preview
        )
    }
}

#Preview("Nested generation", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.previewNested
    ScrollView {
        TableGenerationOccurrenceView(
            model: model,
            occurrence: model.root,
            controller: .preview
        )
    }
}
