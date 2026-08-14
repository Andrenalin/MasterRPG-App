// @copyright André Trettin

import CoreRPG
import Foundation
import WeatherRPG

extension PlayerController {
    func handleWeather(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        switch model.type {
        case .reveal:
            if try await root.weatherRoot.weatherGameControllable.revealWeather(
                itemId: model.data.id,
                data: model.data
            ) {
                gameModel.setGameUpdateType(.weather)
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            // Weather packages are game-session assets. Even legacy store
            // messages must stay in game memory and never enter persistence.
            try await root.weatherRoot.gameControllable.updateGame(data: model.data, hide: true, deep: true)
            root.weatherRoot.weatherGameControllable.markWeatherAvailable(
                itemId: model.data.id,
                version: model.data.version
            )
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            // Weather is immutable during a game. Presentation and repair use
            // reveal messages; live update messages are intentionally ignored.
            break
        }
        return nil
    }
}
