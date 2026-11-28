// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG
import WeatherRPG

// MARK: - Package cache (CODE_AUDIT_Game_Shareplay §7.2)

extension MasterController {
    /// The package for `fingerprint`: the one exported last if the item is unchanged, otherwise a
    /// fresh export, which is kept for the next player that asks.
    func cachedPackage(
        module: NetworkModules,
        itemId: UUID,
        fingerprint: () async -> MasterPackageFingerprint,
        export: () async throws -> NetworkCodableDataType
    ) async throws -> NetworkCodableDataType {
        let current = await fingerprint()
        if let cached = gameModel.packageCache.package(for: module, itemId: itemId, matching: current) {
            return cached
        }
        let package = try await export()
        gameModel.packageCache.store(package)
        return package
    }

    /// Package of a file-backed item (Photo, Pdf, Space, ...).
    func cachedPackage(
        module: NetworkModules,
        itemId: UUID,
        controllable: any GameControllable
    ) async throws -> NetworkCodableDataType {
        try await cachedPackage(
            module: module,
            itemId: itemId,
            fingerprint: {
                // Both versions, as the exported package carries them. See CODE_AUDIT_Edit_Save §5.10.
                let versions = await controllable.packageVersions(for: itemId)
                return MasterPackageFingerprint(version: versions.package, assetVersion: versions.asset)
            },
            export: { try await controllable.createGameData(for: itemId) }
        )
    }

    func cachedMapPackage(for mapId: UUID) async throws -> NetworkCodableDataType {
        let map = root.mapRoot.mapGameControllable
        return try await cachedPackage(
            module: .map,
            itemId: mapId,
            fingerprint: { MasterPackageFingerprint(await map.shareMap(id: mapId)) },
            export: { try await map.createMapGameData(for: mapId) }
        )
    }

    func cachedWeatherPackage(for weatherId: UUID) async throws -> NetworkCodableDataType {
        let weather = root.weatherRoot.weatherGameControllable
        return try await cachedPackage(
            module: .weather,
            itemId: weatherId,
            fingerprint: { MasterPackageFingerprint(version: await weather.weatherVersion(for: weatherId)) },
            export: { try await weather.createWeatherGameData(for: weatherId) }
        )
    }
}
