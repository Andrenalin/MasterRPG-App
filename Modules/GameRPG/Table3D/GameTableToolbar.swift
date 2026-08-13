// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import MapRPG
import PhotoRPG
import SwiftUI

/// Hosts the exact same `GameToolBar` the 2D map uses (via `GameToolBarSession`
/// conformance on `GameTableModel`), so the game master gets one consistent
/// set of controls and actions regardless of which representation is on
/// screen. No bespoke 3D-only buttons remain: "Show/Hide Pointer" and
/// "Center Pointer" merged into the shared toolbar's single pointing-mode
/// toggle (see `GameToolBar.togglePointingMode()`), and the room-visibility
/// menu was dropped — both representations already toggle a room's fog by
/// interacting with it directly (`GameTableModel.toggleRoomVisibility`).
@MainActor
struct GameTableToolbar: View {
    let game: GameTableModel

    var body: some View {
        HStack {
            GameTableWindowButton()

            game.mapRoot.viewController.gameToolBarView(
                root: game.mapRoot,
                isMaster: game.isGameMaster,
                session: game
            )
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @State var game: GameTableModel?

    Group {
        if let game {
            GameTableToolbar(game: game)
        } else {
            ProgressView()
        }
    }
    .task {
        game = GameTableModel(mapRoot: .preview, photoRoot: .preview)
    }
}

#endif
