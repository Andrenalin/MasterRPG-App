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
