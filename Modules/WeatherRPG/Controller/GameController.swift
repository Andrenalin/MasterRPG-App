// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import PhotoRPG

@MainActor @Observable
final class WeatherGameModel: Sendable {
    init() {}

    /// Package versions received during the current game session. Weather is
    /// deliberately not persisted on a player device, so this session state is
    /// the authority for deciding whether an id-only reveal can be displayed.
    var availableVersions: [UUID: Int] = [:]

    func reset() {
        availableVersions.removeAll()
    }
}

public protocol WeatherGameControllable: Sendable {
    /// Stable wire version of the complete Weather package. Weather itself is
    /// immutable during a game, so only its linked Photo asset participates.
    func weatherVersion(for itemId: UUID) async -> Int
    func shareWeather(id: UUID) async -> NetworkCodableDataType
    func createWeatherGameData(for itemId: UUID) async throws -> NetworkCodableDataType

    @MainActor func isWeatherAvailable(itemId: UUID, version: Int) -> Bool
    @MainActor func markWeatherAvailable(itemId: UUID, version: Int)

    /// Reveals a Weather from session memory or imports a full package into
    /// session memory. A successful full import also makes the item current.
    func revealWeather(itemId: UUID, data: NetworkCodableDataType) async throws -> Bool
}

struct GameController: Sendable {
    @MainActor init(itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.weatherGameModel = WeatherGameModel()
    }

    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let weatherGameModel: WeatherGameModel

    @MainActor func gameItem(for itemId: UUID) -> WeatherModel {
        (gameModel.itemData[itemId] as? WeatherModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor func currentItem() -> WeatherModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        weatherGameModel.reset()
    }
}

extension GameController: WeatherGameControllable {
    func weatherVersion(for itemId: UUID) async -> Int {
        let photoId = await MainActor.run {
            gameItem(for: itemId).photoId
        }
        guard let photoId else { return 0 }
        guard await exportController.photoRoot.itemControllable.item(for: photoId) != nil else {
            return 0
        }
        return await exportController.photoRoot.gameControllable.networkVersion(for: photoId)
    }

    func shareWeather(id: UUID) async -> NetworkCodableDataType {
        NetworkCodableDataType(
            id: id,
            type: .weather,
            version: await weatherVersion(for: id)
        )
    }

    func createWeatherGameData(for itemId: UUID) async throws -> NetworkCodableDataType {
        // Resolve the Photo version before exporting. The Photo controller can
        // lazily backfill a legacy file's content hash, and the subsequent
        // archive must carry that same stable metadata to the receiver.
        let version = await weatherVersion(for: itemId)
        let base = try await createGameData(for: itemId)
        return NetworkCodableDataType(
            id: base.id,
            type: base.type,
            version: version,
            data: base.data
        )
    }

    @MainActor
    func isWeatherAvailable(itemId: UUID, version: Int) -> Bool {
        weatherGameModel.availableVersions[itemId] == version
            && gameModel.itemData[itemId] is WeatherModel
    }

    @MainActor
    func markWeatherAvailable(itemId: UUID, version: Int) {
        weatherGameModel.availableVersions[itemId] = version
    }

    func revealWeather(itemId: UUID, data: NetworkCodableDataType) async throws -> Bool {
        guard data.id == itemId, data.type == .weather else {
            throw ItemGameStorableError.wrongData
        }

        if await isWeatherAvailable(itemId: itemId, version: data.version) {
            return await setCurrent(itemId: itemId)
        }

        guard data.data != nil else { return false }
        try await updateGame(
            data: data,
            hide: false,
            deep: true,
            policy: .memoryOnly
        )
        guard await MainActor.run(body: {
            gameModel.itemData[itemId] is WeatherModel
        }) else {
            return false
        }

        await markWeatherAvailable(itemId: itemId, version: data.version)
        return await setCurrent(itemId: itemId)
    }
}
