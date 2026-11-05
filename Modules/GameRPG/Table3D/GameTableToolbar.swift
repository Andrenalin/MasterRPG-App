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
    let root: GameRoot
    let game: GameTableModel

    var body: some View {
        HStack {
            // Always visible: this is the switch between the 2D map window
            // and this 3D game table, so it must stay reachable even before
            // a map is loaded onto the table.
            GameTableWindowButton(root: root, isMaster: game.isGameMaster)

            if game.isGameMaster,
               root.gameModel.playerController?.gameModel.tableWeather.shownWeatherId != nil {
                GameTableClearWeatherButton(root: root)
            }

            // The shared map toolbar's actions (fog, pointer, room
            // visibility) are meaningless before a map is on the table.
            if game.currentMapId != nil {
                game.mapRoot.viewController.gameToolBarView(
                    root: game.mapRoot,
                    isMaster: game.isGameMaster,
                    session: game
                )
            }
        }
    }
}

/// Takes the game master's weather off every table.
@MainActor
private struct GameTableClearWeatherButton: View {
    let root: GameRoot

    var body: some View {
        Button {
            root.scheduleTableWeatherClear()
        } label: {
            Label {
                Text("Clear Weather", bundle: .module)
            } icon: {
                Image(systemName: "cloud.slash")
            }
        }
        .selectedRoundButton(
            title: String(localized: "Clear Weather", bundle: .module),
            module: .weather,
            isSelected: false
        )
    }
}

#Preview(traits: .mockData) {
    @Previewable @State var game: GameTableModel?

    Group {
        if let game {
            GameTableToolbar(root: .preview, game: game)
        } else {
            ProgressView()
        }
    }
    .task {
        game = GameTableModel(mapRoot: .preview, photoRoot: .preview)
    }
}

#endif
