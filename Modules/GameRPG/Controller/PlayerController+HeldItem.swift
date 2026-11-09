// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Held item answer

extension PlayerController {
    /// The player's answer to a master reveal or store of an item that is a whole package (Table,
    /// Weather): `.ok` when this device holds the item afterwards, otherwise `.ok` asking for
    /// the package. `reveal` and `store` take what the message carries and return whether the
    /// item is held; `didReveal` runs once a reveal left the item held. Updates are the
    /// module's own business and answer nothing. The caller has already refused
    /// acknowledgements.
    func answerHeldItem(
        _ model: GameNetworkModel,
        reveal: () async throws -> Bool,
        didReveal: () -> Void,
        store: () async throws -> Bool
    ) async throws -> GameNetworkModel? {
        switch model.type {
        case .reveal:
            let isHeld = try await reveal()
            if isHeld {
                didReveal()
            }
            return response(for: model, isSuccess: true, requestData: !isHeld)
        case .store:
            let isHeld = try await store()
            return response(for: model, isSuccess: true, requestData: !isHeld)
        case .update:
            return nil
        }
    }
}
