// @copyright André Trettin

import CoreRPG
import Foundation
import WeatherRPG

// MARK: - Weather Messages

extension MasterController {
    func handleWeather(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            let baseline = await root.weatherRoot.weatherGameControllable.weatherVersion(for: model.data.id)
            guard model.data.version == baseline else { return nil }
            root.weatherRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }

        switch model.type {
        case .reveal, .store:
            // A player request names only the Weather. Always rebuild the full
            // canonical package from the master; inbound peer bytes are ignored.
            return try await cachedWeatherPackage(for: model.data.id)
        case .update:
            // Weather is immutable for the lifetime of a game. Live update
            // messages are intentionally unsupported for now.
            return nil
        }
    }
}
