// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// The envelope has one wire format. An envelope of any other generation, the released 2.6
/// app's included, does not decode.
@Suite("GameNetworkModel envelope")
struct GameNetworkModelVersionTests {
    let masterId: UUID
    let playerId: UUID
    let master: MasterGameModel
    let players: [PlayerGameModel]
    let controls: [SharingControlModel]
    let features: GameFeatureModel
    let payload: NetworkCodableDataType

    init() {
        let masterId = UUID()
        let playerId = UUID()
        self.masterId = masterId
        self.playerId = playerId
        master = MasterGameModel(id: masterId, type: .master, name: "Master", adventureId: UUID(), adventureTitle: "Adventure")
        players = [PlayerGameModel(id: playerId, type: .player, name: "Player - 1", characterId: UUID())]
        controls = [SharingControlModel(id: playerId, name: "Player - 1", show: true)]
        features = GameFeatureModel(diceMaster: false, dicePlayers: true, audioSharing: false, photoSharing: true, spaceSharing: false)
        payload = NetworkCodableDataType(id: UUID(), type: .photo, version: 3, data: Data([0x11, 0x22]))
    }

    var masterMessage: GameNetworkModel {
        GameNetworkModel(
            counter: 7,
            proxyCounter: 2,
            type: .reveal,
            subType: .show,
            masterId: masterId,
            sender: GameSenderModel(id: masterId, role: .master, name: "Master", characterId: nil),
            masterState: GameMasterStateModel(state: .started, adventureId: master.adventureId, adventureTitle: master.adventureTitle, players: players, controls: controls, features: features),
            data: payload
        )
    }

    var playerMessage: GameNetworkModel {
        GameNetworkModel(
            counter: 4,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: masterId,
            sender: GameSenderModel(id: playerId, role: .player, name: "Player - 1", characterId: players[0].characterId),
            data: payload
        )
    }

    // MARK: - Wire format

    @Test("A master message keeps every field through encoding")
    func masterMessageRoundTrip() throws {
        // Given
        var message = masterMessage
        message.targetId = playerId
        message.senderPlatform = .visionOS

        // When
        let decoded = try #require(GameNetworkModel.decodeData(of: message.encodeData()))

        // Then
        #expect(decoded.version == GameNetworkModel.currentVersion)
        #expect(decoded.timestamp == message.timestamp)
        #expect(decoded.counter == 7)
        #expect(decoded.proxyCounter == 2)
        #expect(decoded.type == .reveal)
        #expect(decoded.subType == .show)
        #expect(decoded.masterId == masterId)
        #expect(decoded.sender == message.sender)
        #expect(decoded.masterState == message.masterState)
        #expect(decoded.targetId == playerId)
        #expect(decoded.senderPlatform == .visionOS)
        #expect(decoded.data == payload)
    }

    @Test("A player message carries no master state")
    func playerMessageRoundTrip() throws {
        // When
        let decoded = try #require(GameNetworkModel.decodeData(of: playerMessage.encodeData()))

        // Then
        #expect(decoded.sender.role == .player)
        #expect(decoded.sender.id == playerId)
        #expect(decoded.masterState == nil)
        #expect(decoded.targetId == nil)
    }

    @Test("The envelope has exactly the keys of the current format")
    func encodedKeys() throws {
        // When
        let data = try #require(masterMessage.encodeData())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Then
        #expect(Set(object.keys) == [
            "version", "timestamp", "counter", "proxyCounter", "type", "subType",
            "masterId", "sender", "masterState", "data"
        ])
        #expect(object["version"] as? Int == GameNetworkModel.currentVersion)
    }

    @Test("An envelope of the released 2.6 app does not decode")
    func legacyEnvelopeIsRejected() throws {
        // Given: the 2.6 shape, roster and controls inside `gameConfig`, no `sender`.
        let legacy: [String: Any] = [
            "version": 1,
            "counter": 7,
            "proxyCounter": 0,
            "type": RPGMessageType.reveal.rawValue,
            "subType": RPGMessageActionType.show.rawValue,
            "gameConfig": [
                "id": masterId.uuidString,
                "players": [],
                "controls": []
            ],
            "data": ["id": payload.id.uuidString, "type": NetworkModules.photo.rawValue, "version": 3]
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)

        // Then
        #expect(GameNetworkModel.decodeData(of: data) == nil)
    }

    @Test("An envelope stamped with another version does not decode", arguments: [1, 2, 4])
    func otherVersionIsRejected(version: Int) throws {
        // Given
        let data = try #require(masterMessage.encodeData())
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = version

        // When
        let restamped = try JSONSerialization.data(withJSONObject: object)

        // Then
        #expect(GameNetworkModel.decodeData(of: restamped) == nil)
    }

    @Test("A sender platform this version does not know does not drop the message")
    func unknownPlatformIsIgnored() throws {
        // Given
        let data = try #require(playerMessage.encodeData())
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["senderPlatform"] = "watchOS"

        // When
        let decoded = try #require(GameNetworkModel.decodeData(of: try JSONSerialization.data(withJSONObject: object)))

        // Then
        #expect(decoded.senderPlatform == nil)
        #expect(decoded.counter == 4)
    }

    @Test("A sender name longer than the limit is clamped when decoded")
    func senderNameIsClamped() throws {
        // Given
        var message = playerMessage
        message.sender.name = String(repeating: "x", count: GameSenderModel.maxNameLength + 20)

        // When
        let decoded = try #require(GameNetworkModel.decodeData(of: message.encodeData()))

        // Then
        #expect(decoded.sender.name.count == GameSenderModel.maxNameLength)
    }

    // MARK: - Deduplication

    @Test("The reference and the package of one show are different messages")
    func dedupKeySeparatesReferenceFromPackage() {
        // Given
        var reference = masterMessage
        reference.data = payload.reference

        // Then: the package that follows a reference must not be dropped as its duplicate.
        #expect(GameMessageKey(model: reference) != GameMessageKey(model: masterMessage))
    }

    @Test("A repeated delivery of the same message is a duplicate")
    func dedupKeyMatchesRepeatedDelivery() {
        // Given
        var repeated = masterMessage
        repeated.timestamp += 5

        // Then
        #expect(GameMessageKey(model: repeated) == GameMessageKey(model: masterMessage))
    }
}
#endif
