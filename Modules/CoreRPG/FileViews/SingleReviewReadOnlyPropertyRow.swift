// @copyright André Trettin

import SwiftUI

struct SingleReviewReadOnlyPropertyRow: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let model: SingleItemImportModel
    let property: SingleReviewItemProperty

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(property.decision.tint)
                Text(property.displayName)
                    .font(.subheadline)
                    .bold()
                Spacer()
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let model = SingleItemImportModel.preview
    SingleReviewReadOnlyPropertyRow(model: model, property: model.properties[0])
        .padding()
}
