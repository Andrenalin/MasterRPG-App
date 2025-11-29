// @copyright André Trettin

import CoreRPG
import SwiftUI

struct EntryRow: View {
    let item: ItemRowTreeModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel
    
    @Environment(AudioRootModel.self) private var root
    @Environment(ListModel.self) private var itemListModel

    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingFeatureActions) private var sharingFeatureActions
    @Environment(\.showGame) private var showGame

    @State private var waitForSharing: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            quickActionView
        }
    }

    private var audioId: UUID {
        item.model.entryId ?? item.model.itemId
    }

    private var isPlaying: Bool {
        root.gameController.isPlayingPlaylist(id: audioId)
    }
    
    private var quickActionView: some View {
        HStack {
            Button {
                if showGame {
                    if root.gameController.allPlayersReported(for: audioId) {
                        networkActions?.game(root.gameController.requestPlay(id: audioId), .playAudio)
                    } else {
                        waitForSharing = true
                        shareAudio()
                    }
                } else {
                    root.gameController.play(id: audioId, shouldPlay: false)
                }
            } label: {
                Image(systemName: playIcon)
                    .imageScale(.large)
                    .symbolRenderingMode(.palette)
                    .contentTransition(.symbolEffect(.replace.offUp))
            }
            .contentShape(Rectangle())
            .buttonStyle(.bordered)
            .disabled(shareAndPlayAudio)

            LinkHighlightTextView(model: linkTextModel)
                .frame(maxWidth: .infinity, alignment: .leading)
#if !os(tvOS)
                .badge(root.itemController.itemOrEmpty(for: audioId).entries.count)
#endif

#if os(tvOS)
            Text("\(root.itemController.itemOrEmpty(for: audioId).entries.count)")
#endif
        }
        .shareListItem(isActive: gameModus == .master && showGame, allReported: root.gameController.allPlayersReported(for: audioId), feedBackEnabled: true) {
            shareAudio()
        }
        .onChange(of: root.gameController.allPlayersReported(for: audioId)) {
            if waitForSharing && root.gameController.allPlayersReported(for: audioId) {
                waitForSharing = false
                networkActions?.game(root.gameController.requestPlay(id: audioId), .playAudio)
            }
        }
    }
    
    private var shareAndPlayAudio: Bool {
        if gameModus == .player {
            let features = sharingFeatureActions.features()
            return !features.audioSharing || waitForSharing
        } else {
            return waitForSharing
        }
    }

    private func shareAudio() {
        Task {
            if gameModus == .master {
                await networkActions?.shareId(root.gameController.share(id: audioId))
            } else {
                if let result = try? await root.gameController.createGameData(for: audioId) {
                    networkActions?.game(result, .generic)
                }
            }
        }
    }
    
    private var playIcon: String {
        if showGame && !root.gameController.allPlayersReported(for: audioId) {
            return "square.and.arrow.up"
        }
        return isPlaying ? "pause" : "play"
    }
    
    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: audioId) else {
            return updateLinkText()
        }
        return linkModel
    }
    
    @discardableResult
    private func updateLinkText() -> LinkHighlightTextModel {
        let entryText = root.itemController.itemOrEmpty(for: audioId).name
        if let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: audioId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: root.rootControllable.linkControllable, text: entryText, highlightedText: itemListModel.searchText, toggler: nil, shareResult: nil, editAction: nil)
            cacheItemListModel.setItemLink(cacheType: .row, itemId: audioId, linkModel: linkModel)
            return linkModel
        }
    }
}

#Preview {
    EntryRow(item: .preview, isSelected: false, cacheItemListModel: .preview)
        .environment(AudioRootModel.preview)
        .environment(\.showGame, true)
}
