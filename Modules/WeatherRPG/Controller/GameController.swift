// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import PhotoRPG

@MainActor @Observable
final class WeatherGameModel {
    init() {}

    /// Package versions received during the current game session. Weather is
    /// deliberately not persisted on a player device, so this session state is
    /// the authority for deciding whether an id-only reveal can be displayed.
    var availableVersions: [UUID: Int] = [:]

    /// Serializes concurrent `revealWeather(itemId:data:)` calls for the same item
    /// (e.g. a stale retransmit racing a newer update) so the "check availability,
    /// import, mark available" sequence can't interleave across two callers. See
    /// CODE_AUDIT_Weather §5.4.
    private var inFlightReveals: [UUID: Task<Bool, Error>] = [:]

    func reset() {
        availableVersions.removeAll()
        inFlightReveals.removeAll()
    }

    func inFlightReveal(for itemId: UUID) -> Task<Bool, Error>? {
        inFlightReveals[itemId]
    }

    func setInFlightReveal(_ task: Task<Bool, Error>, for itemId: UUID) {
        inFlightReveals[itemId] = task
    }

    func clearInFlightReveal(for itemId: UUID) {
        inFlightReveals[itemId] = nil
    }
}

public protocol WeatherGameControllable: Sendable {
    /// Stable wire version of the complete Weather package. Weather itself is
    /// immutable during a game, so only its linked Photo asset participates.
    func weatherVersion(for itemId: UUID) async -> Int
    func shareWeather(id: UUID) async -> NetworkCodableDataType
    /// `@concurrent`, like `createGameData`. See CODE_AUDIT_18 §7.1.
    @concurrent func createWeatherGameData(for itemId: UUID) async throws -> NetworkCodableDataType

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

}

// gameItem(for:)/setGame(item:itemId:)/currentItem() come from
// ModuleGameControllable's default implementations. See CODE_AUDIT_Game §9.1.
extension GameController: ModuleGameControllable {}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        weatherGameModel.reset()
    }
}

extension GameController: WeatherGameControllable {
    func weatherVersion(for itemId: UUID) async -> Int {
        // `gameItem(for:)` is itself `@MainActor` — `await` alone hops there, no
        // `MainActor.run` wrapper needed.
        let photoId = await gameItem(for: itemId).photoId
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

    @concurrent func createWeatherGameData(for itemId: UUID) async throws -> NetworkCodableDataType {
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

    @MainActor
    private func hasWeatherModel(itemId: UUID) -> Bool {
        gameModel.itemData[itemId] is WeatherModel
    }

    func revealWeather(itemId: UUID, data: NetworkCodableDataType) async throws -> Bool {
        guard data.id == itemId, data.type == .weather else {
            throw ItemGameStorableError.wrongData
        }

        // Join an already-running reveal for this item instead of racing it —
        // otherwise two overlapping reveals could both pass `isWeatherAvailable`
        // before either finishes importing, and the later `markWeatherAvailable`
        // could win with a version that doesn't match what `setCurrent` sees.
        if let inFlight = await weatherGameModel.inFlightReveal(for: itemId) {
            return try await inFlight.value
        }

        let task = Task<Bool, Error> {
            defer {
                Task { @MainActor in weatherGameModel.clearInFlightReveal(for: itemId) }
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
            guard await hasWeatherModel(itemId: itemId) else {
                return false
            }

            await markWeatherAvailable(itemId: itemId, version: data.version)
            return await setCurrent(itemId: itemId)
        }

        await weatherGameModel.setInFlightReveal(task, for: itemId)
        return try await task.value
    }
}
