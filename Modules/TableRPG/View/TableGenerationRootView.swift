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

            TableGenerationResultView(model: model)

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
                Text("Choose the results for each generated table.", bundle: .module)
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

private struct TableGenerationResultView: View {
    let model: TableGenerationModel

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(theme.tint(for: .table))

            VStack(alignment: .leading) {
                Text("Outcome", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let summary = model.summary {
                    Text(summary.value)
                        .bold()
                } else {
                    Text(
                        "Choose or roll every table to see the outcome.",
                        bundle: .module
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.tint(for: .table).opacity(model.summary == nil ? 0.08 : 0.18),
            in: .rect(cornerRadius: 20, style: .continuous)
        )
        //.padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

private struct TableGenerationOccurrenceView: View {
    let model: TableGenerationModel
    let occurrence: TableGenerationOccurrence
    let controller: TableGenerationController

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading) {
            TableGenerationOccurrenceHeaderView(
                model: model,
                occurrence: occurrence,
                controller: controller
            )

            if occurrence.allowsMultipleSelection {
                Text(
                    "Select every entry you need. Hide any unwanted entries.",
                    bundle: .module
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach(occurrence.visibleEntries) { entry in
                TableGenerationEntryRow(
                    entry: entry,
                    occurrence: occurrence,
                    model: model,
                    controller: controller
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
}

private struct TableGenerationOccurrenceHeaderView: View {
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
        (sharingControlActions.control?() ?? [])
            .filter(\.show)
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
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

private struct TableGenerationEntryRow: View {
    init(
        entry: TableGenerationEntry,
        occurrence: TableGenerationOccurrence,
        model: TableGenerationModel,
        controller: TableGenerationController
    ) {
        self.entry = entry
        self.occurrence = occurrence
        self.model = model
        self.controller = controller
        _contentModel = State(
            initialValue: LinkHighlightTextModel(
                linkControllable: nil,
                text: entry.content
            )
        )
    }

    let entry: TableGenerationEntry
    let occurrence: TableGenerationOccurrence
    let model: TableGenerationModel
    let controller: TableGenerationController

    @State private var contentModel: LinkHighlightTextModel
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth) {
                    controller.select(
                        entryId: entry.id,
                        in: occurrence,
                        model: model
                    )
                }
            } label: {
                HStack(alignment: .top) {
                    Image(
                        systemName: isSelected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        isSelected
                            ? theme.tint(for: .table)
                            : .secondary
                    )

                    VStack(alignment: .leading) {
                        Text(entry.name.withoutLink())
                            .bold()
                        if !entry.content.isEmpty {
                            LinkHighlightTextView(
                                model: contentModel,
                                allowsLinkInteraction: false
                            )
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                isSelected
                    ? Text("Selected", bundle: .module)
                    : Text("Not selected", bundle: .module)
            )
            .accessibilityHint(selectionHint)

            if occurrence.allowsMultipleSelection, !isSelected {
                GlassButton {
                    withAnimation(reduceMotion ? nil : .smooth) {
                        controller.hide(
                            entryId: entry.id,
                            in: occurrence,
                            model: model
                        )
                    }
                } label: {
                    Label {
                        Text("Hide", bundle: .module)
                    } icon: {
                        Image(systemName: "eye.slash")
                    }
                    .labelStyle(.iconOnly)
                }
                .disabled(
                    !controller.canHide(
                        entryId: entry.id,
                        in: occurrence
                    )
                )
                .accessibilityHint(
                    Text(
                        "Exclude this entry from the generated result",
                        bundle: .module
                    )
                )
            }
        }
        .padding()
        .background(
            theme.tint(for: .table).opacity(isSelected ? 0.16 : 0.05),
            in: .rect(cornerRadius: 16, style: .continuous)
        )
    }

    private var isSelected: Bool {
        occurrence.selectedEntryIds.contains(entry.id)
    }

    private var selectionHint: Text {
        if isSelected {
            if occurrence.allowsMultipleSelection {
                Text("Deselect this generated result", bundle: .module)
            } else {
                Text("Deselect to show the other entries", bundle: .module)
            }
        } else {
            Text("Select this generated result", bundle: .module)
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

private struct TableGenerationPreviewContainer: View {
    let itemId: UUID

    @Environment(TableRootModel.self) private var root

    var body: some View {
        TableGenerationRootView(
            itemId: itemId,
            controller: root.generationController,
            sessionStore: root.generationSessionStore,
            dismissAction: {}
        )
    }
}

#Preview("Dice Table", traits: .mockData) {
    TableGenerationPreviewContainer(itemId: TableModel.previewId)
        .preferredColorScheme(.dark)
}

#Preview("List Table", traits: .mockData) {
    TableGenerationPreviewContainer(itemId: TableModel.previewShortListId)
        .preferredColorScheme(.dark)
}

#Preview("Empty Table", traits: .mockData) {
    TableGenerationPreviewContainer(itemId: TableModel.previewEmptyId)
        .preferredColorScheme(.dark)
}
