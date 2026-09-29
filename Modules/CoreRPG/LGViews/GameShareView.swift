// @copyright André Trettin

import SwiftUI

public struct GameShareView<Content: View>: View {
    public init(root: any ItemRootControllable, itemId: UUID, isShareable: Bool = true, @ViewBuilder content: () -> Content = EmptyView.init) {
        self.root = root
        self.itemId = itemId
        self.isShareable = isShareable
        self.content = content()
    }
    
    let root: any ItemRootControllable
    let itemId: UUID
    /// False suppresses the share affordance regardless of `canShare`'s own game-state
    /// logic — e.g. a Photo row embedded inside a Map entry, which shares only through
    /// the Map itself. See CODE_AUDIT: Photo-in-Map share toggle.
    let isShareable: Bool
    let content: Content
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingFeatureActions) private var sharingFeatureActions
    @Environment(\.sharingControlActions) private var sharingControlActions
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    
    public var body: some View {
        // Computed once per render — avoids re-deriving the same list for the
        // button's allReported state and the row below it.
        let statuses = playerReportStatuses
        actionBarWithSharing(statuses: statuses)
            .overlay(alignment: .topTrailing) {
                // Only where this view offers sharing: a Photo embedded in a Map shares through
                // the Map, so its report row showed player names for a share it doesn't offer.
                // See CODE_AUDIT_19 §8.1.
                if isShareable, root.viewControllable.sharingViewType == .share, !statuses.isEmpty {
                    playerReportRow(for: statuses)
                }
            }
    }
    
    @ViewBuilder
    private func actionBarWithSharing(statuses: [PlayerReportStatus]) -> some View {
        switch root.viewControllable.sharingViewType {
        case .none:
            content
        case .share:
            content
                .shareListItem(isActive: canShare, allReported: !statuses.isEmpty && statuses.allSatisfy(\.reported), feedBackEnabled: true, module: root.configurable.module, action: shareAction)
        case .custom:
            root.viewControllable.sharingView(for: itemId)
        }
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
    /// Only the game master receives per-player acknowledgements for a share —
    /// a player device has no visibility into its siblings' delivery state, so
    /// this stays empty (and the row never appears) anywhere else.
    var playerReportStatuses: [PlayerReportStatus] {
        guard appGameStateModel.gameModus == .master else { return [] }
        let reported = Set(root.gameControllable.gameModel.playerReport(for: itemId))
        return (sharingControlActions.control?() ?? [])
            .visibleSortedByName
            .map { PlayerReportStatus(id: $0.id, name: $0.name, reported: reported.contains($0.id)) }
    }
    
    func playerReportRow(for statuses: [PlayerReportStatus]) -> some View {
        HStack(spacing: 4) {
            Text(playerReportAttributedString(for: statuses))
            if statuses.allSatisfy(\.reported) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .font(.caption)
        // Drawn over the photo or text below it: a material background keeps it legible.
        // See CODE_AUDIT_19 §8.1.
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: .capsule)
        .animation(accessibilityReduceMotion ? nil : .default, value: statuses.map(\.reported))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(playerReportAccessibilityLabel(for: statuses))
    }

    func playerReportAttributedString(status: PlayerReportStatus) -> AttributedString {
        var playerName = status.name
        if let firstName = status.name.split(separator: " ").first {
            playerName = String(firstName)
        }

        var name = AttributedString(playerName)
        if status.reported {
            name.font = .caption.bold()
        } else {
            name.foregroundColor = .secondary
        }
        return name
    }
    
    func playerReportAttributedString(for statuses: [PlayerReportStatus]) -> AttributedString {
        statuses.enumerated().reduce(into: AttributedString()) { line, entry in
            let (index, status) = entry
            if index > 0 {
                line += AttributedString(", ")
            }
            
            var playerName = status.name
            if let firstName = status.name.split(separator: " ").first {
                playerName = String(firstName)
            }

            var name = AttributedString(playerName)
            if status.reported {
                name.font = .caption.bold()
            } else {
                name.foregroundColor = .secondary
            }
            line += name
        }
    }
    
    func playerReportAccessibilityLabel(for statuses: [PlayerReportStatus]) -> Text {
        let reportedNames = statuses.filter(\.reported).map(\.name).joined(separator: ", ")
        let missingNames = statuses.filter { !$0.reported }.map(\.name).joined(separator: ", ")
        if missingNames.isEmpty {
            return Text("All players confirmed: \(reportedNames)", bundle: .module)
        }
        if reportedNames.isEmpty {
            return Text("Waiting on: \(missingNames)", bundle: .module)
        }
        return Text("Confirmed: \(reportedNames). Waiting on: \(missingNames)", bundle: .module)
    }
}

private struct PlayerReportStatus: Identifiable {
    let id: UUID
    let name: String
    let reported: Bool
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
