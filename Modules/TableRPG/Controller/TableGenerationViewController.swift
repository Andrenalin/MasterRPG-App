// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGenerationViewController: ItemGenerationControllable, Sendable {
    let controller: TableGenerationController
    let sessionStore: TableGenerationSessionStore

    @MainActor
    func generationView(
        itemId: UUID,
        dismissAction: @MainActor @escaping @Sendable () -> Void
    ) -> AnyView {
        AnyView(
            TableGenerationRootView(
                itemId: itemId,
                controller: controller,
                sessionStore: sessionStore,
                dismissAction: dismissAction
            )
        )
    }
}
