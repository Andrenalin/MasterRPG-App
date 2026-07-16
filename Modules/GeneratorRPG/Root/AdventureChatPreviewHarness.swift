// @copyright André Trettin

import SwiftUI

struct AdventureChatPreviewHarness: View {
    var body: some View {
        AdventureChatRootView(
            sheetModel: AdventureChatPreviewData.sheetModel,
            usesAvailabilityGate: false,
            runsAutomaticGeneration: false,
            previewBlocks: AdventureChatPreviewData.blocks
        )
    }
}

#Preview("Studio - iPhone", traits: .mockData) {
    NavigationStack {
        AdventureChatPreviewHarness()
            .frame(width: 430, height: 780)
    }
}
