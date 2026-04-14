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
                .shareListItem(isActive: canShare, allReported: root.gameController.allPlayersReported(for: itemId), feedBackEnabled: true, secondActionIcon: playIcon) {
                    shareAudio()
                } secondAction: {
                    if root.gameController.allPlayersReported(for: itemId) {
                        networkActions?.game(root.gameController.requestPlay(id: itemId), .playAudio, nil)
                    } else {
                        waitForSharing = true
                        shareAudio()
                    }
                }
                .onChange(of: root.gameController.allPlayersReported(for: itemId)) {
                    if waitForSharing && root.gameController.allPlayersReported(for: itemId) {
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
            .disabled(!root.itemController.hasAudio(itemId: itemId))
        }
    }
    
    private var canShare: Bool {
        if appGameStateModel.gameModus == .player {
            let features = sharingFeatureActions.features()
            return features.audioSharing && appGameStateModel.isGameRunning
        } else {
            return appGameStateModel.isGameRunning
        }
    }
    
    private var playIcon: String {
        if appGameStateModel.isGameRunning && !root.gameController.allPlayersReported(for: itemId) {
            return "square.and.arrow.up"
        }
        return isPlaying ? "pause" : "play"
    }
    
    private var isPlaying: Bool {
        root.gameController.isPlayingPlaylist(id: itemId)
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
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId
    }
}
