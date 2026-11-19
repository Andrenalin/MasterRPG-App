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
        self.itemId = itemId
        self.controller = controller
        self.sessionStore = sessionStore
        self.dismissAction = dismissAction
    }

    let itemId: UUID
    let controller: TableGenerationController
    let sessionStore: TableGenerationSessionStore
    let dismissAction: @MainActor @Sendable () -> Void

    /// Built once per view identity (the call site keys the view by `itemId`): seeding `@State`
    /// in `init` ran `makeModel` — which walks the whole nested table tree — on every parent
    /// re-render and threw the result away. See CODE_AUDIT_18 §8.5.
    @State private var modelStore = LazyGenerationModel()
    private var model: TableGenerationModel {
        modelStore.model { controller.makeModel(itemId: itemId) }
    }
    @State private var createdValueItemId: UUID?
    @State private var createdValueName = ""
    @State private var isShowingCreatedAlert = false

    @Environment(\.networkActions) private var networkActions
    @Environment(\.routeActions) private var routeActions

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
        .alert(
            Text("Created item \(createdValueName)", bundle: .module),
            isPresented: $isShowingCreatedAlert
        ) {
            Button {
                finishAfterCreatedAlert(showItem: true)
            } label: {
                Text("Yes", bundle: .module)
            }
            Button(role: .cancel) {
                finishAfterCreatedAlert(showItem: false)
            } label: {
                Text("No", bundle: .module)
            }
        } message: {
            Text("Do you want to go to the item?", bundle: .module)
        }
    }

    /// The one closing path every exit uses — Cancel, Save (both the
    /// failure case and after the post-save alert), and Send — so the panel
    /// always closes the same way no matter how it's left. Safe to call
    /// even if the session was already discarded (`discardOutcomeSession`
    /// is a no-op then).
    private func closeSession() {
        controller.discardOutcomeSession(model: model)
        sessionStore.unregister(model)
        dismissAction()
    }

    /// Discards the session without saving anything.
    private func close() {
        closeSession()
    }

    /// Adds the generated outcome as a new value on the character, built
    /// directly from the outcome's edited sheet (name/description/entries)
    /// via `TableGenerationController.addOutcomeToCharacter(session:)` —
    /// only ever tappable while the sheet editor is open, so a session is
    /// always present here. Confirms success with an alert offering to jump
    /// straight to the new value.
    private func save() {
        guard let session = model.outcomeEditingSession else { return }
        // The sheet's own root header can't be edited in place — its first
        // entry stands in as the editable "root" instead (see
        // `TableGenerationController.beginEditingOutcomeSheet(model:)`), and
        // is what `addOutcomeToCharacter(session:)` reads as the new
        // value's name.
        let itemName = session.currentModel?.entries.first?.name ?? ""
        Task {
            let itemId = await controller.addOutcomeToCharacter(session: session)
            guard let itemId else {
                // Keep the panel and the edited sheet open: closing here threw the outcome away
                // without a word. See CODE_AUDIT_26 §5.135.
                model.errorMessage = String(
                    localized: "Could not save the result as a value.",
                    bundle: .module
                )
                return
            }
            controller.discardOutcomeSession(model: model)
            sessionStore.unregister(model)
            createdValueItemId = itemId
            createdValueName = itemName
            isShowingCreatedAlert = true
        }
    }

    private func finishAfterCreatedAlert(showItem: Bool) {
        if showItem, let createdValueItemId {
            routeActions.routePage(.value, createdValueItemId, nil)
        }
        closeSession()
    }

    /// Sends the generated outcome to a player (or every visible player) as
    /// a new Character value — the same wrapper/nested-rows shape `save()`
    /// above hands to `addItem(sheet:)` locally, just carried over the
    /// active game session so the receiving `PlayerController` can call the
    /// identical function on its own device (see
    /// `PlayerController+Value.handleAddItem(_:)`).
    private func send(to playerId: UUID?) {
        controller.endEditingOutcomeSheet(model: model)
        guard let session = model.outcomeEditingSession,
              let payload = SheetItemTransfer(sheet: session.sheetRootModel.sheetModel),
              let data = payload.encodeData()
        else {
            model.errorMessage = String(
                localized: "Could not send the result to the player.",
                bundle: .module
            )
            return
        }
        networkActions?.game(
            NetworkCodableDataType(
                id: payload.id,
                type: .value,
                version: 1,
                data: data
            ),
            .addItem,
            playerId
        )
        closeSession()
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
