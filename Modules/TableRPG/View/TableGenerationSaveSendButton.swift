// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The single commit action for a generated outcome, shown directly under
/// the (now editable) outcome once every table is fully decided. While a
/// game is running and this device is the master, it becomes a "Send" menu
/// to a player or everyone; otherwise it "Saves" the outcome as a new value
/// on the character.
struct TableGenerationSaveSendButton: View {
    let saveAction: () -> Void
    let sendAction: (UUID?) -> Void

    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingControlActions) private var sharingControlActions
    @Environment(AppGameStateModel.self) private var gameState

    var body: some View {
        HStack {
            Spacer()

            if isGameSendMode {
                sendMenu
            } else {
                saveButton
            }
        }
    }

    private var saveButton: some View {
        Button(action: saveAction) {
            Image(systemName: "checkmark")
        }
        .selectedRoundButton(
            title: String(localized: "Save", bundle: .module),
            module: .table,
            isSelected: false
        )
    }

    private var sendMenu: some View {
        Menu {
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

            Divider()

            Button {
                sendAction(nil)
            } label: {
                Label {
                    Text("Send to all", bundle: .module)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .selectedRoundButton(
            title: String(localized: "Send", bundle: .module),
            module: .table,
            isSelected: false
        )
        .disabled(visiblePlayers.isEmpty)
    }

    private var isGameSendMode: Bool {
        gameState.isGameRunning
            && gameState.gameModus == .master
            && networkActions != nil
    }

    private var visiblePlayers: [SharingControlModel] {
        (sharingControlActions.control?() ?? [])
            .filter(\.show)
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}

#Preview("Save (no game running)", traits: .mockData) {
    TableGenerationSaveSendButton(saveAction: {}, sendAction: { _ in })
        .padding()
}

#Preview("Send (game master, players visible)", traits: .mockData) {
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
