// @copyright André Trettin

import SwiftUI

struct SingleReviewEntryRow: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let entry: SingleEntryImportModel
    @State private var isExpanded = false

    private var hasExisting: Bool { entry.entry.existing != nil }
    private var hasImported: Bool { entry.entry.imported != nil }

    private func summary(from source: (any EntryDataAccessable)?) -> String? {
        guard let source else { return nil }
        let namePart = entry.properties.count > 0 ? source[keyPath: entry.properties[0].valueKeyPath] : ""
        let contentPart = entry.properties.count > 1 ? source[keyPath: entry.properties[1].valueKeyPath] : ""
        let pieces = [namePart, contentPart].filter { !$0.isEmpty }
        return pieces.isEmpty ? nil : pieces.joined(separator: " — ")
    }

    private var anyPropertyChanged: Bool {
        entry.properties.contains { entry.isChanged(prop: $0) }
    }

    private var indicatorName: String {
        (!anyPropertyChanged && hasExisting && hasImported) ? "checkmark.circle.fill" : "circle.fill"
    }

    private var indicatorColor: Color {
        if !anyPropertyChanged && hasExisting && hasImported { return .secondary.opacity(0.5) }
        if hasExisting && !hasImported { return .orange }
        if hasImported && !hasExisting { return .green }
        return entry.decision.tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(accessibilityReduceMotion ? nil : .spring(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: indicatorName)
                            .font(.subheadline)
                            .foregroundStyle(indicatorColor)
                        SingleReviewLinkText(text: entry.name)
                            .font(.subheadline)
                            .bold()
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if !entry.isRemovalSummary && !entry.content.isEmpty {
                        SingleReviewLinkText(text: entry.content)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }

                    if !entry.isRemovalSummary {
                        if anyPropertyChanged {
                            HStack(spacing: 4) {
                                Text("Was:", bundle: .module)
                                    .font(.caption2)
                                    .bold()
                                    .foregroundStyle(.orange)
                                SingleReviewLinkText(text: summary(from: entry.entry.existing) ?? "—")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            HStack(spacing: 4) {
                                Text("New:", bundle: .module)
                                    .font(.caption2)
                                    .bold()
                                    .foregroundStyle(.green)
                                SingleReviewLinkText(text: summary(from: entry.entry.imported) ?? "—")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else if hasExisting && !hasImported {
                            Text("Only in existing version", bundle: .module)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else if hasImported && !hasExisting {
                            Text("Only in imported version", bundle: .module)
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(isExpanded ? "Collapse entry details" : "Expand entry details", bundle: .module))

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.properties) { SingleReviewEntryPropertyRow(entry: entry, property: $0) }
                }
                .padding(12)
            }
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(.rect(cornerRadius: 10))
    }
}

#Preview {
    SingleReviewEntryRow(entry: SingleItemImportModel.preview.entries[0])
        .padding()
}
