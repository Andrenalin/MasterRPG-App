// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import CharacterRPG
import PhotoRPG

@MainActor @Observable
final class MapGameModel {
    struct AuthoritativeGeneration: Equatable, Sendable {
        let version: Int
        let assetVersion: Int
        let contentVersion: Int
    }

    init() {
        let settings = BattleRoundSettingsModel()
        let battleRound = BattleRoundModel()
        battleRound.initiativeOrder = settings.initiativeOrder
        battleRoundSettings = settings
        battleRoundModel = battleRound
    }

    var playerPins: [MapPinModel] = []
    let battleRoundModel: BattleRoundModel
    let battleRoundSettings: BattleRoundSettingsModel
    private(set) var battleCharacterCopyIds: Set<UUID> = []
    private var authoritativeGenerations: [UUID: AuthoritativeGeneration] = [:]
    private var lastActivatedRoomIds: [UUID: UUID] = [:]

    func recordAuthoritativeGeneration(_ data: NetworkCodableDataType) {
        guard data.type == .map else { return }
        guard let assetVersion = data.assetVersion,
              let contentVersion = data.contentVersion else {
            authoritativeGenerations[data.id] = nil
            return
        }
        authoritativeGenerations[data.id] = AuthoritativeGeneration(
            version: data.version,
            assetVersion: assetVersion,
            contentVersion: contentVersion
        )
    }

    func authoritativeGeneration(for itemId: UUID) -> AuthoritativeGeneration? {
        authoritativeGenerations[itemId]
    }

    func recordActivatedRoom(_ roomId: UUID, for mapId: UUID) {
        lastActivatedRoomIds[mapId] = roomId
    }

    func lastActivatedRoomId(for mapId: UUID) -> UUID? {
        lastActivatedRoomIds[mapId]
    }

    func registerBattleCharacterCopy(_ id: UUID) {
        battleCharacterCopyIds.insert(id)
    }

    func clearBattleCharacterCopies() {
        battleCharacterCopyIds = []
    }
    
    func reset() {
        playerPins = []
        authoritativeGenerations = [:]
        lastActivatedRoomIds = [:]
        battleCharacterCopyIds = []
        battleRoundModel.reset()
    }
}

public protocol MapGameStorable: Sendable {
    @MainActor var battleRoundModel: BattleRoundModel { get }
    @MainActor var battleRoundSettings: BattleRoundSettingsModel { get }
    /// Parses a Character entry's display value into a valid battle initiative
    /// (minimum 1). Guards against a finite-but-out-of-`Int`-range value
    /// trapping `Int(_:)` — the single correct implementation, exposed here so
    /// `BattleRoundController` doesn't need its own copy. See CODE_AUDIT_Game §5.1/§9.1.
    func battleInitiative(from value: String) -> Int?
    func mapAssetVersion(for itemId: UUID) async -> Int
    @MainActor func mapContentVersion(for itemId: UUID) -> Int
    @MainActor func recordAuthoritativeMapGeneration(_ data: NetworkCodableDataType)
    @MainActor func refreshAuthoritativeMapContentVersion(for itemId: UUID)
    func shareMap(id: UUID) async -> NetworkCodableDataType
    /// `@concurrent`, like `createGameData`. See CODE_AUDIT_18 §7.1.
    @concurrent func createMapGameData(for itemId: UUID) async throws -> NetworkCodableDataType
    func networkMapContentUpdate(for itemId: UUID) async -> NetworkCodableDataType
    @MainActor func applyMapContentUpdate(for itemId: UUID, with data: NetworkCodableDataType) -> Bool

    @MainActor func setPlayerPin(for playerId: UUID, name: String, characterId: UUID)
    @MainActor func resetPlayerPins(for players: [PlayerGameModel])
    @MainActor @discardableResult func synchronizePlayerPins(for itemId: UUID) -> Bool
    @MainActor func updatePin(itemId: UUID, data: Data?, playerId: UUID) -> Bool
    @MainActor func updatePinIfCurrentGeneration(
        itemId: UUID,
        data: NetworkCodableDataType,
        playerId: UUID
    ) -> Bool
    func hasBackgroundImage(itemId: UUID) async -> Bool
    func missingMapImages(itemId: UUID) async -> [NetworkCodableDataType]
    @MainActor func movePin(itemId: UUID, pinId: UUID, location: CGPoint) -> Bool
    @MainActor func toggleRoom(itemId: UUID, roomId: UUID) -> Bool
    @MainActor func toggleRoomFocus(itemId: UUID, roomId: UUID) -> Bool
    @MainActor func setRoomsShown(itemId: UUID, roomIds: [UUID], isShown: Bool) -> Bool
    @MainActor func movePointer(itemId: UUID, location: CGPoint) -> Bool
    @MainActor func togglePointer(itemId: UUID) -> Bool
    @MainActor func networkPointer(itemId: UUID) -> NetworkCodableDataType?
    @MainActor func addMonstersAtMapCenter(itemId: UUID, monsters: [ItemRowModel]) -> Bool
    @MainActor func togglePin(itemId: UUID, pinId: UUID) -> Bool
    @MainActor func zoomPin(itemId: UUID, pinId: UUID) -> Bool
    @MainActor func toggleDeadPin(itemId: UUID, pinId: UUID) -> Bool
    @MainActor func resizePin(itemId: UUID, pinId: UUID) -> Bool
    /// `isGameMaster` is threaded straight through to `synchronizeBattleDefenders`
    /// — the actual highlight toggle always applies locally (both master and
    /// player need their own optimistic view before the network round trip),
    /// but only the master may let that highlight auto-add/repair battle
    /// combatants and recompute `pin.healthPercent`. See that function's own
    /// doc comment for why.
    @MainActor func toggleHighlightPin(itemId: UUID, pinId: UUID, isGameMaster: Bool) -> Bool
    @MainActor func networkPin(itemId: UUID, pinId: UUID) -> NetworkCodableDataType?
    /// The player/room pins eligible to start a battle on `itemId` — pure
    /// map lookup (current map, focused/last-activated room, pins within
    /// it) — or nil if `itemId` isn't the current map or no pins qualify.
    @MainActor func battleStartPins(itemId: UUID) -> (playerPins: [MapPinModel], roomPins: [MapPinModel])?
    /// Resolves (creating a battle-only runtime copy if needed) the
    /// Character behind `pinId` and packages it as a `BattleCombatant`.
    /// Shared by `startBattle`/`addBattleCombatant` (compound, still called
    /// directly by the map editor and tested in isolation) and by
    /// `synchronizeBattleDefenders`, so it stays a single MapRPG primitive.
    @MainActor func makeBattleCombatant(itemId: UUID, pinId: UUID) -> BattleCombatant?
    /// Clears any highlighted pins on the map — battle start/end always
    /// begins from a clean highlight state.
    @MainActor func clearBattleHighlights(itemId: UUID)
    /// The actual domain mutation (`BattleRoundModel.begin`, settings,
    /// auto-resolving configured initiative/HP entries, pin sync) once the
    /// combatants are already built. Kept in MapRPG because it needs
    /// internal access to `BattleRoundModel`'s mutators.
    @MainActor @discardableResult func beginBattle(
        itemId: UUID,
        playerCombatants: [BattleCombatant],
        roomCombatants: [BattleCombatant],
        initiativeOrder: BattleInitiativeOrder
    ) -> Bool
    @MainActor func startBattle(
        itemId: UUID,
        initiativeOrder: BattleInitiativeOrder
    ) -> Bool
    @MainActor func endBattle(itemId: UUID) -> Bool
    @MainActor func setBattleInitiative(
        itemId: UUID,
        combatantId: UUID,
        value: Int?
    ) -> Bool
    @MainActor func adjustBattleInitiative(
        itemId: UUID,
        combatantId: UUID,
        amount: Int
    ) -> Bool
    @MainActor func setBattleInitiativeOrder(
        itemId: UUID,
        order: BattleInitiativeOrder
    ) -> Bool
    @MainActor func moveBattleEntries(from source: IndexSet, to destination: Int)
    @MainActor func activateBattleAttacker(itemId: UUID, combatantId: UUID) -> Bool
    @MainActor func nextBattleAttacker(itemId: UUID) -> Bool
    @MainActor func nextBattleRound(itemId: UUID) -> Bool
    @MainActor func addBattleCombatant(itemId: UUID, pinId: UUID) -> Bool
    @MainActor func removeBattleCombatant(itemId: UUID, combatantId: UUID) -> Bool
    @MainActor func addBattleRoll(
        itemId: UUID,
        combatantId: UUID,
        total: Int,
        expression: String?
    ) -> Bool
    @MainActor func selectBattleRollRecipient(
        itemId: UUID,
        combatantId: UUID
    ) -> Bool
    @MainActor func setBattleCombatantDead(
        itemId: UUID,
        combatantId: UUID,
        isDead: Bool
    ) -> Bool
    @MainActor func assignBattleCharacter(
        itemId: UUID,
        combatantId: UUID,
        characterId: UUID
    ) -> Bool
    @MainActor @discardableResult func setBattleValueEntry(
        itemId: UUID,
        combatantId: UUID,
        entryId: UUID?,
        kind: BattleValueKind
    ) -> Bool
    @MainActor func refreshBattleConfiguredValues(itemId: UUID)
    /// `isGameMaster` gates every mutation this performs (auto-adding
    /// defenders, repairing the attacker highlight, recomputing
    /// `pin.healthPercent`) to the master only — see the implementation's
    /// doc comment for why a player must never let this run for real.
    /// `healthChanged` is broken out separately from the broader `changed`
    /// flag (which also fires for highlight-only defender bookkeeping the
    /// group-relayed `.mapPin` event already covers) so a caller can decide
    /// to rebroadcast only when `pin.healthPercent` itself actually moved —
    /// genuinely new information derived from Character data players don't
    /// have, unlike `isHighlighted`.
    @MainActor @discardableResult func synchronizeBattleDefenders(
        itemId: UUID,
        isGameMaster: Bool
    ) -> (changed: Bool, healthChanged: Bool)
    /// The live health percent (0...100) for a tracked combatant, computed
    /// from its linked hit-points entry. `MapPinView` calls this directly so
    /// the game master's own screen reflects an entry change the instant it
    /// happens, rather than waiting for the next broadcast to `pin.healthPercent`.
    @MainActor func healthPercent(for combatant: BattleCombatant) -> Double?
    @MainActor func networkBattleRoundUpdate(for itemId: UUID) -> NetworkCodableDataType?
    @MainActor func applyBattleRoundUpdate(for itemId: UUID, with data: NetworkCodableDataType) -> Bool
    @MainActor func resetBattleRound()
    @MainActor @discardableResult func updateMap(for itemId: UUID, with data: NetworkCodableDataType) -> Bool
    @MainActor func mapUpdateResult(for itemId: UUID) -> String
    @MainActor func networkMapUpdate(for itemId: UUID) -> NetworkCodableDataType
    /// Envelope carrying only the map's version fingerprint (no payload) — use for comparisons
    /// instead of `networkMapUpdate`, which serialises every entry and pin. See CODE_AUDIT_17 §7.3.
    @MainActor func networkMapGeneration(for itemId: UUID) -> NetworkCodableDataType
    @MainActor func saveAll() -> ItemModuleIds
    
    @MainActor func demoNextMap(itemId: UUID, restart: Bool) -> NetworkCodableDataType?
    
    @MainActor func startGameAsMaster()
}

struct GameController: Sendable {
    @MainActor init(root: MapRootModel, itemController: ItemController, exportController: ExportController) {
        self.root = root
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.mapGameModel = MapGameModel()
    }

    let root: MapRootModel
    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let mapGameModel: MapGameModel

}

// gameItem(for:)/setGame(item:itemId:)/currentItem() come from
// ModuleGameControllable's default implementations. See CODE_AUDIT_Game §9.1.
extension GameController: ModuleGameControllable {}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        releaseBattleCharacters(includingPlayers: true)
        mapGameModel.reset()
    }
}

extension GameController: MapGameStorable {
    @MainActor
    var battleRoundModel: BattleRoundModel {
        mapGameModel.battleRoundModel
    }

    @MainActor
    var battleRoundSettings: BattleRoundSettingsModel {
        mapGameModel.battleRoundSettings
    }

    func mapAssetVersion(for itemId: UUID) async -> Int {
        if let generation = await mapGameModel.authoritativeGeneration(for: itemId) {
            return generation.assetVersion
        }
        if let metadata = await stablePackageMetadata(for: itemId) {
            return metadata.assetVersion
        }
        return await currentMapAssetVersion(for: itemId)
    }

    @MainActor
    func mapContentVersion(for itemId: UUID) -> Int {
        MapUpdatePayload(model: gameItem(for: itemId)).contentVersion
    }

    @MainActor
    func recordAuthoritativeMapGeneration(_ data: NetworkCodableDataType) {
        mapGameModel.recordAuthoritativeGeneration(data)
    }

    /// Re-stamps the recorded generation's content fingerprint from the map's
    /// current live structure, keeping `assetVersion`/`version` untouched.
    ///
    /// `presentMap()` reconciles session player pins into a freshly revealed
    /// map on the game master's own co-located device right after this
    /// device recorded that reveal's content-version fingerprint. Left alone,
    /// that reconciliation silently invalidates the fingerprint it just
    /// recorded: the master's own screen would then see every later
    /// reference-only reshow of that same, unedited map as a missed
    /// structural edit and stall on an unnecessary repair round trip instead
    /// of presenting it again.
    @MainActor
    func refreshAuthoritativeMapContentVersion(for itemId: UUID) {
        guard let previous = mapGameModel.authoritativeGeneration(for: itemId) else { return }
        let refreshedContentVersion = mapContentVersion(for: itemId)
        guard refreshedContentVersion != previous.contentVersion else { return }
        // See CODE_AUDIT §9.2 — shared envelope factory.
        mapGameModel.recordAuthoritativeGeneration(
            Self.mapNetworkData(
                id: itemId,
                generation: MapGameModel.AuthoritativeGeneration(
                    version: gameItem(for: itemId).version,
                    assetVersion: previous.assetVersion,
                    contentVersion: refreshedContentVersion
                ),
                data: nil
            )
        )
    }

    func shareMap(id: UUID) async -> NetworkCodableDataType {
        guard let metadata = await stablePackageMetadata(for: id) else {
            // A continuously edited map may not become stable within the
            // bounded retry window. This actor-isolated fallback is still one
            // internally consistent generation; a later asset change simply
            // makes receivers request the full package.
            return await currentMapReference(for: id)
        }
        // See CODE_AUDIT §9.2 — shared envelope factory.
        return Self.mapNetworkData(
            id: id,
            generation: MapGameModel.AuthoritativeGeneration(
                version: metadata.version,
                assetVersion: metadata.assetVersion,
                contentVersion: metadata.contentVersion
            ),
            data: nil
        )
    }

    @concurrent func createMapGameData(for itemId: UUID) async throws -> NetworkCodableDataType {
        // Export suspends while dependent assets are collected. Validate the
        // generation on both sides of that suspension so the bytes and their
        // advertised fingerprints cannot describe two different map edits.
        for _ in 0..<Self.maximumPackageExportAttempts {
            guard let before = await stablePackageMetadata(for: itemId) else { continue }
            let base = try await createGameData(for: itemId)
            guard let after = await stablePackageMetadata(for: itemId),
                  before == after,
                  base.version == after.version else {
                continue
            }
            // See CODE_AUDIT §9.2. `base.type` is always `.map` here — this is
            // the Map module's own export path — matching the factory's fixed
            // `type: .map`.
            return Self.mapNetworkData(
                id: base.id,
                generation: MapGameModel.AuthoritativeGeneration(
                    version: after.version,
                    assetVersion: after.assetVersion,
                    contentVersion: after.contentVersion
                ),
                data: base.data
            )
        }
        throw MapGameStorableError.packageChangedDuringExport
    }

    func networkMapContentUpdate(for itemId: UUID) async -> NetworkCodableDataType {
        for _ in 0..<Self.maximumPackageExportAttempts {
            let capture = await mapContentCapture(for: itemId)
            guard let metadata = await stablePackageMetadata(for: itemId),
                  capture.core.version == metadata.version,
                  capture.core.contentVersion == metadata.contentVersion,
                  await packageCoreMetadata(for: itemId) == capture.core else {
                continue
            }
            // See CODE_AUDIT §9.2 — shared envelope factory.
            return Self.mapNetworkData(
                id: itemId,
                generation: MapGameModel.AuthoritativeGeneration(
                    version: metadata.version,
                    assetVersion: metadata.assetVersion,
                    contentVersion: metadata.contentVersion
                ),
                data: capture.data
            )
        }
        return await currentMapContentUpdate(for: itemId)
    }

    @MainActor
    func applyMapContentUpdate(for itemId: UUID, with data: NetworkCodableDataType) -> Bool {
        guard data.id == itemId,
              data.type == .map,
              let payload = MapUpdatePayload.decodeData(of: data.data),
              payload.isSupported,
              payload.snapshot.id == itemId,
              data.contentVersion == nil || data.contentVersion == payload.contentVersion,
              let model = gameModel.itemData[itemId] as? MapModel else {
            return false
        }
        payload.snapshot.apply(to: model)
        mapGameModel.recordAuthoritativeGeneration(data)
        return true
    }

    /// Commits an editor working copy into the already-observed game map before
    /// the toolbar creates a structural update. Maps that are not in the active
    /// game are deliberately left alone.
    @MainActor
    func refreshSharedMap(from editedMap: MapModel) -> Bool {
        guard let gameMap = gameModel.itemData[editedMap.id] as? MapModel else { return false }
        MapSnapshot(editedMap).apply(to: gameMap)
        return true
    }

    @MainActor func startGameAsMaster() {
        root.rootModel.isMapStreaming = true
        root.rootModel.gameDisplayMode = .master
    }
}

private enum MapGameStorableError: Error {
    case packageChangedDuringExport
}
