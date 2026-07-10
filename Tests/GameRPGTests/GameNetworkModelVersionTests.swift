// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// Wire-format compatibility between envelope generations:
/// - V1: shipped 2.6 app — players/controls/features inside gameConfig
/// - unreleased dev layouts: slim gameConfig + gameRoster [+ gameControl]
/// - current V2: sender + master-only masterState + optional targetId
@Suite("GameNetworkModel versioning")
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

    var v1MasterMessage: GameNetworkModelV1 {
        GameNetworkModelV1(
            counter: 7,
            proxyCounter: 2,
            type: .reveal,
            subType: .show,
            gameConfig: GameConfigModelV1(id: masterId, state: .started, master: master, players: players, controls: controls, features: features),
            data: payload
        )
    }

    var v1PlayerMessage: GameNetworkModelV1 {
        GameNetworkModelV1(
            counter: 7,
            proxyCounter: 0,
            type: .reveal,
            subType: .ok,
            gameConfig: GameConfigModelV1(id: playerId, state: .started, master: master, players: players, controls: controls, features: features),
            data: payload
        )
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
            counter: 0,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: masterId,
            sender: GameSenderModel(id: playerId, role: .player, name: "Player - 1", characterId: players[0].characterId),
            data: payload
        )
    }

    // MARK: - Receiving old formats

    @Test func decodesV1MasterEnvelopeIntoSenderAndMasterState() throws {
        let v1Data = try JSONEncoder().encode(v1MasterMessage)

        let decoded = try #require(GameNetworkModel.decodeData(of: v1Data))

        #expect(decoded.version == 1)
        #expect(decoded.counter == 7)
        #expect(decoded.masterId == masterId)
        #expect(decoded.sender.id == masterId)
        #expect(decoded.sender.role == .master)
        #expect(decoded.sender.name == "Master")
        let state = try #require(decoded.masterState)
        #expect(state.players == players)
        #expect(state.controls == controls)
        #expect(state.features == features)
        #expect(state.adventureTitle == "Adventure")
        #expect(decoded.data == payload)
        #expect(decoded.senderName == "Master")
    }

    @Test func decodesV1PlayerEnvelopeIntoSenderOnly() throws {
        let v1Data = try JSONEncoder().encode(v1PlayerMessage)

        let decoded = try #require(GameNetworkModel.decodeData(of: v1Data))

        #expect(decoded.masterId == masterId)
        #expect(decoded.sender.id == playerId)
        #expect(decoded.sender.role == .player)
        #expect(decoded.sender.name == "Player - 1")
        #expect(decoded.sender.characterId == players[0].characterId)
        #expect(decoded.masterState == nil)
    }

    @Test func decodesUnreleasedDevLayout() throws {
        // Dev layout: slim gameConfig, gameRoster carries players + controls + features.
        struct DevRoster: Encodable {
            let players: [PlayerGameModel]
            let controls: [SharingControlModel]
            let features: GameFeatureModel
        }
        struct DevEnvelope: Encodable {
            let version: Int
            let counter: Int
            let proxyCounter: Int
            let type: RPGMessageType
            let subType: RPGMessageActionType
            let gameConfig: GameConfigModel
            let gameRoster: DevRoster
            let data: NetworkCodableDataType
        }
        let dev = DevEnvelope(
            version: 1,
            counter: 5,
            proxyCounter: 0,
            type: .update,
            subType: .mapState,
            gameConfig: GameConfigModel(id: masterId, state: .started, master: master),
            gameRoster: DevRoster(players: players, controls: controls, features: features),
            data: payload
        )
        let devData = try JSONEncoder().encode(dev)

        let decoded = try #require(GameNetworkModel.decodeData(of: devData))

        #expect(decoded.sender.role == .master)
        let state = try #require(decoded.masterState)
        #expect(state.players == players)
        #expect(state.controls == controls)
        #expect(state.features == features)
    }

    // MARK: - Sending to old formats

    @Test func encodedMasterMessageIsDecodableByV1Clients() throws {
        let encoded = try #require(masterMessage.encodeData())

        // The strict V1 decoder requires players/controls/features inside
        // gameConfig — exactly what the shipped 2.6 app does.
        let v1Decoded = try JSONDecoder().decode(GameNetworkModelV1.self, from: encoded)

        #expect(v1Decoded.counter == 7)
        #expect(v1Decoded.gameConfig.id == masterId)
        #expect(v1Decoded.gameConfig.master.id == masterId)
        #expect(v1Decoded.gameConfig.master.name == "Master")
        #expect(v1Decoded.gameConfig.players == players)
        #expect(v1Decoded.gameConfig.controls == controls)
        #expect(v1Decoded.gameConfig.features == features)
        #expect(v1Decoded.data == payload)
    }

    @Test func encodedPlayerMessageIsDecodableByV1Clients() throws {
        let encoded = try #require(playerMessage.encodeData())

        let v1Decoded = try JSONDecoder().decode(GameNetworkModelV1.self, from: encoded)

        #expect(v1Decoded.gameConfig.id == playerId)
        #expect(v1Decoded.gameConfig.master.id == masterId)
        // The sender travels as the only roster entry so V1 peers can resolve
        // the sender name.
        #expect(v1Decoded.gameConfig.players.map(\.id) == [playerId])
        #expect(v1Decoded.gameConfig.players.first?.name == "Player - 1")
    }

    // MARK: - Current round trip

    @Test func roundTripKeepsAllFields() throws {
        var message = masterMessage
        message.targetId = playerId
        let encoded = try #require(message.encodeData())

        let decoded = try #require(GameNetworkModel.decodeData(of: encoded))

        #expect(decoded.version == GameNetworkModel.currentVersion)
        #expect(decoded.counter == message.counter)
        #expect(decoded.proxyCounter == message.proxyCounter)
        #expect(decoded.type == message.type)
        #expect(decoded.subType == message.subType)
        #expect(decoded.masterId == message.masterId)
        #expect(decoded.sender == message.sender)
        #expect(decoded.masterState == message.masterState)
        #expect(decoded.targetId == playerId)
        #expect(decoded.data == message.data)
    }

    @Test func playerMessageRoundTripCarriesNoMasterState() throws {
        let encoded = try #require(playerMessage.encodeData())

        let decoded = try #require(GameNetworkModel.decodeData(of: encoded))

        #expect(decoded.sender == playerMessage.sender)
        #expect(decoded.masterState == nil)
        #expect(decoded.masterId == masterId)
    }

    // MARK: - Mappers

    @Test func mapperRoundTripPreservesMasterMessages() {
        let mapped = masterMessage.v1Model.v2Model

        #expect(mapped.version == 1)
        #expect(mapped.counter == masterMessage.counter)
        #expect(mapped.masterId == masterMessage.masterId)
        #expect(mapped.sender == masterMessage.sender)
        #expect(mapped.masterState == masterMessage.masterState)
        #expect(mapped.data == masterMessage.data)
    }

    @Test func upMappedV1MessageStaysCompatibleWhenReEncoded() throws {
        // A relayed V1 message (proxy path) is re-encoded after up-mapping —
        // V1 clients must still be able to decode it.
        let v1Data = try JSONEncoder().encode(v1MasterMessage)
        let received = try #require(GameNetworkModel.decodeData(of: v1Data))

        let reEncoded = try #require(received.encodeData())
        let v1Decoded = try JSONDecoder().decode(GameNetworkModelV1.self, from: reEncoded)

        #expect(v1Decoded.gameConfig.players == players)
        #expect(v1Decoded.gameConfig.controls == controls)

        let v2Decoded = try #require(GameNetworkModel.decodeData(of: reEncoded))
        #expect(v2Decoded.sender.role == .master)
        #expect(v2Decoded.masterState?.players == players)
    }

    // MARK: - Deduplication

    @Test func dedupKeySeparatesMetadataOnlyFromFullPayload() {
        var metadataOnly = masterMessage
        metadataOnly.data = NetworkCodableDataType(id: payload.id, type: payload.type, version: payload.version, data: nil)

        let metadataKey = GameMessageKey(model: metadataOnly)
        let payloadKey = GameMessageKey(model: masterMessage)

        // A failed journal transfer delivers metadata first; the later full
        // payload must not be dropped as a duplicate.
        #expect(metadataKey != payloadKey)
    }
}
#endif
