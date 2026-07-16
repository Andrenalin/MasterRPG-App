// @copyright André Trettin

import SwiftUI

struct SingleReviewStaticPropertyRow: View {
    let displayName: String
    var kind: SingleReviewKind = .text
    let value: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(Color.secondary.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline)
                    .bold()
                SingleReviewValueView(kind: kind, value: value, lineLimit: 1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.03))
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SingleReviewStaticPropertyRow(displayName: "Description", value: "A suspicious ranger.")
        .padding()
}
