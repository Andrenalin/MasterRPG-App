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

// MARK: - Lightning

extension MasterController {
    /// Sends a lightning strike the game master made on the weather on screen to every player.
    /// A strike is an event: it is not replayed to a device that joins later.
    func sendLightning(_ message: NetworkCodableDataType) async {
        guard !asProxy,
              message.type == .weather,
              let strike = WeatherLightningStrike.decodeData(of: message.data),
              strike.isValid,
              strike.weatherId == message.id,
              root.weatherRoot.gameControllable.gameModel.currentItemId == strike.weatherId
        else { return }
        await send(type: .update, subtype: .generic, updated: strike.networkData)
    }
}
