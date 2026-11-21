// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct MasterSideMenu: View {
    let root: GameRoot
    let adventureId: UUID

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
#if os(visionOS)
        VStack {
            MasterModuleWindowMenu(adventureId: adventureId)

            // The players button is in the top ornament's menu; this one is the last window button.
            GameTableWindowButton(root: root)
        }
#else
        MasterModuleWindowMenu(adventureId: adventureId)
#endif
    }
}

#Preview(traits: .mockData) {
    MasterSideMenu(root: GameRoot.previewFixture(), adventureId: GamePreviewData.adventureID)
        .environment(GameScreenModel())
}
