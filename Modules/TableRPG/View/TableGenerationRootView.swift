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
    @Environment(\.networkActions) private var networkActions
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
                closeAction: close,
                saveAction: save,
                sendAction: send
            )
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            sessionStore.register(model)
        }
        .onDisappear {
            // Safety net for any dismissal path that bypasses close()/save()/
            // send(to:) below — the session is in-memory only, so this is
            // cheap even when it's a no-op.
            controller.discardOutcomeSession(model: model)
            sessionStore.unregister(model)
        }
    }

    /// Discards the session without saving anything.
    private func close() {
        controller.discardOutcomeSession(model: model)
        sessionStore.unregister(model)
        dismissAction()
    }

    /// Adds the generated outcome as a new value to the character.
    private func save() {
        // Save/Send now only ever appears while the sheet editor is open —
        // flatten its current entries into `editedOutcome` first, so
        // `model.summary` reflects what's on screen even if the user never
        // explicitly toggled back to "Done" before confirming.
        controller.endEditingOutcomeSheet(model: model)
        guard let summary = model.summary else { return }
        resultAction(summary)
        controller.discardOutcomeSession(model: model)
        sessionStore.unregister(model)
        withAnimation(reduceMotion ? nil : .smooth) {
            dismissAction()
        }
    }

    /// Sends the generated outcome to a player (or every visible player)
    /// over the active game session.
    private func send(to playerId: UUID?) {
        controller.endEditingOutcomeSheet(model: model)
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
        controller.discardOutcomeSession(model: model)
        sessionStore.unregister(model)
        withAnimation(reduceMotion ? nil : .smooth) {
            dismissAction()
        }
    }
}

#Preview("Dice table", traits: .mockData) {
    TableGenerationRootView(
        itemId: TableModel.previewId,
        controller: .preview,
        sessionStore: .preview,
        dismissAction: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("List table", traits: .mockData) {
    TableGenerationRootView(
        itemId: TableModel.previewShortListId,
        controller: .preview,
        sessionStore: .preview,
        dismissAction: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Empty table", traits: .mockData) {
    TableGenerationRootView(
        itemId: TableModel.previewEmptyId,
        controller: .preview,
        sessionStore: .preview,
        dismissAction: {}
    )
    .preferredColorScheme(.dark)
}
