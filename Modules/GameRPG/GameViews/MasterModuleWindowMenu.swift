// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct MasterModuleWindowMenu: View {
    let adventureId: UUID

    private static let modules: [NetworkModules] = [
        .game,
        .adventure,
        .audio,
        .dice,
        .map,
        .pdf,
        .photo,
        .space,
        .table,
        .value,
        .weather
    ]

    var body: some View {
        GlassEffectContainerAll {
            VStack(spacing: 8) {
                ForEach(Self.modules, id: \.self) { module in
                    if module == .game {
                        MasterGameWindowButtonView(adventureId: adventureId)
                    } else {
                        MasterModuleWindowButtonView(valueType: module)
                    }
                }

                GameWindowButtonView(
                    title: String(localized: "Logs", bundle: .module),
                    systemImage: "doc.text.magnifyingglass",
                    tint: NetworkModules.game.tint,
                    sceneId: .logs
                )

#if os(macOS)
                GameWindowButtonView(
                    title: String(localized: "Battle Round", bundle: .module),
                    systemImage: "shield.lefthalf.filled",
                    tint: NetworkModules.game.tint,
                    sceneId: .battleRound
                )
#endif
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
    MasterModuleWindowMenu(adventureId: GamePreviewData.adventureID)
        .environment(GameScreenModel())
}
