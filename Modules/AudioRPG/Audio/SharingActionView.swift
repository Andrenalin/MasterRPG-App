// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SharingActionView: View {
    let itemId: UUID
    
    @Environment(AudioRootModel.self) private var root
    
    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingFeatureActions) private var sharingFeatureActions
    @Environment(\.showGame) private var showGame
    
    @State private var waitForSharing: Bool = false
    
    var body: some View {
        EmptyView()
            .shareListItem(isActive: canShareSpace, allReported: root.gameController.allPlayersReported(for: itemId), feedBackEnabled: true, secondActionIcon: playIcon) {
                shareAudio()
            } secondAction: {
                if root.gameController.allPlayersReported(for: itemId) {
                    networkActions?.game(root.gameController.requestPlay(id: itemId), .playAudio)
                } else {
                    waitForSharing = true
                    shareAudio()
                }
            }
            .onChange(of: root.gameController.allPlayersReported(for: itemId)) {
                if waitForSharing && root.gameController.allPlayersReported(for: itemId) {
                    waitForSharing = false
                    networkActions?.game(root.gameController.requestPlay(id: itemId), .playAudio)
                }
            }
    }
    
    private var canShareSpace: Bool {
        if gameModus == .player {
            let features = sharingFeatureActions.features()
            return features.audioSharing && showGame
        } else {
            return showGame
        }
    }
    
    private var playIcon: String {
        if showGame && !root.gameController.allPlayersReported(for: itemId) {
            return "square.and.arrow.up"
        }
        return isPlaying ? "pause" : "play"
    }
    
    private var isPlaying: Bool {
        root.gameController.isPlayingPlaylist(id: itemId)
    }
    
    private func shareAudio() {
        Task {
            if gameModus == .master {
                await networkActions?.shareId(root.gameController.share(id: itemId))
            } else {
                if let result = try? await root.gameController.createGameData(for: itemId) {
                    networkActions?.game(result, .generic)
                }
            }
        }
    }
}

#Preview {
    MainRow(model: .preview, isSelected: true, cacheItemListModel: .preview)
        .environment(AudioRootModel.preview)
    
}
