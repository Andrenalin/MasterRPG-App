// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    SharingActionView(itemId: AudioModel.previewId, showPlayControl: true)
        .padding()
}

#Preview("Master with player report", traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    let gameState = {
        let gameState = AppGameStateModel()
        gameState.gameModus = .master
        gameState.isGameRunning = true
        return gameState
    }()

    SharingActionView(itemId: AudioModel.previewId, showPlayControl: false, showPlayerReport: true)
        .padding()
        .environment(gameState)
        .environment(\.sharingControlActions, SharingControlActions(
            control: {
                [
                    SharingControlModel(id: .fixture2, name: "Arin Doof", show: true),
                    SharingControlModel(id: .fixture3, name: "Zara Mega", show: true)
                ]
            },
            update: { _ in }
        ))
        .onAppear {
            root.gameController.gameModel.setCurrent(players: [.fixture2, .fixture3])
            root.gameController.report(itemId: AudioModel.previewId, for: .fixture2)
        }
}

struct SharingActionView: View, Equatable {
    let itemId: UUID
    let showPlayControl: Bool
    /// True in the item row: the share spans the row and lists the players next to the button.
    /// An inline audio entry shares its row with the track name and keeps the button alone.
    var showPlayerReport: Bool = false

    @Environment(AudioRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingFeatureActions) private var sharingFeatureActions
    @Environment(\.sharingControlActions) private var sharingControlActions
    @Environment(AppGameStateModel.self) private var appGameStateModel

    @State private var waitForSharing: Bool = false
    /// The size of the track's file, shown on the game master's device during the game.
    @State private var fileByteCount: Int?

    var body: some View {
        if appGameStateModel.isGameRunning {
            PlayerReportRow(statuses: playerReportStatuses, transfer: transfer, fileByteCount: fileByteCount)
                .shareListItem(isActive: canShare, allReported: allReported, feedBackEnabled: true, module: .audio, secondActionIcon: playIcon) {
                    shareAudio()
                } secondAction: {
                    if allReported {
                        networkActions?.game(root.gameController.requestPlay(id: itemId), .playAudio, nil)
                    } else {
                        waitForSharing = true
                        shareAudio()
                    }
                }
                .frame(maxWidth: showPlayerReport ? .infinity : nil, alignment: .leading)
                .task(id: showsFileSize) {
                    fileByteCount = showsFileSize ? await root.gameController.fileByteCount(for: itemId) : nil
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
                    await root.playItem(id: itemId)
#if !os(tvOS)
                    root.donatePlay(of: itemId)
#endif
                }
            } label: {
                Image(systemName: "play.rectangle.on.rectangle")
            }
            .selectedRoundButton(title: String(localized: "Play", bundle: .module), module: .audio, isSelected: false)
            .disabled(!root.itemController.hasAudio(itemId: itemId))
        }
    }

    // Computed once per render — avoids calling allPlayersReported repeatedly
    // in shareListItem, secondAction, onChange, and playIcon.
    private var allReported: Bool {
        root.gameController.allPlayersReported(for: itemId)
    }

    /// Only the game master receives the players' acknowledgements, so the list stays empty
    /// on a player device.
    private var playerReportStatuses: [PlayerReportStatus] {
        guard showPlayerReport, appGameStateModel.gameModus == .master else { return [] }
        return root.gameController.playerReportStatuses(for: itemId, controls: sharingControlActions.control?() ?? [])
    }

    /// The download of this track on a player device, shown where the master sees its players.
    private var transfer: ItemTransferStatus? {
        guard showPlayerReport, appGameStateModel.gameModus == .player else { return nil }
        return root.gameController.gameModel.transfers[itemId]
    }

    /// The game master sees the track's file size for the whole game, in the item row.
    private var showsFileSize: Bool {
        showPlayerReport && appGameStateModel.gameModus == .master
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
            let reference = await root.gameController.share(id: itemId)
            if appGameStateModel.gameModus == .master {
                networkActions?.shareId(reference)
            } else {
                // Only the reference: the game exports the file when the master lacks it.
                networkActions?.game(reference, .generic, nil)
            }
        }
    }

    // showPlayControl must be included — omitting it would prevent the non-game
    // play button from appearing/disappearing when the parent changes the value.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId && lhs.showPlayControl == rhs.showPlayControl && lhs.showPlayerReport == rhs.showPlayerReport
    }
}
