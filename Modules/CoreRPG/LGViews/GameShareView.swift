// @copyright André Trettin

import SwiftUI

public struct GameShareView<Content: View>: View {
    public init(root: any ItemRootControllable, itemId: UUID, isShareable: Bool = true, usesModuleSharingView: Bool = true, @ViewBuilder content: () -> Content = EmptyView.init) {
        self.root = root
        self.itemId = itemId
        self.isShareable = isShareable
        self.usesModuleSharingView = usesModuleSharingView
        self.content = content()
    }

    let root: any ItemRootControllable
    let itemId: UUID
    /// False suppresses the share affordance regardless of `canShare`'s own game-state
    /// logic — e.g. a Photo row embedded inside a Map entry, which shares only through
    /// the Map itself. See CODE_AUDIT: Photo-in-Map share toggle.
    let isShareable: Bool
    /// False renders the standard share button even where the module returns a custom sharing
    /// view. That view builds on it (e.g. Table adds a generate button) and would otherwise
    /// replace itself.
    let usesModuleSharingView: Bool
    let content: Content

    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingFeatureActions) private var sharingFeatureActions
    @Environment(\.sharingControlActions) private var sharingControlActions

    public var body: some View {
        // Computed once per render — avoids re-deriving the same list for the
        // button's allReported state and the row below it.
        let statuses = playerReportStatuses
        if showsReportBesideButton {
            PlayerReportRow(statuses: statuses, transfer: transfer)
                .shareListItem(isActive: canShare, allReported: allReported(statuses), feedBackEnabled: true, module: root.configurable.module, action: shareAction)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            actionBarWithSharing(statuses: statuses)
                .overlay(alignment: .topTrailing) {
                    // Only where this view offers sharing: a Photo embedded in a Map shares through
                    // the Map, so its report row showed player names for a share it doesn't offer.
                    // See CODE_AUDIT_19 §8.1.
                    if isShareable, sharingType == .share, !replacesShareWithGenerate, !statuses.isEmpty || transfer != nil {
                        PlayerReportRow(statuses: statuses, transfer: transfer)
                            // Informational only: a tap on a control in the content's top-trailing
                            // corner must reach that control, not this caption.
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    /// A share without content — an item row — is the button alone, so the report overlay
    /// landed on the button itself. There the players follow the button and the share spans
    /// the row, the layout of the Music row's `SharingActionView`.
    private var showsReportBesideButton: Bool {
        Content.self == EmptyView.self && isShareable && sharingType == .share
    }

    /// The game master goes by the players it lists. A player device lists no names: its
    /// button follows its own game model, where it can share itself (Photo, 3D model).
    private func allReported(_ statuses: [PlayerReportStatus]) -> Bool {
        if appGameStateModel.gameModus == .player {
            return canShare && root.gameControllable.isSharedWithEveryone(itemId)
        }
        return !statuses.isEmpty && statuses.allSatisfy(\.reported)
    }

    @ViewBuilder
    private func actionBarWithSharing(statuses: [PlayerReportStatus]) -> some View {
        switch sharingType {
        case .none:
            content
        case .share where replacesShareWithGenerate:
            HStack(spacing: 8) {
                if canGenerate {
                    ItemGenerateButton(root: root, itemId: itemId)
                }
                content
                    .contentShape(.rect)
            }
        case .share:
            content
                .shareListItem(isActive: canShare, allReported: allReported(statuses), feedBackEnabled: true, module: root.configurable.module, action: shareAction)
        case .custom:
            root.viewControllable.sharingView(for: itemId)
        }
    }

    /// A module's custom sharing view replaces the share button of an item row only. Content
    /// around the button (a sheet's name row) keeps the standard share, which the custom view
    /// would otherwise drop together with that content.
    private var sharingType: SharingViewType {
        let type = root.viewControllable.sharingViewType
        guard type == .custom else { return type }
        return usesModuleSharingView && Content.self == EmptyView.self ? .custom : .share
    }

    /// A sheet header of an item whose module generates (Table) offers Generate instead of
    /// Share: a table is shared from its row, the sheet generates from it.
    private var replacesShareWithGenerate: Bool {
        Content.self != EmptyView.self && root.generationControllable != nil
    }

    /// The game master generates during a game, like the share button's own condition.
    private var canGenerate: Bool {
        isShareable && appGameStateModel.gameModus != .player && appGameStateModel.isGameRunning
    }

    var canShare: Bool {
        guard isShareable else { return false }
        if appGameStateModel.gameModus == .player {
            let features = sharingFeatureActions.features()
            switch root.configurable.module {
            case .photo:
                return features.photoSharing && appGameStateModel.isGameRunning
            case .audio:
                return features.audioSharing && appGameStateModel.isGameRunning
            case .space:
                return features.spaceSharing && appGameStateModel.isGameRunning
            default:
                return false
            }
        } else {
            return appGameStateModel.isGameRunning
        }
    }

    func shareAction() {
        Task {
            if appGameStateModel.gameModus == .master {
                await networkActions?.shareId(root.gameControllable.share(id: itemId))
            } else {
                if let result = try? await root.gameControllable.createGameData(for: itemId) {
                    networkActions?.game(result, .generic, nil)
                }
            }
        }
    }
}

// MARK: - Player report status

private extension GameShareView {
    /// The download of this item's file on a player device; the game master has none.
    var transfer: ItemTransferStatus? {
        guard appGameStateModel.gameModus == .player else { return nil }
        return root.gameControllable.gameModel.transfers[itemId]
    }

    /// Only the game master receives per-player acknowledgements for a share, so
    /// this stays empty (and the row never appears) anywhere else. A player device
    /// shows the outcome on its button alone, see `allReported(_:)`.
    var playerReportStatuses: [PlayerReportStatus] {
        guard appGameStateModel.gameModus == .master else { return [] }
        let reported = Set(root.gameControllable.gameModel.playerReport(for: itemId))
        return (sharingControlActions.control?() ?? [])
            .playerReportStatuses { reported.contains($0) }
    }
}

#Preview {
    GameShareView(root: ItemRootController.previewFixture(), itemId: .fixture1) {
        Text(verbatim: "Share item")
            .padding(64)
    }
    .environment(AppGameStateModel())
}

#Preview("Master with player report status") {
    let fixture = {
        let itemId = UUID.fixture1
        let confirmedPlayer = UUID.fixture2
        let missingPlayer = UUID.fixture3
        let fixture = FakeItemRootControllerFixture(sharingViewType: .share)
        let root = fixture.root
        root.gameControllable.report(itemId: itemId, for: confirmedPlayer)

        let gameState = AppGameStateModel()
        gameState.gameModus = .master
        gameState.isGameRunning = true

        return (
            itemId: itemId,
            confirmedPlayer: confirmedPlayer,
            missingPlayer: missingPlayer,
            root: root,
            gameState: gameState
        )
    }()

    GameShareView(root: fixture.root, itemId: fixture.itemId) {
        ZStack {
            Color.yellow.opacity(0.2)
                .frame(width: 160, height: 60)
            Text(verbatim: "Some content")
                .padding()
        }
    }
    .padding()
    .environment(fixture.gameState)
    .environment(\.sharingControlActions, SharingControlActions(
        control: {
            [
                SharingControlModel(id: fixture.confirmedPlayer, name: "Arin Doof", show: true),
                SharingControlModel(id: fixture.missingPlayer, name: "Zara Mega", show: true)
            ]
        },
        update: { _ in }
    ))
}

#Preview("Master item row with player report status") {
    let fixture = FakeItemRootControllerFixture(sharingViewType: .share)
    let gameState = {
        let gameState = AppGameStateModel()
        gameState.gameModus = .master
        gameState.isGameRunning = true
        return gameState
    }()

    GameShareView(root: fixture.root, itemId: .fixture1)
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
            fixture.root.gameControllable.report(itemId: .fixture1, for: .fixture2)
        }
}
