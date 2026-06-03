// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SharingActionView: View, Equatable {
    let itemId: UUID
    let showPlayControl: Bool

    @Environment(AudioRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingFeatureActions) private var sharingFeatureActions
    @Environment(AppGameStateModel.self) private var appGameStateModel

    @State private var waitForSharing: Bool = false

    var body: some View {
        if appGameStateModel.isGameRunning {
            EmptyView()
                .shareListItem(isActive: canShare, allReported: allReported, feedBackEnabled: true, secondActionIcon: playIcon) {
                    shareAudio()
                } secondAction: {
                    if allReported {
                        networkActions?.game(root.gameController.requestPlay(id: itemId), .playAudio, nil)
                    } else {
                        waitForSharing = true
                        shareAudio()
                    }
                }
                .onChange(of: allReported) { _, newValue in
                    if waitForSharing && newValue {
                        waitForSharing = false
                        networkActions?.game(root.gameController.requestPlay(id: itemId), .playAudio, nil)
                    }
                }
        } else if showPlayControl {
            Button {
                Task {
                    let list = root.itemController.audioList(itemId: itemId)
                    await root.audioController.add(audio: list, replace: true)
                    root.audioController.togglePlay(id: list.first?.id)
                }
            } label: {
                Image(systemName: "play.rectangle.on.rectangle")
            }
            .accessibilityLabel(String(localized: "Play", bundle: .module))
            .disabled(!root.itemController.hasAudio(itemId: itemId))
        }
    }

    // Computed once per render — avoids calling allPlayersReported repeatedly
    // in shareListItem, secondAction, onChange, and playIcon.
    private var allReported: Bool {
        root.gameController.allPlayersReported(for: itemId)
    }

    private var canShare: Bool {
        if appGameStateModel.gameModus == .player {
            return sharingFeatureActions.features().audioSharing && appGameStateModel.isGameRunning
        }
        return appGameStateModel.isGameRunning
    }

    private var playIcon: String {
        if appGameStateModel.isGameRunning && !allReported {
            return "square.and.arrow.up"
        }
        return root.gameController.isPlayingPlaylist(id: itemId) ? "pause" : "play"
    }

    private func shareAudio() {
        Task {
            if appGameStateModel.gameModus == .master {
                await networkActions?.shareId(root.gameController.share(id: itemId))
            } else {
                if let result = try? await root.gameController.createGameData(for: itemId) {
                    networkActions?.game(result, .generic, nil)
                }
            }
        }
    }

    // showPlayControl must be included — omitting it would prevent the non-game
    // play button from appearing/disappearing when the parent changes the value.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId && lhs.showPlayControl == rhs.showPlayControl
    }
}
