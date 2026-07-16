// @copyright André Trettin

import SwiftUI

struct AdventureChatMetricPill: View {
    let value: Int
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(value, format: .number)
            Text(verbatim: label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: .rect(cornerRadius: 8))
    }
}

#Preview {
    AdventureChatMetricPill(value: 4, label: "Blocks", systemImage: "square.stack.3d.up")
        .padding()
}
