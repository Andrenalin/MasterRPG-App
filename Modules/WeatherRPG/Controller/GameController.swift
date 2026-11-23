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
    private(set) var inFlightReveals: [UUID: InFlightReveal] = [:]

    /// A running reveal. `version` lets a caller with the same package join it, `token` keeps a
    /// finished reveal from clearing the entry of the newer one that replaced it.
    struct InFlightReveal {
        let token: UUID
        let version: Int
        let task: Task<Bool, Error>
    }

    func reset() {
        availableVersions.removeAll()
        inFlightReveals.removeAll()
    }

    /// Returns the running reveal of the same package, or registers a new one that
    /// `makeTask` builds from the reveal it has to wait for. Looking up and registering happen
    /// in this one synchronous call: with an `await` between them, two overlapping reveals could
    /// both see "nothing running" and import in parallel, letting the older package finish last.
    func reveal(
        for itemId: UUID,
        version: Int,
        makeTask: (_ previous: InFlightReveal?, _ token: UUID) -> Task<Bool, Error>
    ) -> Task<Bool, Error> {
        let previous = inFlightReveals[itemId]
        if let previous, previous.version == version {
            return previous.task
        }
        let token = UUID()
        let task = makeTask(previous, token)
        inFlightReveals[itemId] = InFlightReveal(token: token, version: version, task: task)
        return task
    }

    func clearInFlightReveal(for itemId: UUID, token: UUID) {
        guard inFlightReveals[itemId]?.token == token else { return }
        inFlightReveals[itemId] = nil
    }
}

public protocol WeatherGameControllable: Sendable {
    /// Stable wire version of the complete Weather package: the Weather's sky and storm settings
    /// plus its linked Photo asset.
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
    /// The version players compare their cached copy with: the Weather's own settings plus the
    /// linked Photo's version, so editing a Weather during a game reaches the players on the next
    /// show. See CODE_AUDIT §5.7.
    func weatherVersion(for itemId: UUID) async -> Int {
        // `gameItem(for:)` is itself `@MainActor` — `await` alone hops there, no
        // `MainActor.run` wrapper needed.
        let weather = await gameItem(for: itemId)
        let photoVersion = await linkedPhotoVersion(of: weather)
        return await weather.contentVersion(photoVersion: photoVersion)
    }

    private func linkedPhotoVersion(of weather: WeatherModel) async -> Int {
        guard let photoId = await weather.photoId,
              await exportController.photoRoot.itemControllable.item(for: photoId) != nil else {
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

        // Never race a running reveal of this item — otherwise two overlapping reveals could
        // both pass `isWeatherAvailable` before either finishes importing, and the later
        // `markWeatherAvailable` could win with a version that doesn't match what `setCurrent`
        // sees. The same package joins the running reveal; a different one (a newer package,
        // see CODE_AUDIT §3.1) runs after it, so its payload is never dropped.
        let task = await weatherGameModel.reveal(for: itemId, version: data.version) { previous, token in
            Task {
                try await performReveal(itemId: itemId, data: data, after: previous, token: token)
            }
        }

        return try await task.value
    }

    /// The body of one registered reveal: waits for the reveal it follows, then shows the
    /// session copy or imports the package. `@concurrent`, so the import stays off the main actor.
    @concurrent
    private func performReveal(
        itemId: UUID,
        data: NetworkCodableDataType,
        after previous: WeatherGameModel.InFlightReveal?,
        token: UUID
    ) async throws -> Bool {
        if let previous {
            _ = try? await previous.task.value
        }
        defer {
            Task { @MainActor in weatherGameModel.clearInFlightReveal(for: itemId, token: token) }
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
}
