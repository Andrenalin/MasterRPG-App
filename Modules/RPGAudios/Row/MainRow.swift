// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MainRow: View {
    let model: AudioModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel
    
    @Environment(AudioRoot.self) private var root
    
    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingFeatureActions) private var sharingFeatureActions
    @Environment(\.showGame) private var showGame
    
    @State private var waitForSharing: Bool = false

    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheItemListModel, name: \.name, tags: \.tags, description: \.description, isSelected: isSelected, tagAdds: {
            CategoryItemRow(category: model.category)
        }, actionBar: {
            EmptyView()
                .shareListItem(isActive: canShareSpace, allReported: root.gameController.allPlayersReported(for: model.id), feedBackEnabled: true, secondActionIcon: playIcon) {
                    shareAudio()
                } secondAction: {
                    if root.gameController.allPlayersReported(for: model.id) {
                        networkActions?.game(root.gameController.requestPlay(id: model.id), .playAudio)
                    } else {
                        waitForSharing = true
                        shareAudio()
                    }
                }
        })
        .onChange(of: root.gameController.allPlayersReported(for: model.id)) {
            if waitForSharing && root.gameController.allPlayersReported(for: model.id) {
                waitForSharing = false
                networkActions?.game(root.gameController.requestPlay(id: model.id), .playAudio)
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
        if showGame && !root.gameController.allPlayersReported(for: model.id) {
            return "square.and.arrow.up"
        }
        return isPlaying ? "pause" : "play"
    }
    
    private var isPlaying: Bool {
        root.gameController.isPlayingPlaylist(id: model.id)
    }

    private func shareAudio() {
        Task {
            if gameModus == .master {
                await networkActions?.shareId(root.gameController.share(id: model.id))
            } else {
                if let result = try? await root.gameController.createGameData(for: model.id) {
                    networkActions?.game(result, .generic)
                }
            }
        }
    }
}

#Preview {
    MainRow(model: .preview, isSelected: true, cacheItemListModel: .preview)
        .environment(AudioRoot.preview)

}
