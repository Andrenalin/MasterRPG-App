// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import CharacterRPG
import PhotoRPG
import os.log

extension GameController {
    static let maximumFuturePinTimestampSkew: TimeInterval = 5 * 60
    static let maximumPackageExportAttempts = 3

    struct PackageMetadata: Equatable, Sendable {
        let version: Int
        let assetVersion: Int
        let contentVersion: Int
    }

    struct PackageCoreMetadata: Equatable, Sendable {
        let version: Int
        let contentVersion: Int
        let backgroundPhotoId: UUID?
    }

    struct MapContentCapture: Sendable {
        let core: PackageCoreMetadata
        let data: Data?
    }

    // MARK: - Package & version metadata

    @MainActor
    func networkGeneration(for itemId: UUID) -> MapGameModel.AuthoritativeGeneration {
        if let authoritative = mapGameModel.authoritativeGeneration(for: itemId) {
            return authoritative
        }
        let item = gameItem(for: itemId)
        return MapGameModel.AuthoritativeGeneration(
            version: item.version,
            assetVersion: currentMapAssetVersion(for: itemId),
            contentVersion: mapContentVersion(for: itemId)
        )
    }

    /// Shared validation for "is this payload still for the map generation
    /// this device currently has". Both the pin-update and battle-round-update
    /// apply paths need this exact six-condition check to stay in sync — see
    /// CODE_AUDIT §9.3.
    @MainActor
    func isCurrentGeneration(_ data: NetworkCodableDataType, for itemId: UUID) -> Bool {
        let generation = networkGeneration(for: itemId)
        return data.id == itemId
            && data.type == .map
            && gameModel.currentItemId == itemId
            && data.version == generation.version
            && data.assetVersion == generation.assetVersion
            && data.contentVersion == generation.contentVersion
    }

    /// Shared factory for a `.map`-typed `NetworkCodableDataType` envelope.
    /// Callers that already hold a `MapGameModel.AuthoritativeGeneration`
    /// (from `networkGeneration(for:)` or a `stablePackageMetadata`/
    /// `packageCoreMetadata` result) pass it straight through instead of
    /// re-deriving the three version fields inline at each call site — see
    /// CODE_AUDIT §9.2.
    static func mapNetworkData(
        id itemId: UUID,
        generation: MapGameModel.AuthoritativeGeneration,
        data: Data?
    ) -> NetworkCodableDataType {
        NetworkCodableDataType(
            id: itemId,
            type: .map,
            version: generation.version,
            data: data,
            assetVersion: generation.assetVersion,
            contentVersion: generation.contentVersion
        )
    }

    func stablePackageMetadata(for itemId: UUID) async -> PackageMetadata? {
        for _ in 0..<Self.maximumPackageExportAttempts {
            let before = await packageCoreMetadata(for: itemId)
            let backgroundPhotoVersion: Int?
            if let photoId = before.backgroundPhotoId {
                backgroundPhotoVersion = await root.photoRoot.gameControllable.networkVersion(for: photoId)
            } else {
                backgroundPhotoVersion = nil
            }
            let after = await packageCoreMetadata(for: itemId)
            let currentBackgroundPhotoVersion = await currentBackgroundPhotoVersion(
                for: after.backgroundPhotoId
            )
            guard before == after,
                  backgroundPhotoVersion == currentBackgroundPhotoVersion else {
                continue
            }
            return PackageMetadata(
                version: after.version,
                assetVersion: MapAssetFingerprint(
                    mapId: itemId,
                    backgroundPhotoId: after.backgroundPhotoId,
                    backgroundPhotoVersion: backgroundPhotoVersion
                ).version,
                contentVersion: after.contentVersion
            )
        }
        return nil
    }

    @MainActor
    func packageCoreMetadata(for itemId: UUID) -> PackageCoreMetadata {
        let item = gameItem(for: itemId)
        return PackageCoreMetadata(
            version: item.version,
            contentVersion: MapUpdatePayload(model: item).contentVersion,
            backgroundPhotoId: item.photoId
        )
    }

    @MainActor
    func mapContentCapture(for itemId: UUID) -> MapContentCapture {
        let item = gameItem(for: itemId)
        let payload = MapUpdatePayload(model: item)
        return MapContentCapture(
            core: PackageCoreMetadata(
                version: item.version,
                contentVersion: payload.contentVersion,
                backgroundPhotoId: item.photoId
            ),
            data: payload.encodeData()
        )
    }

    @MainActor
    func currentMapReference(for itemId: UUID) -> NetworkCodableDataType {
        let item = gameItem(for: itemId)
        // See CODE_AUDIT §9.2 — shared envelope factory. This site
        // deliberately builds its own generation from live state rather than
        // `networkGeneration(for:)`/`mapGameModel.authoritativeGeneration`,
        // since it's the package-export fallback path.
        return Self.mapNetworkData(
            id: itemId,
            generation: MapGameModel.AuthoritativeGeneration(
                version: item.version,
                assetVersion: currentMapAssetVersion(for: itemId),
                contentVersion: MapUpdatePayload(model: item).contentVersion
            ),
            data: nil
        )
    }

    @MainActor
    func currentMapContentUpdate(for itemId: UUID) -> NetworkCodableDataType {
        let capture = mapContentCapture(for: itemId)
        // See CODE_AUDIT §9.2 — same package-export fallback rationale as
        // `currentMapReference(for:)` above.
        return Self.mapNetworkData(
            id: itemId,
            generation: MapGameModel.AuthoritativeGeneration(
                version: capture.core.version,
                assetVersion: currentMapAssetVersion(for: itemId),
                contentVersion: capture.core.contentVersion
            ),
            data: capture.data
        )
    }

    @MainActor
    func currentBackgroundPhotoVersion(for photoId: UUID?) -> Int? {
        guard let photoId else { return nil }
        let gamePhoto = root.photoRoot.gameControllable.gameModel.itemData[photoId] as? PhotoModel
        let persistentPhoto = root.photoRoot.itemControllable.itemSync(for: photoId) as? PhotoModel
        return (gamePhoto ?? persistentPhoto)?.version ?? -1
    }

    @MainActor
    func currentMapAssetVersion(for itemId: UUID) -> Int {
        let backgroundPhotoId = gameItem(for: itemId).photoId
        let backgroundPhotoVersion = currentBackgroundPhotoVersion(for: backgroundPhotoId)
        return MapAssetFingerprint(
            mapId: itemId,
            backgroundPhotoId: backgroundPhotoId,
            backgroundPhotoVersion: backgroundPhotoVersion
        ).version
    }

    /// The shared "give this monotonic mutation a fresh timestamp" idiom used
    /// by every optimistic pin/pointer write. See CODE_AUDIT §9.4.
    static func bumpedTimeInterval(from previous: TimeInterval) -> TimeInterval {
        max(Date.now.timeIntervalSince1970, previous.nextUp)
    }

    static func applyPlayerMetadata(from source: MapPinModel, to destination: inout MapPinModel) {
        destination.name = source.name
        destination.color = source.color
        destination.photoId = source.photoId
        destination.characterId = source.characterId
        destination.isPlayer = true
        destination.players = source.players
    }

    @MainActor
    func resolveBattleConfiguredValues(
        for combatantId: UUID? = nil,
        remap: Bool = false
    ) {
        for combatant in battleRoundModel.combatants
        where combatantId == nil || combatant.id == combatantId {
            guard let gameCharacterId = combatant.gameCharacterId else { continue }

            if remap || combatant.initiativeEntryId == nil,
               let entry = root.characterRoot.valueGameControllable.gameEntry(
                   matchingAny: battleRoundSettings.initiativeNames,
                   characterId: gameCharacterId
               ) {
                _ = battleRoundModel.setValueEntry(
                    entry.id,
                    kind: .initiative,
                    for: combatant.id
                )
                // Automatic prefill is intentionally one-shot. A value typed
                // by the game master is never overwritten on later refreshes.
                if combatant.initiative == nil,
                   let value = root.characterRoot.valueGameControllable
                    .gameEntryDisplayValue(
                        characterId: gameCharacterId,
                        entryId: entry.id
                    ),
                   let initiative = battleInitiative(from: value) {
                    _ = battleRoundModel.setInitiative(
                        initiative,
                        for: combatant.id
                    )
                }
            }

            if remap || combatant.hitPointsEntryId == nil,
               let entry = root.characterRoot.valueGameControllable.gameEntry(
                   matchingAny: battleRoundSettings.hitPointsNames,
                   characterId: gameCharacterId
               ) {
                _ = battleRoundModel.setValueEntry(
                    entry.id,
                    kind: .hitPoints,
                    for: combatant.id
                )
            }

            // Re-fetch: the hit-points entry assigned just above isn't
            // reflected on the loop's original snapshot.
            applyHealthPercent(for: battleRoundModel.combatant(id: combatant.id) ?? combatant)
        }
    }

    /// Writes the freshly computed health percent onto the combatant's pin
    /// when it changed, so the map broadcast (and CloudKit save) only picks
    /// up a new `timeInterval` on an actual health change.
    @MainActor
    private func applyHealthPercent(for combatant: BattleCombatant) {
        guard let mapId = battleRoundModel.mapId else { return }
        let percent = healthPercent(for: combatant)
        guard combatant.pin.healthPercent != percent else {
            Logger.gameController.debug("applyHealthPercent: pin \(combatant.pin.name, privacy: .public) unchanged at \(percent.map { "\($0)" } ?? "nil", privacy: .public), not persisting")
            return
        }
        let persisted = updatePinState(itemId: mapId, pinId: combatant.pinId) { pin in
            pin.healthPercent = percent
        }
        Logger.gameController.debug("applyHealthPercent: pin \(combatant.pin.name, privacy: .public) → \(percent.map { "\($0)" } ?? "nil", privacy: .public), updatePinState persisted=\(persisted, privacy: .public)")
    }

    func battleInitiative(from value: String) -> Int? {
        if let value = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(1, value)
        }
        guard let value = Double(
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        ), value.isFinite, value >= Double(Int.min), value <= Double(Int.max) else {
            return nil
        }
        return max(1, Int(value))
    }

    @MainActor
    func releaseBattleCharacters(includingPlayers: Bool) {
        guard includingPlayers else { return }
        let ids = mapGameModel.battleCharacterCopyIds
        root.characterRoot.valueGameControllable.removeBattleCharacterCopies(ids)
    }

    @MainActor
    func applyActiveBattleHighlights(itemId: UUID) {
        guard let map = gameModel.itemData[itemId] as? MapModel,
              let entry = battleRoundModel.activeEntry,
              let attacker = battleRoundModel.attacker(for: entry) else {
            return
        }
        let highlightedPinIds = Set(
            [attacker.pinId] + battleRoundModel.defenders(for: entry).map(\.pinId)
        )
        for pin in map.mapPins where pin.isHighlighted != highlightedPinIds.contains(pin.id) {
            _ = updatePinState(itemId: itemId, pinId: pin.id) { updatedPin in
                updatedPin.isHighlighted = highlightedPinIds.contains(updatedPin.id)
            }
        }
        _ = battleRoundModel.synchronize(pins: map.mapPins)
    }

    @MainActor
    @discardableResult
    func updateMap(for itemId: UUID, with result: String) -> Bool {
        let model = gameItem(for: itemId)
        var entries = model.entries
        guard let pinArrayStart = result.firstIndex(of: "[") else { return false }
        let entrySection = result[..<pinArrayStart]
        guard entrySection.isEmpty || entrySection.last == "|" else { return false }
        let pinText = String(result[pinArrayStart...])
        guard let mapPins: [MapPinModel] = JSONString.decode(text: pinText),
              let pointer = mapPins.first else {
            return false
        }

        for entryToken in entrySection.split(separator: "|") {
            let entryState = entryToken.split(separator: ":", omittingEmptySubsequences: false)
            guard entryState.count == 3,
                  let entryId = UUID(uuidString: String(entryState[0])),
                  let shown = Self.mapStateBool(entryState[1]),
                  let focused = Self.mapStateBool(entryState[2]),
                  let entryIndex = entries.firstIndex(where: { $0.id == entryId }) else {
                return false
            }
            entries[entryIndex].isShown = shown
            entries[entryIndex].focused = focused
        }

        let incoming = Array(mapPins.dropFirst())
        // Preserve only fields a player may optimistically change while
        // awaiting the authoritative round trip. Visibility, size, death,
        // and metadata always come from the game-master mapState.
        let mergedPins = incoming.map { incomingPin in
            guard let local = model.mapPins.first(where: { $0.id == incomingPin.id }),
                  local.timeInterval > incomingPin.timeInterval else {
                return incomingPin
            }
            var mergedPin = incomingPin
            if incomingPin.isPlayer {
                mergedPin.location = local.location
            }
            mergedPin.isZoom = local.isZoom
            mergedPin.isHighlighted = local.isHighlighted
            mergedPin.timeInterval = local.timeInterval
            return mergedPin
        }

        model.pointer = pointer
        model.mapPins = mergedPins
        model.entries = entries
        return true
    }

    static func mapStateBool(_ value: Substring) -> Bool? {
        switch value {
        case "true": true
        case "false": false
        default: nil
        }
    }

    /// Applies a local pin mutation and gives it a monotonic timestamp. This is
    /// used by both authoritative master actions and optimistic player actions.
    @MainActor
    @discardableResult
    func updatePinState(
        itemId: UUID,
        pinId: UUID,
        mutation: (inout MapPinModel) -> Void
    ) -> Bool {
        mutatedPinState(itemId: itemId, pinId: pinId, mutation: mutation) != nil
    }

    /// The same mutate-bump-write-sync unit as `updatePinState(itemId:pinId:mutation:)`
    /// above, but handing back the mutated pin for callers that need to build
    /// something from it (e.g. a fresh `BattleCombatant`) instead of just
    /// knowing whether the write happened. Deliberately a distinctly-named
    /// function rather than an overload of `updatePinState` — an overload
    /// differing only in a trailing-closure parameter's label is ambiguous at
    /// every existing call site that discards or loosely infers the result
    /// (verified: it broke `applyHealthPercent`/`applyActiveBattleHighlights`
    /// below). See CODE_AUDIT §9.4.
    @MainActor
    @discardableResult
    func mutatedPinState(
        itemId: UUID,
        pinId: UUID,
        mutation: (inout MapPinModel) -> Void
    ) -> MapPinModel? {
        let item = gameItem(for: itemId)
        guard var pin = item.mapPins.first(where: { $0.id == pinId }) else { return nil }
        mutation(&pin)
        pin.timeInterval = Self.bumpedTimeInterval(from: pin.timeInterval)
        item[MapPinId.id, pinId] = pin
        if pin.isPlayer,
           let index = mapGameModel.playerPins.firstIndex(where: { $0.id == pinId }) {
            mapGameModel.playerPins[index] = pin
        }
        return pin
    }
}
