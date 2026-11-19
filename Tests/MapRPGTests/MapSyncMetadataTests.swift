// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import CharacterRPG
@testable import MapRPG
@testable import PhotoRPG

// CharacterRPG and PhotoRPG have a GameController of their own.
private typealias GameController = MapRPG.GameController

/// CODE_AUDIT_TestGaps §5.4: the version metadata a map is announced with, the player-metadata
/// merge, the health percent (master only) and the battle round update a player applies.
@MainActor
struct MapSyncMetadataTests {
    private struct Fixture {
        let root: MapRootModel
        let sut: GameController
        let map: MapModel
        let playerPin: MapPinModel
        let monsterPin: MapPinModel
        let playerCharacterId: UUID
        let monsterCharacterId: UUID
    }

    private func makeFixture() async throws -> Fixture {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let playerCharacterId = UUID()
        let monsterCharacterId = UUID()
        root.characterRoot.itemController.replace(model: ValueModel(id: playerCharacterId, name: "Hero"), isInsert: true)
        root.characterRoot.itemController.replace(model: ValueModel(id: monsterCharacterId, name: "Goblin"), isInsert: true)
        let room = MapEntryModel(
            id: UUID(),
            name: "Room",
            content: "A damp cellar",
            coordinates: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)],
            focused: true
        )
        let playerPin = MapPinModel(id: UUID(), name: "Hero", characterId: playerCharacterId, location: CGPoint(x: 20, y: 20), isPlayer: true)
        let monsterPin = MapPinModel(id: UUID(), name: "Goblin", characterId: monsterCharacterId, location: CGPoint(x: 60, y: 60))
        let map = MapModel(id: UUID(), name: "Dungeon", entries: [room], mapPins: [playerPin, monsterPin])
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: map.id)
        return Fixture(
            root: root, sut: sut, map: map, playerPin: playerPin, monsterPin: monsterPin,
            playerCharacterId: playerCharacterId, monsterCharacterId: monsterCharacterId
        )
    }

    // MARK: - Envelope and version metadata

    @Test("The map envelope carries the id, the map type and the three versions as given")
    func envelopeCarriesTheGeneration() {
        let id = UUID()
        let generation = MapGameModel.AuthoritativeGeneration(version: 7, assetVersion: 8, contentVersion: 9)
        let payload = Data([1, 2, 3])

        let withData = GameController.mapNetworkData(id: id, generation: generation, data: payload)
        let reference = GameController.mapNetworkData(id: id, generation: generation, data: nil)

        #expect(withData.id == id)
        #expect(withData.type == .map)
        #expect(withData.version == 7)
        #expect(withData.assetVersion == 8)
        #expect(withData.contentVersion == 9)
        #expect(withData.data == payload)
        #expect(reference.data == nil)
        #expect(reference.version == 7)
    }

    @Test("An unchanged map keeps its metadata, and the stable metadata equals the live one")
    func unchangedMapKeepsItsVersions() async throws {
        let fixture = try await makeFixture()
        let id = fixture.map.id

        let first = try #require(await fixture.sut.stablePackageMetadata(for: id))
        let second = try #require(await fixture.sut.stablePackageMetadata(for: id))
        let core = fixture.sut.packageCoreMetadata(for: id)

        #expect(first == second)
        #expect(core.version == first.version)
        #expect(core.contentVersion == first.contentVersion)
        #expect(fixture.sut.currentMapAssetVersion(for: id) == first.assetVersion)
        #expect(fixture.sut.mapContentVersion(for: id) == first.contentVersion)
    }

    @Test("Two copies of the same map content have the same content version")
    func sameContentSameContentVersion() async throws {
        let fixture = try await makeFixture()

        let version = MapUpdatePayload.contentVersion(of: fixture.map)
        let copyVersion = MapUpdatePayload.contentVersion(of: fixture.map.copy())

        #expect(version == copyVersion)
    }

    @Test("Structure changes the content version; a pin's runtime state does not")
    func contentVersionIgnoresRuntimePinState() async throws {
        let fixture = try await makeFixture()
        let id = fixture.map.id
        let before = try #require(await fixture.sut.stablePackageMetadata(for: id))
        let live = fixture.sut.gameItem(for: id)

        // Position, visibility, health and highlight travel with the map state, not the content.
        live.mapPins[1].location = CGPoint(x: 90, y: 90)
        live.mapPins[1].isShown = false
        live.mapPins[1].healthPercent = 10
        live.mapPins[1].isHighlighted = true
        live.mapPins[1].timeInterval += 5
        let afterRuntime = try #require(await fixture.sut.stablePackageMetadata(for: id))
        #expect(afterRuntime.contentVersion == before.contentVersion)

        // A renamed pin, a renamed room and a new pin are structure.
        live.mapPins[1].name = "Orc"
        let afterPinName = try #require(await fixture.sut.stablePackageMetadata(for: id))
        live.entries[0].name = "Flooded cellar"
        let afterRename = try #require(await fixture.sut.stablePackageMetadata(for: id))
        live.mapPins.append(MapPinModel(id: UUID(), name: "Chest"))
        let afterNewPin = try #require(await fixture.sut.stablePackageMetadata(for: id))

        let versions = [before.contentVersion, afterPinName.contentVersion, afterRename.contentVersion, afterNewPin.contentVersion]
        #expect(Set(versions).count == 4)
        // The background photo did not change, so the asset version stays.
        #expect(Set([before.assetVersion, afterPinName.assetVersion, afterRename.assetVersion, afterNewPin.assetVersion]).count == 1)
    }

    @Test("Content that stays hidden from the players still changes the content version")
    func hiddenEditsStillRegister() async throws {
        let fixture = try await makeFixture()
        let id = fixture.map.id
        let live = fixture.sut.gameItem(for: id)
        live.entries[0].isShown = false
        let before = fixture.sut.mapContentVersion(for: id)

        live.entries[0].content = "The treasure is under the third stone"

        #expect(fixture.sut.mapContentVersion(for: id) != before, "a later reveal must register as a change")
    }

    @Test("The same map exports the same content and announces the captured generation")
    func contentCaptureIsDeterministic() async throws {
        let fixture = try await makeFixture()
        let id = fixture.map.id

        let first = fixture.sut.mapContentCapture(for: id)
        let second = fixture.sut.mapContentCapture(for: id)

        #expect(first.core == second.core)
        let firstPayload = try #require(MapUpdatePayload.decodeData(of: first.data))
        let secondPayload = try #require(MapUpdatePayload.decodeData(of: second.data))
        #expect(firstPayload.contentVersion == secondPayload.contentVersion)
        #expect(firstPayload.contentVersion == first.core.contentVersion)
        #expect(firstPayload.isSupported)
        // The bytes are not compared: redacting the notes stamps a new CRDT clock on every export,
        // so equal content does not give equal bytes (recorded in CODE_AUDIT_TestGaps §5.4).
        #expect(firstPayload.snapshot.id == secondPayload.snapshot.id)
        #expect(firstPayload.snapshot.entries.wrappedValue.map(\.id) == secondPayload.snapshot.entries.wrappedValue.map(\.id))
        #expect(firstPayload.snapshot.mapPins.wrappedValue.map(\.id) == secondPayload.snapshot.mapPins.wrappedValue.map(\.id))

        let update = await fixture.sut.networkMapContentUpdate(for: id)
        #expect(update.contentVersion == first.core.contentVersion)
        #expect(update.version == first.core.version)
        #expect(update.data != nil)
    }

    @Test("The players' payload leaves out the notes, hidden room texts and hidden pins")
    func payloadIsRedactedButKeepsTheVersionOfTheTruth() async throws {
        let fixture = try await makeFixture()
        let id = fixture.map.id
        let live = fixture.sut.gameItem(for: id)
        live.description = "Secret: the baron did it"
        live.entries[0].isShown = false
        live.mapPins[1].isShown = false
        let capture = fixture.sut.mapContentCapture(for: id)

        let payload = try #require(MapUpdatePayload.decodeData(of: capture.data))

        #expect(payload.snapshot.description.wrappedValue.isEmpty)
        #expect(payload.snapshot.entries.wrappedValue.first?.content.isEmpty == true)
        #expect(!payload.snapshot.mapPins.wrappedValue.contains { $0.id == fixture.monsterPin.id })
        // The version is the one of the unredacted map, so a later reveal still counts as a change.
        #expect(capture.core.contentVersion == MapUpdatePayload.contentVersion(of: live))
        live.entries[0].isShown = true
        #expect(MapUpdatePayload.contentVersion(of: live) != capture.core.contentVersion)
    }

    @Test("The background photo and the map id decide the asset version")
    func assetVersionFollowsThePhotoAndTheMap() {
        let mapId = UUID()
        let photoId = UUID()

        let base = MapAssetFingerprint(mapId: mapId, backgroundPhotoId: photoId, backgroundPhotoVersion: 1).version
        let same = MapAssetFingerprint(mapId: mapId, backgroundPhotoId: photoId, backgroundPhotoVersion: 1).version
        let newPhotoVersion = MapAssetFingerprint(mapId: mapId, backgroundPhotoId: photoId, backgroundPhotoVersion: 2).version
        let otherPhoto = MapAssetFingerprint(mapId: mapId, backgroundPhotoId: UUID(), backgroundPhotoVersion: 1).version
        let noPhoto = MapAssetFingerprint(mapId: mapId, backgroundPhotoId: nil, backgroundPhotoVersion: nil).version
        let otherMap = MapAssetFingerprint(mapId: UUID(), backgroundPhotoId: photoId, backgroundPhotoVersion: 1).version

        #expect(base == same)
        #expect(Set([base, newPhotoVersion, otherPhoto, noPhoto, otherMap]).count == 5)
    }

    // MARK: - Authoritative generation

    @Test("A recorded generation is what the map announces, and a reshow of an unedited map keeps it")
    func authoritativeGenerationWins() async throws {
        let fixture = try await makeFixture()
        let id = fixture.map.id
        let announced = GameController.mapNetworkData(
            id: id,
            generation: MapGameModel.AuthoritativeGeneration(version: 11, assetVersion: 22, contentVersion: 33),
            data: nil
        )

        fixture.sut.recordAuthoritativeMapGeneration(announced)

        let generation = fixture.sut.networkGeneration(for: id)
        #expect(generation == MapGameModel.AuthoritativeGeneration(version: 11, assetVersion: 22, contentVersion: 33))
        #expect(await fixture.sut.mapAssetVersion(for: id) == 22)
    }

    @Test("Without a recorded generation the live map decides; recording one without versions forgets it")
    func liveGenerationIsTheFallback() async throws {
        let fixture = try await makeFixture()
        let id = fixture.map.id
        let live = fixture.sut.networkGeneration(for: id)
        #expect(live.contentVersion == fixture.sut.mapContentVersion(for: id))
        #expect(live.assetVersion == fixture.sut.currentMapAssetVersion(for: id))

        fixture.sut.recordAuthoritativeMapGeneration(GameController.mapNetworkData(
            id: id, generation: .init(version: 1, assetVersion: 2, contentVersion: 3), data: nil
        ))
        #expect(fixture.sut.networkGeneration(for: id).contentVersion == 3)

        // A map announcement from an older sender carries no asset/content version.
        fixture.sut.recordAuthoritativeMapGeneration(NetworkCodableDataType(id: id, type: .map, version: 5, data: nil))

        #expect(fixture.sut.networkGeneration(for: id) == live)
    }

    @Test("Refreshing the content fingerprint keeps the recorded version and asset version")
    func refreshKeepsTheRestOfTheGeneration() async throws {
        let fixture = try await makeFixture()
        let id = fixture.map.id
        fixture.sut.recordAuthoritativeMapGeneration(GameController.mapNetworkData(
            id: id, generation: .init(version: 11, assetVersion: 22, contentVersion: 33), data: nil
        ))

        fixture.sut.refreshAuthoritativeMapContentVersion(for: id)

        let refreshed = fixture.sut.networkGeneration(for: id)
        #expect(refreshed.assetVersion == 22)
        #expect(refreshed.contentVersion == fixture.sut.mapContentVersion(for: id))
        #expect(refreshed.version == fixture.sut.gameItem(for: id).version)
    }

    @Test("A payload is current only when all six conditions hold")
    func currentGenerationNeedsEveryCondition() async throws {
        let fixture = try await makeFixture()
        let id = fixture.map.id
        let generation = fixture.sut.networkGeneration(for: id)
        func payload(
            id: UUID = id,
            type: NetworkModules = .map,
            version: Int? = nil,
            asset: Int? = nil,
            content: Int? = nil
        ) -> NetworkCodableDataType {
            NetworkCodableDataType(
                id: id, type: type, version: version ?? generation.version, data: nil,
                assetVersion: asset ?? generation.assetVersion, contentVersion: content ?? generation.contentVersion
            )
        }

        #expect(fixture.sut.isCurrentGeneration(payload(), for: id))
        #expect(!fixture.sut.isCurrentGeneration(payload(id: UUID()), for: id), "another map")
        #expect(!fixture.sut.isCurrentGeneration(payload(type: .photo), for: id), "another item type")
        #expect(!fixture.sut.isCurrentGeneration(payload(version: generation.version + 1), for: id))
        #expect(!fixture.sut.isCurrentGeneration(payload(asset: generation.assetVersion + 1), for: id))
        #expect(!fixture.sut.isCurrentGeneration(payload(content: generation.contentVersion + 1), for: id))
        let otherMap = UUID()
        #expect(!fixture.sut.isCurrentGeneration(payload(id: otherMap), for: otherMap), "not the map being shown")
    }

    // MARK: - Player metadata

    @Test("Player metadata replaces identity and keeps position, health and highlight")
    func playerMetadataKeepsRuntimeState() {
        let characterId = UUID()
        let photoId = UUID()
        let controller = UUID()
        let source = MapPinModel(
            id: UUID(), name: "Anna", color: .blue, photoId: photoId, characterId: characterId,
            location: CGPoint(x: 1, y: 1), isPlayer: true, players: [controller], healthPercent: 100
        )
        var destination = MapPinModel(
            id: UUID(), name: "Old", color: .red, location: CGPoint(x: 300, y: 400),
            timeInterval: 42, isDead: true, isHighlighted: true, healthPercent: 25, mapId: UUID()
        )
        let place = destination.location
        let time = destination.timeInterval
        let mapId = destination.mapId

        GameController.applyPlayerMetadata(from: source, to: &destination)

        #expect(destination.name == "Anna")
        #expect(destination.color == .blue)
        #expect(destination.photoId == photoId)
        #expect(destination.characterId == characterId)
        #expect(destination.players == [controller])
        #expect(destination.isPlayer)
        #expect(destination.location == place)
        #expect(destination.healthPercent == 25, "metadata must not write the health percent")
        #expect(destination.isHighlighted)
        #expect(destination.isDead)
        #expect(destination.timeInterval == time)
        #expect(destination.mapId == mapId)
    }

    @Test("A Character package arriving later updates the player pin on every map without moving it")
    func lateCharacterPackageRefreshesTheMapPin() async throws {
        let fixture = try await makeFixture()
        let playerId = UUID()
        let characterId = UUID()
        let live = fixture.sut.gameItem(for: fixture.map.id)
        fixture.sut.setPlayerPin(for: playerId, name: "Anna", characterId: UUID())
        fixture.sut.synchronizePlayerPins(for: fixture.map.id)
        let index = try #require(live.mapPins.firstIndex { $0.id == playerId })
        live.mapPins[index].location = CGPoint(x: 77, y: 88)

        fixture.sut.setPlayerPin(for: playerId, name: "Anna", characterId: characterId)

        let pin = try #require(live.mapPins.first { $0.id == playerId })
        #expect(pin.characterId == characterId)
        #expect(pin.location == CGPoint(x: 77, y: 88))
    }

    // MARK: - Health percent

    /// The monster's Character gets a hit-points entry, so a battle resolves a health percent.
    private func giveMonsterHitPoints(_ fixture: Fixture, value: String) throws -> ValueEntryModel {
        let entry = ValueEntryModel(id: UUID(), name: "HP", type: .number, value: value)
        let character = try #require(fixture.root.characterRoot.itemController.itemDataModel.itemData[fixture.monsterCharacterId] as? ValueModel)
        character.entries = [entry]
        fixture.sut.battleRoundSettings.hitPointsNames = ["HP"]
        return entry
    }

    @Test("Health of a combatant without a Character or hit-points entry is unknown, not zero")
    func healthWithoutSourcesIsNil() async throws {
        let fixture = try await makeFixture()
        let noCharacter = BattleCombatant(pin: fixture.monsterPin, sourceCharacterId: nil, gameCharacterId: nil)
        let noEntry = BattleCombatant(pin: fixture.monsterPin, sourceCharacterId: fixture.monsterCharacterId, gameCharacterId: fixture.monsterCharacterId)
        var missingEntry = noEntry
        let missingId = UUID()
        missingEntry.hitPointsEntryId = missingId

        #expect(fixture.sut.battleHealth(for: noCharacter) == .noCharacter)
        #expect(fixture.sut.battleHealth(for: noEntry) == .noHitPointsEntry)
        #expect(fixture.sut.battleHealth(for: missingEntry) == .entryNotFound(missingId))
        #expect(fixture.sut.healthPercent(for: noCharacter) == nil)
    }

    @Test("Hit points are base and modifier, as a percent of the base clamped to 0...100")
    func healthIsBaseAndModifier() async throws {
        let fixture = try await makeFixture()
        let entry = try giveMonsterHitPoints(fixture, value: "20|-5")
        var combatant = BattleCombatant(pin: fixture.monsterPin, sourceCharacterId: fixture.monsterCharacterId, gameCharacterId: fixture.monsterCharacterId)
        combatant.hitPointsEntryId = entry.id
        let character = try #require(fixture.root.characterRoot.itemController.itemDataModel.itemData[fixture.monsterCharacterId] as? ValueModel)
        #expect(fixture.sut.battleHealth(for: combatant) == .percent(75))

        character.entries[0].value = "20|-50"
        #expect(fixture.sut.battleHealth(for: combatant) == .percent(0), "below zero is clamped")
        character.entries[0].value = "20|10"
        #expect(fixture.sut.battleHealth(for: combatant) == .percent(100), "above the maximum is clamped")
        character.entries[0].value = "free text"
        guard case .notCalculable = fixture.sut.battleHealth(for: combatant) else {
            Issue.record("free text has no positive numeric base")
            return
        }
    }

    @Test("Only the game master writes the health percent of a pin")
    func playerNeverWritesHealthPercent() async throws {
        let fixture = try await makeFixture()
        let id = fixture.map.id
        _ = try giveMonsterHitPoints(fixture, value: "20|-15")
        #expect(fixture.sut.startBattle(itemId: id))
        let live = fixture.sut.gameItem(for: id)
        let index = try #require(live.mapPins.firstIndex { $0.id == fixture.monsterPin.id })
        #expect(live.mapPins[index].healthPercent == 25)
        // The master's broadcast said 80; the player's own device must keep it.
        live.mapPins[index].healthPercent = 80
        live.mapPins[index].isHighlighted = true

        let player = fixture.sut.synchronizeBattleDefenders(itemId: id, isGameMaster: false)

        #expect(player.changed == false)
        #expect(player.healthChanged == false)
        #expect(live.mapPins[index].healthPercent == 80, "a player's sync must not overwrite the master's value")

        let master = fixture.sut.synchronizeBattleDefenders(itemId: id, isGameMaster: true)
        #expect(master.healthChanged)
        #expect(live.mapPins[index].healthPercent == 25)

        let repeated = fixture.sut.synchronizeBattleDefenders(itemId: id, isGameMaster: true)
        #expect(repeated.healthChanged == false, "an unchanged health must not rewrite the pin")
    }

    // MARK: - Pin timestamps and library copies

    @Test("A pin mutation always gets a newer timestamp, also against a clock in the past")
    func mutationTimestampsAreMonotonic() async throws {
        let fixture = try await makeFixture()
        let id = fixture.map.id
        let live = fixture.sut.gameItem(for: id)
        let index = try #require(live.mapPins.firstIndex { $0.id == fixture.monsterPin.id })
        let future = Date.now.timeIntervalSince1970 + 10_000
        live.mapPins[index].timeInterval = future

        let pin = try #require(fixture.sut.mutatedPinState(itemId: id, pinId: fixture.monsterPin.id) { $0.isDead = true })

        #expect(pin.isDead)
        #expect(pin.timeInterval > future)
        #expect(GameController.bumpedTimeInterval(from: 5) >= Date.now.timeIntervalSince1970 - 1)
        #expect(fixture.sut.mutatedPinState(itemId: id, pinId: UUID()) { _ in } == nil)
        #expect(!fixture.sut.updatePinState(itemId: id, pinId: UUID()) { _ in })
    }

    @Test("A moved pin now stands on the map it was moved on")
    func movedPinTakesTheMapId() async throws {
        let fixture = try await makeFixture()
        let id = fixture.map.id
        let live = fixture.sut.gameItem(for: id)
        let index = try #require(live.mapPins.firstIndex { $0.id == fixture.monsterPin.id })
        live.mapPins[index].mapId = UUID()

        let untouched = fixture.sut.mutatedPinState(itemId: id, pinId: fixture.monsterPin.id) { $0.isDead = false }
        let moved = fixture.sut.mutatedPinState(itemId: id, pinId: fixture.monsterPin.id) { $0.location = CGPoint(x: 5, y: 5) }

        #expect(untouched?.mapId != id)
        #expect(moved?.mapId == id)
    }

    @Test("Library pins drop session pins and point battle clones back at their source")
    func libraryPinsRestoreSources() {
        let cloneId = UUID()
        let sourceId = UUID()
        let player = MapPinModel(id: UUID(), name: "Hero", isPlayer: true)
        let monster = MapPinModel(id: UUID(), name: "Goblin", characterId: cloneId)
        let marker = MapPinModel(id: UUID(), name: "Marker", characterId: UUID())

        let pins = GameController.libraryPins(of: [player, monster, marker], sources: [cloneId: sourceId])

        #expect(pins.map(\.id) == [monster.id, marker.id])
        #expect(pins[0].characterId == sourceId)
        #expect(pins[1].characterId == marker.characterId)
    }

    @Test("Map state booleans accept only true and false")
    func mapStateBooleans() {
        #expect(GameController.mapStateBool("true") == true)
        #expect(GameController.mapStateBool("false") == false)
        #expect(GameController.mapStateBool("True") == nil)
        #expect(GameController.mapStateBool("1") == nil)
        #expect(GameController.mapStateBool("") == nil)
    }

    // MARK: - Battle round update

    private func startedBattle() async throws -> (Fixture, GameController) {
        let master = try await makeFixture()
        #expect(master.sut.startBattle(itemId: master.map.id))
        return (master, master.sut)
    }

    /// A player's device: the same map shown, with the master's announced generation recorded.
    private func playerDevice(for master: Fixture) async throws -> GameController {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let player = root.gameController
        player.setGame(item: master.map.copy(), itemId: master.map.id)
        let announced = GameController.mapNetworkData(
            id: master.map.id, generation: master.sut.networkGeneration(for: master.map.id), data: nil
        )
        player.recordAuthoritativeMapGeneration(announced)
        return player
    }

    @Test("A player applies the master's round advance and ignores an older or repeated update")
    func playerFollowsTheRoundAdvance() async throws {
        let (master, masterController) = try await startedBattle()
        let id = master.map.id
        let player = try await playerDevice(for: master)
        let first = try #require(masterController.networkBattleRoundUpdate(for: id))
        #expect(player.applyBattleRoundUpdate(for: id, with: first))
        #expect(player.battleRoundModel.isRunning)
        let firstSequence = player.battleRoundModel.networkSequence

        // The master advances the round and announces it.
        #expect(masterController.battleRoundModel.nextRound())
        let advanced = try #require(masterController.networkBattleRoundUpdate(for: id))
        let advancedState = try #require(BattleRoundNetworkState.decodeData(of: advanced.data))

        #expect(player.applyBattleRoundUpdate(for: id, with: advanced))
        #expect(player.battleRoundModel.roundCounter == advancedState.roundCounter)
        #expect(player.battleRoundModel.networkSequence > firstSequence)
        #expect(player.battleRoundModel.presentedActivePinId == advancedState.activePinId)

        // The same update again, and the one before it, change nothing.
        #expect(!player.applyBattleRoundUpdate(for: id, with: advanced))
        #expect(!player.applyBattleRoundUpdate(for: id, with: first))
        #expect(player.battleRoundModel.roundCounter == advancedState.roundCounter)
    }

    @Test("A round update of another map generation is refused and changes nothing")
    func staleGenerationIsRefused() async throws {
        let (master, masterController) = try await startedBattle()
        let id = master.map.id
        let player = try await playerDevice(for: master)
        let update = try #require(masterController.networkBattleRoundUpdate(for: id))
        let stale = NetworkCodableDataType(
            id: update.id, type: .map, version: update.version, data: update.data,
            assetVersion: update.assetVersion, contentVersion: (update.contentVersion ?? 0) + 1
        )

        #expect(!player.applyBattleRoundUpdate(for: id, with: stale))
        #expect(!player.battleRoundModel.isRunning)
        #expect(player.battleRoundModel.networkSequence == 0)
    }

    @Test("A round update without a payload, or for another map, is refused")
    func malformedRoundUpdateIsRefused() async throws {
        let (master, masterController) = try await startedBattle()
        let id = master.map.id
        let player = try await playerDevice(for: master)
        let update = try #require(masterController.networkBattleRoundUpdate(for: id))
        let withoutData = NetworkCodableDataType(
            id: id, type: .map, version: update.version, data: nil,
            assetVersion: update.assetVersion, contentVersion: update.contentVersion
        )
        let otherMapState = BattleRoundNetworkState(mapId: UUID(), isRunning: true, roundCounter: 3, activePinId: nil, sequence: 9)
        let otherMap = NetworkCodableDataType(
            id: id, type: .map, version: update.version, data: otherMapState.encodeData(),
            assetVersion: update.assetVersion, contentVersion: update.contentVersion
        )

        #expect(!player.applyBattleRoundUpdate(for: id, with: withoutData))
        #expect(!player.applyBattleRoundUpdate(for: id, with: otherMap))
        #expect(!player.battleRoundModel.isRunning)
    }

    @Test("A hidden pin on its turn is not named in the update for the players")
    func hiddenActivePinIsNotNamed() async throws {
        let (master, masterController) = try await startedBattle()
        let id = master.map.id
        let live = masterController.gameItem(for: id)
        live.entries[0].isShown = true
        let monster = try #require(masterController.battleRoundModel.combatant(pinId: master.monsterPin.id))
        #expect(masterController.activateBattleAttacker(itemId: id, combatantId: monster.id))
        let visible = try #require(masterController.networkBattleRoundUpdate(for: id))
        #expect(BattleRoundNetworkState.decodeData(of: visible.data)?.activePinId == master.monsterPin.id)

        let index = try #require(live.mapPins.firstIndex { $0.id == master.monsterPin.id })
        live.mapPins[index].isShown = false
        let hidden = try #require(masterController.networkBattleRoundUpdate(for: id))
        let state = try #require(BattleRoundNetworkState.decodeData(of: hidden.data))

        #expect(state.activePinId == nil)
        #expect(state.isRunning)
        #expect(state.roundCounter == BattleRoundNetworkState.decodeData(of: visible.data)?.roundCounter)
    }

    @Test("There is no round update for a map without a battle")
    func noBattleNoUpdate() async throws {
        let fixture = try await makeFixture()

        #expect(fixture.sut.networkBattleRoundUpdate(for: fixture.map.id) == nil)
        #expect(fixture.sut.networkBattleRoundUpdate(for: UUID()) == nil)
    }
}
#endif
