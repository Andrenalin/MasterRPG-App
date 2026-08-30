// @copyright André Trettin

#if os(visionOS) || os(macOS)
import CoreRPG
import SwiftUI

/// The master's and player's "open another module window" buttons (see
/// `MasterSideMenu`/`PlayerSideMenu`), merged behind a single `isMaster`
/// flag — used inside `GameTableView`'s own leading-side ornament, folded
/// into the *same* `HStack`/`GlassEffectContainerAll` as `windowOpenButton`
/// (row 1 of that ornament's window-controls / `GameTableToolbar` / dice-bar
/// stack) so the whole row reads as one continuous glass group rather than
/// two adjacent ones. Deliberately bare — no own `HStack`, `GlassEffectContainerAll`,
/// or `.padding()` — so `GameTableView` can wrap this together with
/// `windowOpenButton` in a single shared container instead of nesting one
/// glass group inside another; that's also why this isn't its own ornament
/// anymore, which is what this view used to be. `MasterSideMenu`/
/// `PlayerSideMenu` themselves stay as they are for the flat 2D game
/// screens' own trailing ornament, which is a tall vertical column against
/// the screen edge — this isn't a replacement for those, just the same
/// buttons in the row shape the table's window-controls row calls for.
/// Does *not* include the adventure/character window toggle
/// (`GameWindowMenuButtonView`) those two do — that one is `GameTableView`'s
/// own `windowOpenButton`, placed right before this view in the same row;
/// see that property's own doc.
struct GameTableSideMenu: View {
    let root: GameRoot
    let isMaster: Bool

    /// `NetworkModules.gameWindowMasterModules` minus `.game` — `.game`'s own
    /// button (`GameWindowMenuButtonView`) lives in `GameTableView`'s leading
    /// ornament instead, not inline here (see this struct's own doc). Shared
    /// with `MasterModuleWindowMenu`, not a hand-copy — see CODE_AUDIT §9.7.
    private static let masterModules: [NetworkModules] = NetworkModules.gameWindowMasterModules.filter { $0 != .game }

    /// Shared with `PlayerSideMenu.modules`, not a hand-copy — see CODE_AUDIT §9.7.
    private static let playerModules: [NetworkModules] = NetworkModules.gameWindowPlayerModules

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        if isMaster {
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

#Preview("Master", traits: .mockData) {
    GlassEffectContainerAll {
        HStack(spacing: 8) {
            GameTableSideMenu(root: .previewFixture(), isMaster: true)
        }
    }
    .padding()
    .environment(GameScreenModel())
}

#Preview("Player", traits: .mockData) {
    GlassEffectContainerAll {
        HStack(spacing: 8) {
            GameTableSideMenu(root: .previewFixture(game: .player), isMaster: false)
        }
    }
    .padding()
    .environment(GameScreenModel())
}
#endif
