// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGenerationOccurrenceHeaderView: View {
    let model: TableGenerationModel
    let occurrence: TableGenerationOccurrence
    let controller: TableGenerationController

    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingControlActions) private var sharingControlActions
    @Environment(AppGameStateModel.self) private var gameState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            Label {
                Text(occurrence.tableName)
                    .bold()
            } icon: {
                Image(
                    systemName: occurrence.diceId == nil
                        ? "list.number"
                        : "dice"
                )
            }

            if let lastRoll = occurrence.lastRoll {
                Text("Rolled \(lastRoll)", bundle: .module)
                    .foregroundStyle(.secondary)
            }

            if occurrence.isAwaitingPlayerRoll,
               let awaitingPlayerName = occurrence.awaitingPlayerName {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for \(awaitingPlayerName)", bundle: .module)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    withAnimation(reduceMotion ? nil : .smooth) {
                        _ = controller.roll(
                            occurrence: occurrence,
                            model: model
                        )
                    }
                } label: {
                    Label {
                        Text("Roll", bundle: .module)
                    } icon: {
                        Image(systemName: "dice.fill")
                    }
                }
                .disabled(occurrence.entries.isEmpty)

                if canShareDice {
                    Divider()

                    ForEach(visiblePlayers) { player in
                        Button {
                            shareDice(
                                to: player.id,
                                playerName: player.name
                            )
                        } label: {
                            Label {
                                Text(
                                    "Share to \(player.name)",
                                    bundle: .module
                                )
                            } icon: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .disabled(occurrence.isAwaitingPlayerRoll)
                    }

                    Button {
                        shareDice(
                            to: nil,
                            playerName: String(
                                localized: "All Players",
                                bundle: .module
                            )
                        )
                    } label: {
                        Label {
                            Text("Share to all", bundle: .module)
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(occurrence.isAwaitingPlayerRoll)
                }

                if occurrence.hasDecisions {
                    Divider()

                    Button(role: .destructive) {
                        withAnimation(reduceMotion ? nil : .smooth) {
                            controller.reset(
                                occurrence: occurrence,
                                model: model
                            )
                        }
                    } label: {
                        Label {
                            Text("Reset", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                }
            } label: {
                Label {
                    Text("Roll or Share Dice", bundle: .module)
                } icon: {
                    Image(systemName: "dice.fill")
                }
                .labelStyle(.iconOnly)
            }
#if !os(visionOS)
            .buttonStyle(.glass)
#endif
            .accessibilityLabel(
                Text(
                    "Roll or share dice for \(occurrence.tableName)",
                    bundle: .module
                )
            )
        }
    }

    private var visiblePlayers: [SharingControlModel] {
        (sharingControlActions.control?() ?? []).visibleSortedByName
    }

    private var canShareDice: Bool {
        gameState.isGameRunning
            && gameState.gameModus == .master
            && networkActions != nil
            && !visiblePlayers.isEmpty
    }

    private func shareDice(
        to playerId: UUID?,
        playerName: String
    ) {
        occurrence.isAwaitingPlayerRoll = true
        occurrence.awaitingPlayerId = playerId
        occurrence.awaitingPlayerName = playerName
        Task {
            do {
                let data = try await controller.gameData(
                    for: occurrence,
                    sessionId: model.id
                )
                networkActions?.game(data, .show, playerId)
            } catch {
                occurrence.isAwaitingPlayerRoll = false
                occurrence.awaitingPlayerId = nil
                occurrence.awaitingPlayerName = nil
                model.errorMessage = String(
                    localized: "Could not share the dice with \(playerName).",
                    bundle: .module
                )
            }
        }
    }
}

#Preview("Dice table", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.preview
    TableGenerationOccurrenceHeaderView(
        model: model,
        occurrence: model.root,
        controller: .preview
    )
    .padding()
}

#Preview("Rolled", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.previewRolled
    TableGenerationOccurrenceHeaderView(
        model: model,
        occurrence: model.root,
        controller: .preview
    )
    .padding()
}
