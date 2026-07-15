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

    @Test func decodesV1PlayerEnvelopeWithoutRosterAsPlayer() throws {
        struct V1PlayerEnvelopeWithoutRoster: Encodable {
            let version: Int
            let counter: Int
            let proxyCounter: Int
            let type: RPGMessageType
            let subType: RPGMessageActionType
            let gameConfig: GameConfigModel
            let data: NetworkCodableDataType
        }
        let oldPlayer = V1PlayerEnvelopeWithoutRoster(
            version: 1,
            counter: 8,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            gameConfig: GameConfigModel(id: playerId, state: .started, master: master),
            data: NetworkCodableDataType(id: UUID(), type: .dice, version: 0, data: Data([0x01]))
        )
        let oldPlayerData = try JSONEncoder().encode(oldPlayer)

        let decoded = try #require(GameNetworkModel.decodeData(of: oldPlayerData))

        #expect(decoded.masterId == masterId)
        #expect(decoded.sender.id == playerId)
        #expect(decoded.sender.role == .player)
        #expect(!decoded.sender.name.isEmpty)
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

        #expect(v1Decoded.version == GameNetworkModelV1.wireVersion)
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

        #expect(v1Decoded.version == GameNetworkModelV1.wireVersion)
        #expect(v1Decoded.gameConfig.id == playerId)
        #expect(v1Decoded.gameConfig.master.id == masterId)
        // The sender travels as the only roster entry so V1 peers can resolve
        // the sender name.
        #expect(v1Decoded.gameConfig.players.map(\.id) == [playerId])
        #expect(v1Decoded.gameConfig.players.first?.name == "Player - 1")
    }

    @Test func mapContentUpdateKeepsTheV1GenericActionAndPayloadShape() throws {
        struct LegacyPayload: Decodable {
            let id: UUID
            let type: NetworkModules
            let version: Int
            let data: Data?
        }
        struct LegacyEnvelope: Decodable {
            let type: RPGMessageType
            let subType: RPGMessageActionType
            let data: LegacyPayload
        }

        // Given
        let mapId = UUID()
        var update = masterMessage
        update.type = .update
        update.subType = .generic
        update.data = NetworkCodableDataType(
            id: mapId,
            type: .map,
            version: 14,
            data: Data("{\"schemaVersion\":1}".utf8),
            assetVersion: 27,
            contentVersion: 31
        )

        // When
        let encoded = try #require(update.encodeData())
        let legacy = try JSONDecoder().decode(LegacyEnvelope.self, from: encoded)
        let current = try #require(GameNetworkModel.decodeData(of: encoded))

        // Then: old peers ignore the two optional version keys instead of
        // rejecting a new enum raw value, while current peers retain them.
        #expect(legacy.type == .update)
        #expect(legacy.subType == .generic)
        #expect(legacy.data.id == mapId)
        #expect(legacy.data.type == .map)
        #expect(legacy.data.version == 14)
        #expect(legacy.data.data == update.data.data)
        #expect(current.data.assetVersion == 27)
        #expect(current.data.contentVersion == 31)
    }

    @Test("V2 gamemaster and V1 player can send dice and photo")
    func v2MasterAndV1PlayerCanSendDiceAndPhoto() throws {
        for payload in Self.compatibilityPayloads {
            let v2MasterMessage = v2MasterMessage(payload)
            let encodedMasterMessage = try #require(v2MasterMessage.encodeData())

            let receivedByV1Player = try JSONDecoder().decode(GameNetworkModelV1.self, from: encodedMasterMessage)

            #expect(receivedByV1Player.version == GameNetworkModelV1.wireVersion)
            #expect(receivedByV1Player.gameConfig.id == masterId)
            #expect(receivedByV1Player.gameConfig.master.id == masterId)
            #expect(receivedByV1Player.gameConfig.players == players)
            assert(receivedByV1Player, matches: v2MasterMessage)

            let v1PlayerMessage = v1PlayerMessage(payload)
            let encodedPlayerMessage = try JSONEncoder().encode(v1PlayerMessage)

            let receivedByV2Master = try #require(GameNetworkModel.decodeData(of: encodedPlayerMessage))

            #expect(receivedByV2Master.masterId == masterId)
            #expect(receivedByV2Master.sender.id == playerId)
            #expect(receivedByV2Master.sender.role == .player)
            #expect(receivedByV2Master.sender.name == "Player - 1")
            #expect(receivedByV2Master.masterState == nil)
            assert(receivedByV2Master, matches: v1PlayerMessage)
        }
    }

    @Test("V1 gamemaster and V2 player can send dice and photo")
    func v1MasterAndV2PlayerCanSendDiceAndPhoto() throws {
        for payload in Self.compatibilityPayloads {
            let v1MasterMessage = v1MasterMessage(payload)
            let encodedMasterMessage = try JSONEncoder().encode(v1MasterMessage)

            let receivedByV2Player = try #require(GameNetworkModel.decodeData(of: encodedMasterMessage))

            #expect(receivedByV2Player.masterId == masterId)
            #expect(receivedByV2Player.sender.id == masterId)
            #expect(receivedByV2Player.sender.role == .master)
            let masterState = try #require(receivedByV2Player.masterState)
            #expect(masterState.players == players)
            #expect(masterState.controls == controls)
            assert(receivedByV2Player, matches: v1MasterMessage)

            let v2PlayerMessage = v2PlayerMessage(payload)
            let encodedPlayerMessage = try #require(v2PlayerMessage.encodeData())

            let receivedByV1Master = try JSONDecoder().decode(GameNetworkModelV1.self, from: encodedPlayerMessage)

            #expect(receivedByV1Master.version == GameNetworkModelV1.wireVersion)
            #expect(receivedByV1Master.gameConfig.id == playerId)
            #expect(receivedByV1Master.gameConfig.master.id == masterId)
            #expect(receivedByV1Master.gameConfig.players.map(\.id) == [playerId])
            #expect(receivedByV1Master.gameConfig.players.first?.type == .player)
            assert(receivedByV1Master, matches: v2PlayerMessage)
        }
    }

    // MARK: - Current round trip

    @Test func roundTripKeepsAllFields() throws {
        var message = masterMessage
        message.targetId = playerId
        let encoded = try #require(message.encodeData())

        let decoded = try #require(GameNetworkModel.decodeData(of: encoded))

        #expect(decoded.version == GameNetworkModelV1.wireVersion)
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

private extension GameNetworkModelVersionTests {
    struct CompatibilityPayload {
        let module: NetworkModules
        let type: RPGMessageType
        let subType: RPGMessageActionType
        let bytes: Data
    }

    static let compatibilityPayloads: [CompatibilityPayload] = [
        CompatibilityPayload(module: .dice, type: .update, subType: .generic, bytes: Data([0xD1, 0xCE])),
        CompatibilityPayload(module: .photo, type: .reveal, subType: .show, bytes: Data([0xF0, 0x70]))
    ]

    func v2MasterMessage(_ payload: CompatibilityPayload) -> GameNetworkModel {
        GameNetworkModel(
            counter: payload.module == .dice ? 10 : 11,
            proxyCounter: 0,
            type: payload.type,
            subType: payload.subType,
            masterId: masterId,
            sender: GameSenderModel(id: masterId, role: .master, name: "Master", characterId: nil),
            masterState: GameMasterStateModel(state: .started, adventureId: master.adventureId, adventureTitle: master.adventureTitle, players: players, controls: controls, features: features),
            data: data(for: payload)
        )
    }

    func v2PlayerMessage(_ payload: CompatibilityPayload) -> GameNetworkModel {
        GameNetworkModel(
            counter: payload.module == .dice ? 20 : 21,
            proxyCounter: 0,
            type: payload.type,
            subType: payload.subType,
            masterId: masterId,
            sender: GameSenderModel(id: playerId, role: .player, name: "Player - 1", characterId: players[0].characterId),
            data: data(for: payload)
        )
    }

    func v1MasterMessage(_ payload: CompatibilityPayload) -> GameNetworkModelV1 {
        GameNetworkModelV1(
            counter: payload.module == .dice ? 30 : 31,
            proxyCounter: 0,
            type: payload.type,
            subType: payload.subType,
            gameConfig: GameConfigModelV1(id: masterId, state: .started, master: master, players: players, controls: controls, features: features),
            data: data(for: payload)
        )
    }

    func v1PlayerMessage(_ payload: CompatibilityPayload) -> GameNetworkModelV1 {
        GameNetworkModelV1(
            counter: payload.module == .dice ? 40 : 41,
            proxyCounter: 0,
            type: payload.type,
            subType: payload.subType,
            gameConfig: GameConfigModelV1(id: playerId, state: .started, master: master, players: players, controls: controls, features: features),
            data: data(for: payload)
        )
    }

    func data(for payload: CompatibilityPayload) -> NetworkCodableDataType {
        NetworkCodableDataType(id: UUID(), type: payload.module, version: 1, data: payload.bytes)
    }

    func assert(_ received: GameNetworkModelV1, matches sent: GameNetworkModel) {
        #expect(received.counter == sent.counter)
        #expect(received.proxyCounter == sent.proxyCounter)
        #expect(received.type == sent.type)
        #expect(received.subType == sent.subType)
        #expect(received.data.type == sent.data.type)
        #expect(received.data.data == sent.data.data)
    }

    func assert(_ received: GameNetworkModel, matches sent: GameNetworkModelV1) {
        #expect(received.counter == sent.counter)
        #expect(received.proxyCounter == sent.proxyCounter)
        #expect(received.type == sent.type)
        #expect(received.subType == sent.subType)
        #expect(received.data.type == sent.data.type)
        #expect(received.data.data == sent.data.data)
    }
}
#endif
