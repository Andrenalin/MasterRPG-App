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

            // macOS has the button in the toolbar, iOS in the overlay's control field.
            TablePlayersButton(root: root)
                .imageScale(.large)
                .padding(8)
                .contentShape(.circle)
                .modifier(GameWindowButtonAppearance(module: .value, isWindowPresented: false))
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
