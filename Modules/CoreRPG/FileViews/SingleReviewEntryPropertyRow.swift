// @copyright André Trettin

import SwiftUI

struct SingleReviewEntryPropertyRow: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let entry: SingleEntryImportModel
    let property: SingleReviewEntryProperty
    @State private var isExpanded = false

    private var isOverridden: Bool { property.decision != entry.decision }

    private var alternatives: [SingleReviewDecision] {
        property.availableDecisions.filter { $0 != property.decision }
    }

    private func value(for decision: SingleReviewDecision) -> String? {
        switch decision {
        case .existing: entry.existingValue(for: property)
        case .imported: entry.importedValue(for: property)
        case .merge: entry.mergedValue(for: property)
        }
    }

    var body: some View {
        if !entry.isChanged(prop: property) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary.opacity(0.4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(property.displayName)
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.secondary)
                    SingleReviewValueView(kind: property.kind, value: entry.effectiveValue(for: property), lineLimit: 1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(Color.secondary.opacity(0.03))
            .clipShape(.rect(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(accessibilityReduceMotion ? nil : .spring(duration: 0.3)) { isExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: isOverridden ? "circle.fill" : "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(isOverridden ? property.decision.tint : .secondary.opacity(0.5))
                            Text(property.displayName)
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.secondary)
                            Spacer()
                            Label(property.decision.title, systemImage: property.decision.systemImage)
                                .font(.caption2)
                                .foregroundStyle(property.decision.tint)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        SingleReviewValueView(kind: property.kind, value: entry.effectiveValue(for: property))
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .contentTransition(.opacity)
                            .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: property.decision)
                        HStack(spacing: 4) {
                            Text("Was:", bundle: .module)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.orange)
                            SingleReviewValueView(kind: property.kind, value: entry.existingValue(for: property), lineLimit: 1)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text("New:", bundle: .module)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.green)
                            SingleReviewValueView(kind: property.kind, value: entry.importedValue(for: property), lineLimit: 1)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(isExpanded ? "Collapse property choices" : "Expand property choices", bundle: .module))

                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(alternatives) { decision in
                            SingleReviewAlternativeBlock(decision: decision, kind: property.kind, value: value(for: decision)) {
                                withAnimation(accessibilityReduceMotion ? nil : .spring(duration: 0.3)) {
                                    entry.setPropertyDecision(decision, propertyID: property.id)
                                    isExpanded = false
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .background(Color.secondary.opacity(0.05))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}

#Preview {
    let entry = SingleItemImportModel.preview.entries[0]
    SingleReviewEntryPropertyRow(entry: entry, property: entry.properties[0])
        .padding()
}
