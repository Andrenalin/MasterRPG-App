// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Previews the generated outcome. While choices are still being made it's
/// a compact single line (sized like `EntryNameEditor`'s row); once every
/// table is fully decided it expands to show the full text — editing itself
/// happens through the sheet editor opened via `TableGenerationEditAsSheetButton`
/// (see `TableGenerationPanelView`), not inline here.
struct TableGenerationResultView: View {
    let model: TableGenerationModel

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.isFullyDecided {
                expandedOutcome
            } else {
                compactOutcome
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: model.isFullyDecided)
    }

    private var compactOutcome: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(theme.tint(for: .table))

            Text(model.currentOutcome ?? "")
                .bold()
                .lineLimit(1)
                // Keep the most recently added choice (at the end of the
                // string) visible rather than the first one.
                .truncationMode(.head)

            Spacer()
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .background(
            theme.tint(for: .table).opacity(0.18),
            in: .rect(cornerRadius: 16, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("Outcome: \(model.currentOutcome ?? "")", bundle: .module)
        )
    }

    private var expandedOutcome: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text("Outcome", bundle: .module)
            } icon: {
                Image(systemName: "wand.and.stars")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(model.editedOutcome ?? model.currentOutcome ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            theme.tint(for: .table).opacity(0.18),
            in: .rect(cornerRadius: 16, style: .continuous)
        )
    }
}

#Preview("Compact — partial choice", traits: .mockData) {
    // Multi-select table: only the linked entry is decided so far, the
    // rest are still undecided — not fully decided yet, stays compact.
    TableGenerationResultView(model: .previewNested)
        .padding()
}

#Preview("Expanded — single-select resolved", traits: .mockData) {
    // A single-select (dice) table only ever has one decision to make, so
    // picking it is immediately "fully decided".
    TableGenerationResultView(model: .previewResolved)
        .padding()
}

#Preview("Expanded — multi-select fully decided", traits: .mockData) {
    TableGenerationResultView(model: .previewFullyDecided)
        .padding()
}
