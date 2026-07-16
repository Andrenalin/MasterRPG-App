// @copyright André Trettin

import SwiftUI

struct ImportReviewCountBadge: View {
    let count: Int
    let systemImage: String
    let tint: Color
    let accessibilityLabel: Text

    var body: some View {
        Label {
            Text(count, format: .number)
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(tint)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(count, format: .number))
    }
}

#Preview {
    ImportReviewCountBadge(
        count: 3,
        systemImage: "exclamationmark.triangle.fill",
        tint: .red,
        accessibilityLabel: Text(verbatim: "Blocked references")
    )
    .padding()
}
