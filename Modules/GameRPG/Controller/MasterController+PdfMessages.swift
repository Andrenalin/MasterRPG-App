// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Pdf Messages

extension MasterController {
    func handlePdf(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        try await handleFileBackedMessage(model, access: root.pdfRoot.fileBackedAccess)
    }
}
