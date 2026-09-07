// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The commit action for a generated outcome, shown on the footer toolbar
/// alongside Close once the outcome's sheet editor is open. While a game is
/// running and this device is the master, it becomes a combined "Save and
/// Share" menu — the outcome can still be saved as a new value on the
/// character, or shared to a player/everyone over the active game session;
/// otherwise it's a plain "Save" button.
struct TableGenerationSaveSendButton: View {
    let saveAction: () -> Void
    let sendAction: (UUID?) -> Void

    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var gameState

    var body: some View {
        if isGameSendMode {
            TableGenerationSaveAndShareMenuView(saveAction: saveAction, sendAction: sendAction)
        } else {
            TableGenerationSaveButtonView(saveAction: saveAction)
        }
    }

    private var isGameSendMode: Bool {
        gameState.isGameRunning
            && gameState.gameModus == .master
            && networkActions != nil
    }
}

private struct TableGenerationSaveButtonView: View {
    let saveAction: () -> Void

    var body: some View {
        Button(action: saveAction) {
            Image(systemName: "square.and.arrow.down")
        }
        .selectedRoundButton(
            title: String(localized: "Save", bundle: .module),
            module: .table,
            isSelected: false
        )
    }
}

private struct TableGenerationSaveAndShareMenuView: View {
    let saveAction: () -> Void
    let sendAction: (UUID?) -> Void

    @Environment(\.sharingControlActions) private var sharingControlActions

    var body: some View {
        Menu {
            Button(action: saveAction) {
                Label {
                    Text("Save", bundle: .module)
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                }
            }

            if !visiblePlayers.isEmpty {
                Divider()

                ForEach(visiblePlayers) { player in
                    Button {
                        sendAction(player.id)
                    } label: {
                        Label {
                            Text("Send to \(player.name)", bundle: .module)
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                        }
                    }
                }

                Button {
                    sendAction(nil)
                } label: {
                    Label {
                        Text("Send to all", bundle: .module)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .selectedRoundButton(
            title: String(localized: "Save and Share", bundle: .module),
            module: .table,
            isSelected: false
        )
    }

    private var visiblePlayers: [SharingControlModel] {
        (sharingControlActions.control?() ?? []).visibleSortedByName
    }
}

#Preview("Save (no game running)", traits: .mockData) {
    TableGenerationSaveSendButton(saveAction: {}, sendAction: { _ in })
        .padding()
}

#Preview("Save and Share (game master, players visible)", traits: .mockData) {
    @Previewable @State var gameState: AppGameStateModel = {
        let state = AppGameStateModel()
        state.isGameRunning = true
        state.gameModus = .master
        return state
    }()

    TableGenerationSaveSendButton(saveAction: {}, sendAction: { _ in })
        .padding()
        .environment(gameState)
        .environment(
            \.networkActions,
            NetworkActions(shareId: { _ in }, send: { _ in }, game: { _, _, _ in })
        )
        .environment(
            \.sharingControlActions,
            SharingControlActions(
                control: {
                    [
                        SharingControlModel(id: UUID(), name: "Aldric", show: true),
                        SharingControlModel(id: UUID(), name: "Mira", show: true),
                    ]
                },
                update: nil
            )
        )
}
