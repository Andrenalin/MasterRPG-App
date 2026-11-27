// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct MasterModuleWindowMenu: View {
    let adventureId: UUID

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        GlassEffectContainerAll {
            VStack(spacing: 8) {
                ForEach(NetworkModules.gameWindowMasterModules, id: \.self) { module in
                    if module == .game {
                        GameWindowMenuButtonView(isMaster: true, itemId: adventureId)
                    } else {
                        MasterModuleWindowButtonView(valueType: module)
                    }
                }
            }
        }
#if os(macOS)
        .padding(.trailing, 8)
#else
        .padding()
#endif
    }
}

#Preview(traits: .mockData) {
    MasterModuleWindowMenu(adventureId: GamePreviewData.adventureId)
        .environment(GameScreenModel())
}
