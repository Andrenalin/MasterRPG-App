// @copyright André Trettin

#if os(visionOS) || os(macOS)
import CoreRPG
import SwiftUI

/// The master's and player's "open another window" menu (see
/// `MasterSideMenu`/`PlayerSideMenu`), merged behind a single `isMaster`
/// flag and laid out horizontally — used as the volumetric game table's own
/// trailing-side ornament (`GameTableView`), a companion row to the
/// leading-side map toolbar + dice bar. `MasterSideMenu`/`PlayerSideMenu`
/// themselves stay as they are for the flat 2D game screens' own trailing
/// ornament, which is a tall vertical column against the screen edge — this
/// isn't a replacement for those, just the same buttons in the row shape a
/// second, table-side ornament calls for.
struct GameTableSideMenu: View {
    let root: GameRoot
    let isMaster: Bool
    /// Only needed for the master's own "open the adventure window" button
    /// (see `MasterGameWindowButtonView`) — `nil` hides that one button
    /// rather than requiring an adventure to already be selected before the
    /// table volume can even show its ornament.
    let adventureId: UUID?

    /// Mirrors `MasterModuleWindowMenu.modules`, minus `.game` — handled as
    /// its own leading button below instead of inline, since this is the
    /// only entry needing `adventureId`.
    private static let masterModules: [NetworkModules] = [
        .adventure, .audio, .dice, .map, .pdf, .photo, .rule, .space, .table, .value, .weather
    ]

    /// Mirrors `PlayerSideMenu.modules`.
    private static let playerModules: [NetworkModules] = [
        .value, .table, .audio, .photo, .pdf, .space, .dice
    ]

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        GlassEffectContainerAll {
            HStack(spacing: 8) {
                if isMaster {
                    if let adventureId {
                        MasterGameWindowButtonView(adventureId: adventureId)
                    }
                    ForEach(Self.masterModules, id: \.self) { module in
                        MasterModuleWindowButtonView(valueType: module)
                    }
                    GameWindowButtonView(
                        title: String(localized: "Logs", bundle: .module),
                        systemImage: "doc.text.magnifyingglass",
                        module: .game,
                        sceneId: .logs
                    )
                } else {
                    if root.gameModel.gameType != .observer {
                        PlayerGameWindowButtonView(root: root)
                    }
                    ForEach(Self.playerModules, id: \.self) { module in
                        GameWindowButtonView(
                            title: module.title,
                            systemImage: module.icon,
                            module: module,
                            sceneId: SceneId.sceneId(for: module)
                        )
                    }
                }
            }
        }
        .padding()
    }
}

#Preview("Master", traits: .mockData) {
    GameTableSideMenu(root: .previewFixture(), isMaster: true, adventureId: GamePreviewData.adventureID)
        .environment(GameScreenModel())
}

#Preview("Player", traits: .mockData) {
    GameTableSideMenu(root: .previewFixture(game: .player), isMaster: false, adventureId: nil)
        .environment(GameScreenModel())
}
#endif
