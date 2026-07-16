// @copyright André Trettin

import SwiftUI

public struct GameShareView<Content: View>: View {
    public init(root: any ItemRootControllable, itemId: UUID, @ViewBuilder content: () -> Content = EmptyView.init) {
        self.root = root
        self.itemId = itemId
        self.content = content()
    }

    let root: any ItemRootControllable
    let itemId: UUID
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
        HStack(alignment: .top, spacing: 4) {
            actionBarWithSharing(statuses: statuses)
            if root.viewControllable.sharingViewType == .share, !statuses.isEmpty {
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
                .shareListItem(isActive: canShare, allReported: !statuses.isEmpty && statuses.allSatisfy(\.reported), feedBackEnabled: true, action: shareAction)
        case .custom:
            root.viewControllable.sharingView(for: itemId)
        }
    }

    var canShare: Bool {
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
            .filter(\.show)
            .map { PlayerReportStatus(id: $0.id, name: $0.name, reported: reported.contains($0.id)) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
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
            .animation(accessibilityReduceMotion ? nil : .default, value: statuses.map(\.reported))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(playerReportAccessibilityLabel(for: statuses))
    }

    func playerReportAttributedString(for statuses: [PlayerReportStatus]) -> AttributedString {
        statuses.enumerated().reduce(into: AttributedString()) { line, entry in
            let (index, status) = entry
            if index > 0 {
                line += AttributedString(", ")
            }

            var name = AttributedString(status.name)
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

private struct PlayerReportStatus {
    let id: UUID
    let name: String
    let reported: Bool
}

#Preview {
    GameShareView(root: ItemRootController.previewFixture(), itemId: .fixture1) {
        Label {
            Text(verbatim: "Share item")
        } icon: {
            Image(systemName: "square.and.arrow.up")
        }
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
        Label {
            Text(verbatim: "Share item")
        } icon: {
            Image(systemName: "square.and.arrow.up")
        }
    }
    .padding()
    .environment(fixture.gameState)
    .environment(\.sharingControlActions, SharingControlActions(
        control: {
            [
                SharingControlModel(id: fixture.confirmedPlayer, name: "Arin", show: true),
                SharingControlModel(id: fixture.missingPlayer, name: "Zara", show: true)
            ]
        },
        update: { _ in }
    ))
}
