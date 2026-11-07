// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Photo Messages

extension MasterController {
    func handlePhoto(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        try await handleFileBackedMessage(model, access: root.photoRoot.fileBackedAccess)
    }
}
