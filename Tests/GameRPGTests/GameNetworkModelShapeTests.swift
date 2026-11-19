// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_TestGaps §5.15: what a message is follows from its shape alone
/// (`GameNetworkModel+Shape`). Both controllers and the transports decide with these predicates,
/// so each is pinned here with the shapes that must pass and the near misses that must not.
@Suite("Game message shape")
struct GameNetworkModelShapeTests {
    private func message(
        _ type: RPGMessageType,
        _ subType: RPGMessageActionType,
        module: NetworkModules,
        bytes: Int? = nil,
        from role: GameType = .player,
        targetId: UUID? = nil,
        timestamp: TimeInterval = Date.now.timeIntervalSince1970
    ) -> GameNetworkModel {
        GameNetworkModel(
            timestamp: timestamp,
            counter: 1,
            proxyCounter: 0,
            type: type,
            subType: subType,
            masterId: UUID(),
            sender: GameSenderModel(id: UUID(), role: role, name: "Sender", characterId: nil),
            targetId: targetId,
            data: NetworkCodableDataType(
                id: UUID(), type: module, version: 3,
                data: bytes.map { Data(count: $0) },
                assetVersion: 5, contentVersion: 7
            )
        )
    }

    // MARK: - Timestamps

    @Test("An event timestamp must be finite, positive and not far in the future")
    func timestampPolicy() {
        let now: TimeInterval = 1_700_000_000
        let skew = GameNetworkModel.maximumFutureEventTimestampSkew

        #expect(GameNetworkModel.acceptsEventTimestamp(now, now: now))
        #expect(GameNetworkModel.acceptsEventTimestamp(now + skew, now: now), "exactly at the limit")
        #expect(!GameNetworkModel.acceptsEventTimestamp(now + skew + 1, now: now))
        #expect(GameNetworkModel.acceptsEventTimestamp(1, now: now), "any past time")
        #expect(!GameNetworkModel.acceptsEventTimestamp(0, now: now))
        #expect(!GameNetworkModel.acceptsEventTimestamp(-5, now: now))
        #expect(!GameNetworkModel.acceptsEventTimestamp(.nan, now: now))
        #expect(!GameNetworkModel.acceptsEventTimestamp(.infinity, now: now))
        #expect(!GameNetworkModel.acceptsEventTimestamp(-.infinity, now: now))
    }

    // MARK: - Acknowledgements and lists

    @Test("Only ok and failed are acknowledgements", arguments: [
        (RPGMessageActionType.ok, true), (.failed, true), (.show, false), (.generic, false), (.audioList, false)
    ])
    func acknowledgement(subType: RPGMessageActionType, expected: Bool) {
        #expect(message(.update, subType, module: .audio).isAcknowledgement == expected)
    }

    @Test("A report list needs its own module's item type and the update type", arguments: [
        (RPGMessageActionType.audioList, NetworkModules.audio, true),
        (.photoList, .photo, true),
        (.pdfList, .pdf, true),
        (.spaceList, .space, true),
        (.audioList, .photo, false),
        (.photoList, .audio, false),
        (.pdfList, .map, false),
        (.spaceList, .none, false),
        (.show, .audio, false)
    ])
    func reportListEnvelope(subType: RPGMessageActionType, module: NetworkModules, expected: Bool) {
        #expect(message(.update, subType, module: module).isReportListEnvelope == expected)
    }

    @Test("A list action paired with another message type is not a report list envelope")
    func reportListNeedsUpdateType() {
        #expect(!message(.reveal, .audioList, module: .audio).isReportListEnvelope)
        #expect(!message(.store, .photoList, module: .photo).isReportListEnvelope)
        // The subtype alone still says "a list".
        #expect(message(.reveal, .audioList, module: .audio).isReportList)
        #expect(!message(.update, .show, module: .audio).isReportList)
    }

    // MARK: - Asset requests

    @Test("A player's echo of a reveal or store without bytes is an asset request", arguments: [
        NetworkModules.audio, .dice, .map, .pdf, .photo, .space, .table, .weather
    ])
    func assetRequest(module: NetworkModules) {
        #expect(message(.reveal, .show, module: module).isAssetRequest)
        #expect(message(.store, .store, module: module).isAssetRequest)
    }

    @Test("Near misses of an asset request")
    func assetRequestNearMisses() {
        #expect(!message(.reveal, .show, module: .photo, bytes: 4).isAssetRequest, "it carries bytes")
        #expect(!message(.reveal, .show, module: .photo, from: .master).isAssetRequest, "the master does not request")
        #expect(!message(.update, .show, module: .photo).isAssetRequest)
        #expect(!message(.reveal, .generic, module: .photo).isAssetRequest)
        #expect(!message(.reveal, .show, module: .adventure).isAssetRequest, "an adventure has no asset")
        #expect(!message(.reveal, .show, module: .value).isAssetRequest)
    }

    // MARK: - Group events

    @Test("A complete dice roll is a group event of kind diceRoll")
    func diceRoll() {
        let roll = message(.update, .generic, module: .dice, bytes: 64)

        #expect(roll.isDiceRollEvent)
        #expect(roll.groupEventKind == .diceRoll)
        #expect(roll.isPlayerGroupEvent)
    }

    @Test("A dice message is not a roll without bytes, with a target or with another subtype")
    func diceRollNearMisses() {
        #expect(!message(.update, .generic, module: .dice).isDiceRollEvent)
        #expect(!message(.update, .generic, module: .dice, bytes: 64, targetId: UUID()).isDiceRollEvent)
        #expect(!message(.update, .show, module: .dice, bytes: 64).isDiceRollEvent)
        #expect(!message(.reveal, .generic, module: .dice, bytes: 64).isDiceRollEvent)
        #expect(!message(.update, .generic, module: .map, bytes: 64).isDiceRollEvent)
    }

    @Test("Map pins and Space transforms are group events by module and subtype")
    func otherGroupEvents() {
        #expect(message(.update, .mapPin, module: .map, bytes: 10).groupEventKind == .mapPin)
        #expect(message(.update, .spaceTransform, module: .space, bytes: 10).groupEventKind == .spaceTransform)
        #expect(message(.update, .mapPin, module: .space, bytes: 10).groupEventKind == nil)
        #expect(message(.update, .spaceTransform, module: .map, bytes: 10).groupEventKind == nil)
        #expect(message(.reveal, .mapPin, module: .map, bytes: 10).groupEventKind == nil)
        #expect(message(.update, .show, module: .map, bytes: 10).groupEventKind == nil)
    }

    @Test("A player group event is limited by payload size, role, target and clock")
    func playerGroupEventLimits() {
        let limit = GameLimits.maximumGroupEventPayloadBytes
        let now = Date.now.timeIntervalSince1970

        #expect(message(.update, .mapPin, module: .map, bytes: limit).isPlayerGroupEvent, "exactly at the limit")
        #expect(!message(.update, .mapPin, module: .map, bytes: limit + 1).isPlayerGroupEvent)
        #expect(!message(.update, .mapPin, module: .map).isPlayerGroupEvent, "no payload")
        #expect(!message(.update, .mapPin, module: .map, bytes: 10, from: .master).isPlayerGroupEvent)
        #expect(!message(.update, .mapPin, module: .map, bytes: 10, targetId: UUID()).isPlayerGroupEvent)
        #expect(!message(.update, .mapPin, module: .map, bytes: 10, timestamp: now + 3_600).isPlayerGroupEvent, "clock far ahead")
        #expect(!message(.update, .mapPin, module: .map, bytes: 10, timestamp: 0).isPlayerGroupEvent)
        #expect(!message(.update, .show, module: .map, bytes: 10).isPlayerGroupEvent, "not a group event kind")
    }

    // MARK: - Presentation

    @Test("A reveal of a showable module from the master is a presentation", arguments: [
        NetworkModules.map, .photo, .pdf, .space, .table, .weather, .none
    ])
    func presentation(module: NetworkModules) {
        #expect(message(.reveal, .show, module: module, from: .master).isPresentation)
        #expect(!message(.reveal, .show, module: module, from: .player).isPresentation)
    }

    @Test("Audio, dice and adventure reveals are no presentation, a map state update is")
    func presentationNearMisses() {
        #expect(!message(.reveal, .show, module: .audio, from: .master).isPresentation)
        #expect(!message(.reveal, .show, module: .dice, from: .master).isPresentation)
        #expect(!message(.reveal, .show, module: .adventure, from: .master).isPresentation)
        #expect(message(.update, .mapState, module: .map, from: .master).isPresentation)
        #expect(!message(.update, .mapState, module: .photo, from: .master).isPresentation)
        #expect(!message(.update, .mapState, module: .map, from: .player).isPresentation)
        #expect(!message(.store, .show, module: .map, from: .master).isPresentation)
    }

    // MARK: - Assets

    @Test("Only the file-backed modules carry an asset, and only with bytes", arguments: [
        (NetworkModules.pdf, true), (.audio, true), (.space, true), (.photo, true), (.map, true), (.weather, true),
        (.dice, false), (.table, false), (.value, false), (.adventure, false)
    ])
    func dataCarriesAsset(module: NetworkModules, expected: Bool) {
        let withBytes = NetworkCodableDataType(id: UUID(), type: module, version: 1, data: Data([1]))
        let reference = NetworkCodableDataType(id: UUID(), type: module, version: 1)

        #expect(withBytes.carriesAsset == expected)
        #expect(!reference.carriesAsset)
    }

    @Test("A reveal or store carries the asset, an update only when it is not a map or weather event")
    func messageCarriesAsset() {
        #expect(message(.reveal, .show, module: .photo, bytes: 4).carriesAsset)
        #expect(message(.store, .store, module: .pdf, bytes: 4).carriesAsset)
        #expect(message(.update, .generic, module: .space, bytes: 4).carriesAsset, "a player's file contribution")
        #expect(!message(.update, .generic, module: .weather, bytes: 4).carriesAsset, "a lightning strike")
        #expect(!message(.update, .generic, module: .map, bytes: 4).carriesAsset)
        #expect(!message(.reveal, .show, module: .photo).carriesAsset, "no bytes")
        #expect(!message(.reveal, .show, module: .dice, bytes: 4).carriesAsset)
    }

    @Test("A reference keeps the item and its versions and drops the bytes")
    func referenceDropsTheBytes() {
        let data = NetworkCodableDataType(id: UUID(), type: .photo, version: 3, data: Data([1, 2]), assetVersion: 5, contentVersion: 7)

        let reference = data.reference

        #expect(reference.data == nil)
        #expect(reference.id == data.id)
        #expect(reference.type == .photo)
        #expect(reference.version == 3)
        #expect(reference.assetVersion == 5)
        #expect(reference.contentVersion == 7)
    }
}
#endif
