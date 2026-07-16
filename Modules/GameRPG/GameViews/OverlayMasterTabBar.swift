// @copyright André Trettin

import Foundation
import SwiftUI

struct OverlayMasterTabBar: View {
    let root: GameRoot
    let adventureId: UUID

    var body: some View {
        ZStack(alignment: .trailing) {
#if os(macOS) || os(visionOS)
            OnlyGameView(root: root, adventureId: adventureId)
#else
            TabGameView(root: root, adventureId: adventureId)
            TabSecondGameView(root: root)
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

#Preview {
    OverlayMasterTabBar(root: .previewFixture(), adventureId: GamePreviewData.adventureID)
        .environment(GameScreenModel())
}
