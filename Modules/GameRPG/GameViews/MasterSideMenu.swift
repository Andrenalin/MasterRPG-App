// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct MasterSideMenu: View {
    let root: GameRoot
    let adventureId: UUID

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        MasterModuleWindowMenu(adventureId: adventureId)
    }
}

#Preview(traits: .mockData) {
    MasterSideMenu(root: GameRoot.previewFixture(), adventureId: GamePreviewData.adventureID)
        .environment(GameScreenModel())
}
