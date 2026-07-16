// @copyright André Trettin

import SwiftUI

struct AdventureChatHeaderView: View {
    let seedBlocks: [AdventureChatSeedBlock]
    let sourceCount: Int
    let generatedCount: Int
    let selectedCount: Int

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                AdventureChatMetricPill(
                    value: seedBlocks.count,
                    label: String(localized: "Context", bundle: .module),
                    systemImage: "doc.text"
                )
                AdventureChatMetricPill(
                    value: sourceCount,
                    label: String(localized: "Sheet Blocks", bundle: .module),
                    systemImage: "text.book.closed"
                )
                AdventureChatMetricPill(
                    value: generatedCount,
                    label: String(localized: "Blocks", bundle: .module),
                    systemImage: "square.stack.3d.up"
                )
                AdventureChatMetricPill(
                    value: selectedCount,
                    label: String(localized: "Selected", bundle: .module),
                    systemImage: "checkmark.circle"
                )
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .padding()
    }
}

#Preview {
    AdventureChatHeaderView(seedBlocks: [], sourceCount: 3, generatedCount: 4, selectedCount: 2)
}
