// @copyright André Trettin

import SwiftUI

struct SingleReviewAlternativeBlock: View {
    let decision: SingleReviewDecision
    var kind: SingleReviewKind = .text
    let value: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                Label(decision.title, systemImage: decision.systemImage)
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(decision.tint)
                SingleReviewValueView(kind: kind, value: value)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(decision.tint.opacity(0.08))
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(decision.tint.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Choose this version for the property", bundle: .module))
    }
}

extension Optional where Wrapped == String {
    var reviewTags: [String] {
        guard let value = self else { return [] }
        return value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

#Preview {
    SingleReviewAlternativeBlock(
        decision: .imported,
        value: "The new expedition begins at the forgotten shrine.",
        onSelect: {}
    )
    .padding()
}
