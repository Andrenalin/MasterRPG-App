// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import WeatherRPG

// The game master's weather on the 3D table. `.update/.tableWeather` names the weather before
// its reveal; the table draws it once this device holds the weather. See
// `MasterController+TableWeather.swift` for the sending side.

extension PlayerController {
    /// The game master's `.update/.tableWeather`.
    func handleTableWeather(_ model: GameNetworkModel) {
        guard let presentation = TableWeatherPresentation.decodeData(of: model.data.data),
              presentation.weatherId == model.data.id,
              model.data.type == .weather
        else {
            Logger.networking.error("PlayerController: Invalid table weather \(model.data.id, privacy: .public)")
            return
        }
        gameModel.tableWeather.applyMaster(presentation, isHeld: holdsWeather(presentation.weatherId))
    }

    /// A weather arrived on this device, revealed or stored: the table draws it if it is the
    /// one shown.
    func tableWeatherArrived(_ weatherId: UUID) {
        gameModel.tableWeather.weatherArrived(weatherId)
    }

    /// The game master's own screen draws from the library; a player from game memory.
    private func holdsWeather(_ weatherId: UUID) -> Bool {
        gameModel.asGameMaster || root.weatherRoot.gameControllable.gameModel.itemData[weatherId] != nil
    }
}
