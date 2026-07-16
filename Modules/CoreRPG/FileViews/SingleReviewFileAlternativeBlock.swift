// @copyright André Trettin

import SwiftUI

struct SingleReviewFileAlternativeBlock<Thumbnail: View>: View {
    let decision: SingleReviewDecision
    let value: String?
    @ViewBuilder let thumbnail: () -> Thumbnail
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                thumbnail()
                VStack(alignment: .leading, spacing: 5) {
                    Label(decision.title, systemImage: decision.systemImage)
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(decision.tint)
                    Text(value ?? "-")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.primary)
                }
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
        .accessibilityHint(Text("Choose this file version", bundle: .module))
    }
}

#Preview("File Alternative") {
    SingleReviewFileAlternativeBlock(decision: .imported, value: "mara.png") {
        Image(systemName: "photo")
            .frame(width: 44, height: 44)
    } onSelect: {}
    .padding()
}
