// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// What a message is follows from its shape: sender, type, subtype and whether it has bytes.
@Suite("Game message shapes")
struct GameMessageShapeTests {
    let masterId = UUID()
    let playerId = UUID()
    let itemId = UUID()

    func message(
        role: GameType,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        module: NetworkModules,
        bytes: Data? = nil,
        targetId: UUID? = nil
    ) -> GameNetworkModel {
        GameNetworkModel(
            counter: 5,
            proxyCounter: 0,
            type: type,
            subType: subType,
            masterId: masterId,
            sender: GameSenderModel(
                id: role == .master ? masterId : playerId,
                role: role,
                name: "Sender",
                characterId: nil
            ),
            masterState: role == .master ? GameMasterStateModel(state: .started) : nil,
            targetId: targetId,
            data: NetworkCodableDataType(id: itemId, type: module, version: 3, data: bytes)
        )
    }

    // MARK: - Asset request

    @Test(
        "A player's reveal or store without bytes asks for the item",
        arguments: [NetworkModules.audio, .dice, .map, .pdf, .photo, .space, .table, .weather],
        [RPGMessageType.reveal, .store]
    )
    func assetRequest(module: NetworkModules, type: RPGMessageType) {
        #expect(message(role: .player, type: type, subType: .show, module: module).isAssetRequest)
        #expect(message(role: .player, type: type, subType: .store, module: module).isAssetRequest)
        #expect(message(role: .observer, type: type, subType: .show, module: module).isAssetRequest)
    }

    @Test("A reveal with another subtype is not a request", arguments: [RPGMessageActionType.photoList, .screen, .mapState, .generic])
    func otherSubTypesAskForNothing(subType: RPGMessageActionType) {
        #expect(!message(role: .observer, type: .reveal, subType: subType, module: .photo).isAssetRequest)
        #expect(!message(role: .player, type: .store, subType: subType, module: .photo).isAssetRequest)
    }

    @Test("An acknowledgement, a message with bytes, an update and a master message ask for nothing")
    func notAnAssetRequest() {
        #expect(!message(role: .player, type: .reveal, subType: .ok, module: .photo).isAssetRequest)
        #expect(!message(role: .player, type: .reveal, subType: .failed, module: .photo).isAssetRequest)
        #expect(!message(role: .player, type: .reveal, subType: .show, module: .photo, bytes: Data([1])).isAssetRequest)
        #expect(!message(role: .player, type: .update, subType: .generic, module: .photo).isAssetRequest)
        #expect(!message(role: .master, type: .reveal, subType: .show, module: .photo).isAssetRequest)
        #expect(!message(role: .player, type: .store, subType: .store, module: .value).isAssetRequest)
    }

    // MARK: - Player group events

    @Test("A Dice roll, a moved pin and a Space transform of a player are for the group")
    func playerGroupEvents() {
        #expect(message(role: .player, type: .update, subType: .generic, module: .dice, bytes: Data([1])).isPlayerGroupEvent)
        #expect(message(role: .player, type: .update, subType: .mapPin, module: .map, bytes: Data([1])).isPlayerGroupEvent)
        #expect(message(role: .player, type: .update, subType: .spaceTransform, module: .space, bytes: Data([1])).isPlayerGroupEvent)
    }

    @Test("Everything else a player sends is for the game master only")
    func masterOnlyPlayerMessages() {
        // Reports, the Character, contributions, requests and acknowledgements.
        #expect(!message(role: .player, type: .update, subType: .photoList, module: .photo, bytes: Data([1])).isPlayerGroupEvent)
        #expect(!message(role: .player, type: .update, subType: .store, module: .value, bytes: Data([1])).isPlayerGroupEvent)
        #expect(!message(role: .player, type: .update, subType: .generic, module: .photo, bytes: Data([1])).isPlayerGroupEvent)
        #expect(!message(role: .player, type: .reveal, subType: .show, module: .photo).isPlayerGroupEvent)
        #expect(!message(role: .player, type: .reveal, subType: .ok, module: .photo).isPlayerGroupEvent)
        // Dice commands other than a complete roll.
        #expect(!message(role: .player, type: .update, subType: .show, module: .dice, bytes: Data([1])).isPlayerGroupEvent)
        #expect(!message(role: .player, type: .update, subType: .generic, module: .dice).isPlayerGroupEvent)
        // A targeted message is not for the group.
        #expect(!message(role: .player, type: .update, subType: .generic, module: .dice, bytes: Data([1]), targetId: UUID()).isPlayerGroupEvent)
    }

    @Test("A group event larger than its bound is not relayed to the group")
    func oversizedGroupEvent() {
        let atLimit = Data(count: GameLimits.maximumGroupEventPayloadBytes)
        let overLimit = Data(count: GameLimits.maximumGroupEventPayloadBytes + 1)
        #expect(message(role: .player, type: .update, subType: .mapPin, module: .map, bytes: atLimit).isPlayerGroupEvent)
        #expect(!message(role: .player, type: .update, subType: .mapPin, module: .map, bytes: overLimit).isPlayerGroupEvent)
        #expect(!message(role: .player, type: .update, subType: .generic, module: .dice, bytes: overLimit).isPlayerGroupEvent)
        #expect(!message(role: .player, type: .update, subType: .spaceTransform, module: .space, bytes: overLimit).isPlayerGroupEvent)
    }

    @Test("Only a player publishes a group event", arguments: [GameType.observer, .proxy, .master])
    func otherRolesHaveNoGroupEvents(role: GameType) {
        #expect(!message(role: role, type: .update, subType: .generic, module: .dice, bytes: Data([1])).isPlayerGroupEvent)
    }

    @Test("A group event with a timestamp far in the future is not relayed")
    func groupEventNeedsPlausibleTimestamp() {
        // Given
        var roll = message(role: .player, type: .update, subType: .generic, module: .dice, bytes: Data([1]))
        roll.timestamp = Date.now.timeIntervalSince1970 + GameNetworkModel.maximumFutureEventTimestampSkew + 60

        // Then
        #expect(!roll.isPlayerGroupEvent)
    }

    // MARK: - Presentation and assets

    @Test("A master reveal and a map state change what the screen shows")
    func presentations() {
        #expect(message(role: .master, type: .reveal, subType: .show, module: .photo).isPresentation)
        #expect(message(role: .master, type: .reveal, subType: .show, module: .map, bytes: Data([1])).isPresentation)
        #expect(message(role: .master, type: .update, subType: .mapState, module: .map, bytes: Data([1])).isPresentation)
        #expect(!message(role: .master, type: .store, subType: .store, module: .photo, bytes: Data([1])).isPresentation)
        #expect(!message(role: .master, type: .update, subType: .generic, module: .map, bytes: Data([1])).isPresentation)
        #expect(!message(role: .master, type: .update, subType: .photoList, module: .photo, bytes: Data([1])).isPresentation)
        #expect(!message(role: .master, type: .reveal, subType: .show, module: .audio).isPresentation)
        #expect(!message(role: .player, type: .reveal, subType: .show, module: .photo).isPresentation)
    }

    @Test("A package of a file-backed module travels as an asset")
    func assets() {
        #expect(message(role: .master, type: .reveal, subType: .show, module: .photo, bytes: Data([1])).carriesAsset)
        #expect(message(role: .master, type: .store, subType: .show, module: .audio, bytes: Data([1])).carriesAsset)
        // The file a player contributes.
        #expect(message(role: .player, type: .update, subType: .generic, module: .pdf, bytes: Data([1])).carriesAsset)
        // References, live map updates and the small modules do not.
        #expect(!message(role: .master, type: .reveal, subType: .show, module: .photo).carriesAsset)
        #expect(!message(role: .master, type: .update, subType: .generic, module: .map, bytes: Data([1])).carriesAsset)
        #expect(!message(role: .master, type: .update, subType: .mapState, module: .map, bytes: Data([1])).carriesAsset)
        #expect(!message(role: .player, type: .update, subType: .mapPin, module: .map, bytes: Data([1])).carriesAsset)
        #expect(!message(role: .master, type: .reveal, subType: .show, module: .table, bytes: Data([1])).carriesAsset)
        #expect(!message(role: .player, type: .update, subType: .store, module: .value, bytes: Data([1])).carriesAsset)
    }
}
#endif
