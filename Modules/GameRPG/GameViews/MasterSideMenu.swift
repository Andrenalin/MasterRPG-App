// @copyright André Trettin

import Foundation
import SwiftUI

struct MasterSideMenu: View {
    let adventureId: UUID

    var body: some View {
        MasterModuleWindowMenu(adventureId: adventureId)
    }
}

#Preview(traits: .mockData) {
    MasterSideMenu(adventureId: GamePreviewData.adventureID)
        .environment(GameScreenModel())
}
