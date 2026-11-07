// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import WeatherRPG

// The weather the game master shows also covers every 3D game table. `.update/.tableWeather`
// goes out before the weather's reveal; a player draws it once it holds the weather. The game
// master's own screen keeps the state, through its loopback, as for photos over the map. See
// `PlayerController+TableWeather.swift` for the receiving side.

extension MasterController {
    /// Whether the game master sends `.update/.tableWeather` at all. Off for now: no table shows
    /// a weather and the "Clear Weather" button never appears. Players still accept the message.
    nonisolated static let isTableWeatherEnabled = false

    /// Shows a weather on every table: sent with each show of a weather.
    func showTableWeather(_ weatherId: UUID) async {
        guard Self.isTableWeatherEnabled, !asProxy else { return }
        await broadcastTableWeather(TableWeatherPresentation(
            weatherId: weatherId,
            isShown: true,
            sequence: gameModel.nextTableWeatherSequence(),
            sessionId: gameModel.deliverySessionId
        ))
    }

    /// Clears the weather from every table.
    func clearTableWeather() async {
        guard Self.isTableWeatherEnabled,
              !asProxy,
              let weatherId = root.gameModel.playerController?.gameModel.tableWeather.shownWeatherId
        else { return }
        await broadcastTableWeather(TableWeatherPresentation(
            weatherId: weatherId,
            isShown: false,
            sequence: gameModel.nextTableWeatherSequence(),
            sessionId: gameModel.deliverySessionId
        ))
    }

    func broadcastTableWeather(_ presentation: TableWeatherPresentation) async {
        await send(type: .update, subtype: .tableWeather, updated: presentation.networkData)
    }

    /// Replays the table's weather to a peer that just became ready: the weather's package,
    /// then which weather the table shows.
    func replayTableWeather(to origin: GameMessageOrigin) async {
        guard Self.isTableWeatherEnabled,
              !asProxy,
              let presentation = root.gameModel.playerController?.gameModel.tableWeather.presentation,
              presentation.isShown
        else { return }
        do {
            let package = try await root.weatherRoot.weatherGameControllable.createWeatherGameData(for: presentation.weatherId)
            await send(type: .store, subtype: .store, updated: package, origin: origin, authoritativeMaster: true)
        } catch {
            // The peer still learns the weather; a later show delivers its package.
            Logger.networking.error("MasterController: Cannot replay table weather \(presentation.weatherId, privacy: .public): \(error.logIdentifier, privacy: .public)")
        }
        await send(
            type: .update,
            subtype: .tableWeather,
            updated: presentation.networkData,
            origin: origin,
            authoritativeMaster: true
        )
    }
}
