// @copyright André Trettin

import CoreRPG
import Foundation
import WeatherRPG

extension PlayerController {
    func handleWeather(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }
        if model.type == .update, model.subType == .photoPresentation {
            // How a weather over the map is shown; only the game master sends it.
            guard model.sender.isMaster else { return nil }
            await handleMapPhotoPresentation(model)
            return nil
        }
        if model.type == .update, model.subType == .generic {
            // A lightning strike on the weather on screen; only the game master sends it.
            guard model.sender.isMaster,
                  model.data.type == .weather,
                  let strike = WeatherLightningStrike.decodeData(of: model.data.data),
                  strike.weatherId == model.data.id
            else { return nil }
            root.weatherRoot.receiveLightning(strike)
            return nil
        }
        if model.type == .update, model.subType == .tableWeather {
            // The weather on the 3D table; only the game master sends it.
            guard model.sender.isMaster else { return nil }
            handleTableWeather(model)
            return nil
        }

        // Weather is immutable during a game. Presentation and request answers use reveal
        // messages; its only live update is the lightning strike above.
        return try await answerHeldItem(
            model,
            reveal: { try await revealWeather(model) },
            didReveal: {
                // A weather the game master showed while the map was on screen opens on the map.
                if !presentOnMap(.weather, itemId: model.data.id) {
                    gameModel.showWeather()
                }
                tableWeatherArrived(model.data.id)
            },
            store: {
                // Weather packages are game-session assets. Even legacy store messages must stay
                // in game memory and never enter persistence.
                try await root.weatherRoot.gameControllable.updateGame(data: model.data, hide: true, deep: true)
                root.weatherRoot.weatherGameControllable.markWeatherAvailable(
                    itemId: model.data.id,
                    version: model.data.version
                )
                tableWeatherArrived(model.data.id)
                return true
            }
        )
    }

    /// Makes the revealed weather current. The game master's own screen shows it from the
    /// library: it gets only the reference, and its request for the package is never sent. A
    /// player shows it from session memory or the delivered package.
    private func revealWeather(_ model: GameNetworkModel) async throws -> Bool {
        if gameModel.asGameMaster {
            return await root.weatherRoot.gameControllable.setCurrent(itemId: model.data.id)
        }
        return try await root.weatherRoot.weatherGameControllable.revealWeather(
            itemId: model.data.id,
            data: model.data
        )
    }
}
