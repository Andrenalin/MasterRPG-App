// @copyright André Trettin

import SwiftUI

struct SingleReviewPropertyRow: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let model: SingleItemImportModel
    let property: SingleReviewItemProperty
    @State private var isExpanded = false

    private var isOverridden: Bool { property.decision != model.decision }

    private var alternatives: [SingleReviewDecision] {
        property.availableDecisions.filter { $0 != property.decision }
    }

    private func value(for decision: SingleReviewDecision) -> String? {
        switch decision {
        case .existing: model.existingValue(for: property)
        case .imported: model.importedValue(for: property)
        case .merge: model.mergedValue(for: property)
        }
    }

    var body: some View {
        if !model.isChanged(prop: property) {
            SingleReviewStaticPropertyRow(
                displayName: property.displayName,
                kind: property.kind,
                value: model.effectiveValue(for: property)
            )
        } else if property.isReadOnly {
            SingleReviewReadOnlyPropertyRow(model: model, property: property)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(accessibilityReduceMotion ? nil : .spring(duration: 0.3)) { isExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: isOverridden ? "circle.fill" : "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(isOverridden ? property.decision.tint : .secondary.opacity(0.5))
                            Text(property.displayName)
                                .font(.subheadline)
                                .bold()
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        SingleReviewValueView(kind: property.kind, value: model.effectiveValue(for: property))
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .contentTransition(.opacity)
                            .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: property.decision)
                        HStack(spacing: 4) {
                            Text("Was:", bundle: .module)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.orange)
                            SingleReviewValueView(kind: property.kind, value: model.existingValue(for: property), lineLimit: 1)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text("New:", bundle: .module)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.green)
                            SingleReviewValueView(kind: property.kind, value: model.importedValue(for: property), lineLimit: 1)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityHint(expansionHint)

                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(alternatives) { decision in
                            SingleReviewAlternativeBlock(decision: decision, kind: property.kind, value: value(for: decision)) {
                                withAnimation(accessibilityReduceMotion ? nil : .spring(duration: 0.3)) {
                                    model.setPropertyDecision(decision, propertyId: property.id)
                                    isExpanded = false
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .background(Color.secondary.opacity(0.05))
            .clipShape(.rect(cornerRadius: 10))
        }
    }

    private var expansionHint: Text {
        isExpanded ? Text("Collapse choices", bundle: .module) : Text("Show choices", bundle: .module)
    }
}

#Preview("Property") {
    let model = SingleItemImportModel.preview
    SingleReviewPropertyRow(model: model, property: model.properties[0])
        .padding()
}
