// @copyright André Trettin

import CoreRPG
import Foundation

extension PlayerController {
    func handlePdf(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        // PDFs come from the game master only; a player shows one through the master.
        guard !model.isAcknowledgement, model.sender.isMaster else { return nil }

        return try await handleFileBackedMessage(
            model,
            access: root.pdfRoot.fileBackedAccess,
            didReveal: { _ in gameModel.setGameUpdateType(.pdf) }
        )
    }
}
