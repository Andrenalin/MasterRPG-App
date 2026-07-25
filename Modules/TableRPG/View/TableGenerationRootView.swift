// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGenerationRootView: View {
    init(
        itemId: UUID,
        controller: TableGenerationController,
        sessionStore: TableGenerationSessionStore,
        dismissAction: @MainActor @escaping @Sendable () -> Void
    ) {
        self.controller = controller
        self.sessionStore = sessionStore
        self.dismissAction = dismissAction
        _model = State(initialValue: controller.makeModel(itemId: itemId))
    }

    let controller: TableGenerationController
    let sessionStore: TableGenerationSessionStore
    let dismissAction: @MainActor @Sendable () -> Void

    @State private var model: TableGenerationModel

    @Environment(\.itemGenerationResultAction) private var resultAction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
#if os(iOS)
            Color.black.opacity(0.28)
                .ignoresSafeArea()
#endif

            TableGenerationPanelView(
                model: model,
                controller: controller,
                cancelAction: cancel,
                confirmAction: confirm
            )
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            sessionStore.register(model)
        }
        .onDisappear {
            sessionStore.unregister(model)
        }
    }

    private func cancel() {
        sessionStore.unregister(model)
        dismissAction()
    }

    private func confirm() {
        guard let summary = model.summary else { return }
        resultAction(summary)
        sessionStore.unregister(model)
        withAnimation(reduceMotion ? nil : .smooth) {
            dismissAction()
        }
    }
}

private struct TableGenerationPanelView: View {
    let model: TableGenerationModel
    let controller: TableGenerationController
    let cancelAction: () -> Void
    let confirmAction: () -> Void

    var body: some View {
        VStack {
            TableGenerationHeaderView(
                model: model,
                controller: controller
            )

            Divider()

            ScrollView {
                LazyVStack {
                    ForEach(model.occurrences) { occurrence in
                        TableGenerationOccurrenceView(
                            model: model,
                            occurrence: occurrence,
                            controller: controller
                        )
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)

            if let errorMessage = model.errorMessage {
                Label {
                    Text(errorMessage)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
                .padding(.horizontal)
            }

            Divider()

            TableGenerationFooterView(
                canConfirm: model.canConfirm,
                cancelAction: cancelAction,
                confirmAction: confirmAction
            )
        }
        .frame(maxWidth: 760, maxHeight: 820)
        .themedSurface()
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
#if os(visionOS)
        .glassBackgroundEffect(in: .rect(cornerRadius: 28, style: .continuous))
#else
        .glassEffectAll(.regular, in: .rect(cornerRadius: 28, style: .continuous))
#endif
        .shadow(radius: 24)
    }
}

private struct TableGenerationHeaderView: View {
    let model: TableGenerationModel
    let controller: TableGenerationController

    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingControlActions) private var sharingControlActions
    @Environment(AppGameStateModel.self) private var gameState

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.root.tableName)
                    .font(.title)
                    .bold()
                Text("Choose one result from each generated table.", bundle: .module)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if gameState.isGameRunning,
               gameState.gameModus == .master,
               networkActions != nil,
               model.summary != nil {
                Menu {
                    ForEach(visiblePlayers) { player in
                        Button {
                            shareSummary(to: player.id)
                        } label: {
                            Label {
                                Text("Share with \(player.name)", bundle: .module)
                            } icon: {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                            }
                        }
                    }
                } label: {
                    Label {
                        Text("Share", bundle: .module)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
#if !os(visionOS)
                .buttonStyle(.glass)
#endif
                .disabled(visiblePlayers.isEmpty)
            }

            GlassButton(isProminent: true) {
                withAnimation {
                    controller.autoRoll(model: model)
                }
            } label: {
                Label {
                    Text("Auto Roll", bundle: .module)
                } icon: {
                    Image(systemName: "dice.fill")
                }
            }
            .disabled(model.root.entries.isEmpty)
        }
        .padding()
    }

    private var visiblePlayers: [SharingControlModel] {
        (sharingControlActions.control?() ?? [])
            .filter(\.show)
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func shareSummary(to playerId: UUID) {
        guard let summary = model.summary,
              let data = summary.encodeData()
        else {
            return
        }
        networkActions?.game(
            NetworkCodableDataType(
                id: summary.id,
                type: .generator,
                version: 1,
                data: data
            ),
            .generatedValue,
            playerId
        )
    }
}

private struct TableGenerationOccurrenceView: View {
    let model: TableGenerationModel
    let occurrence: TableGenerationOccurrence
    let controller: TableGenerationController

    @Environment(\.appTheme) private var theme
    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingControlActions) private var sharingControlActions
    @Environment(AppGameStateModel.self) private var gameState

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label {
                    Text(occurrence.tableName)
                        .bold()
                } icon: {
                    Image(systemName: occurrence.diceId == nil ? "list.number" : "dice")
                }

                if let lastRoll = occurrence.lastRoll {
                    Text("Rolled \(lastRoll)", bundle: .module)
                        .foregroundStyle(.secondary)
                }

                if let awaitingPlayerName = occurrence.awaitingPlayerName {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for \(awaitingPlayerName)", bundle: .module)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if canAskPlayerToRoll {
                    Menu {
                        ForEach(visiblePlayers) { player in
                            Button {
                                askPlayerToRoll(player)
                            } label: {
                                Label {
                                    Text("Roll with \(player.name)", bundle: .module)
                                } icon: {
                                    Image(systemName: "person.crop.circle.badge.questionmark")
                                }
                            }
                        }
                    } label: {
                        Label {
                            Text("Player Roll", bundle: .module)
                        } icon: {
                            Image(systemName: "person.2.fill")
                        }
                        .labelStyle(.iconOnly)
                    }
#if !os(visionOS)
                    .buttonStyle(.glass)
#endif
                    .accessibilityLabel(Text("Ask a player to roll \(occurrence.tableName)", bundle: .module))
                }
            }

            ForEach(occurrence.visibleEntries) { entry in
                Button {
                    withAnimation {
                        controller.select(
                            entryId: entry.id,
                            in: occurrence,
                            model: model
                        )
                    }
                } label: {
                    HStack(alignment: .top) {
                        Image(
                            systemName: occurrence.selectedEntryId == entry.id
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                        .foregroundStyle(
                            occurrence.selectedEntryId == entry.id
                                ? theme.tint(for: .table)
                                : .secondary
                        )

                        VStack(alignment: .leading) {
                            Text(entry.name.withoutLink())
                                .bold()
                            if !entry.content.isEmpty {
                                Text(entry.content.withoutLink())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(
                        theme.tint(for: .table).opacity(
                            occurrence.selectedEntryId == entry.id ? 0.16 : 0.05
                        ),
                        in: .rect(cornerRadius: 16, style: .continuous)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(
                    occurrence.selectedEntryId == entry.id
                        ? Text("Selected", bundle: .module)
                        : Text("Not selected", bundle: .module)
                )
                .accessibilityHint(
                    occurrence.selectedEntryId == entry.id
                        ? Text("Deselect to show the other entries", bundle: .module)
                        : Text("Select this generated result", bundle: .module)
                )
            }

            if !occurrence.ignoredCycleNames.isEmpty {
                Label {
                    Text(
                        "Skipped recursive link: \(occurrence.ignoredCycleNames.joined(separator: ", "))",
                        bundle: .module
                    )
                } icon: {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            theme.tint(for: .table).opacity(0.08),
            in: .rect(cornerRadius: 20, style: .continuous)
        )
        .padding(.leading, CGFloat(occurrence.depth) * 16)
    }

    private var visiblePlayers: [SharingControlModel] {
        (sharingControlActions.control?() ?? [])
            .filter(\.show)
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var canAskPlayerToRoll: Bool {
        gameState.isGameRunning
            && gameState.gameModus == .master
            && networkActions != nil
            && !visiblePlayers.isEmpty
            && occurrence.awaitingPlayerId == nil
    }

    private func askPlayerToRoll(_ player: SharingControlModel) {
        occurrence.awaitingPlayerId = player.id
        occurrence.awaitingPlayerName = player.name
        Task {
            do {
                let data = try await controller.gameData(
                    for: occurrence,
                    sessionId: model.id
                )
                networkActions?.game(data, .show, player.id)
            } catch {
                occurrence.awaitingPlayerId = nil
                occurrence.awaitingPlayerName = nil
                model.errorMessage = String(
                    localized: "Could not share the dice with \(player.name).",
                    bundle: .module
                )
            }
        }
    }
}

private struct TableGenerationFooterView: View {
    let canConfirm: Bool
    let cancelAction: () -> Void
    let confirmAction: () -> Void

    var body: some View {
        GlassEffectContainerAll {
            HStack {
                GlassButton(action: cancelAction) {
                    Label {
                        Text("Cancel", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark")
                    }
                }

                Spacer()

                GlassButton(isProminent: true, action: confirmAction) {
                    Label {
                        Text("Confirm", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                }
                .disabled(!canConfirm)
            }
        }
        .padding()
    }
}
