// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CharacterRPG
@testable import CoreRPG
@testable import GameRPG

@MainActor
@Suite("Game value updates")
struct GameValueUpdateTests {
    @Test("Value update payload round-trips without link fields")
    func payloadRoundTrip() throws {
        let update = GameValueEntryUpdate(
            characterId: UUID(),
            entryId: UUID(),
            name: "HP",
            typeRawValue: ValueEntryModel.ValueType.number.rawValue,
            isGenerator: false,
            value: "20|-3",
            displayState: 2
        )

        let decoded = try #require(
            GameValueEntryUpdate.decodeData(of: update.encodeData())
        )

        #expect(decoded == update)
    }

    @Test("Runtime value update preserves the master's entry links")
    func runtimeUpdatePreservesLinks() throws {
        let root = CharacterRootModel.previewFixture(models: [])
        let characterId = UUID()
        let entryId = UUID()
        let diceId = UUID()
        let nestedValueId = UUID()
        let character = ValueModel(
            id: characterId,
            name: "Hero",
            entries: [
                ValueEntryModel(
                    id: entryId,
                    name: "HP",
                    type: .number,
                    value: "20",
                    diceId: diceId,
                    valueId: nestedValueId
                )
            ]
        )
        root.itemController.replace(model: character, isInsert: true)
        let update = GameValueEntryUpdate(
            characterId: characterId,
            entryId: entryId,
            name: "Health",
            typeRawValue: ValueEntryModel.ValueType.number.rawValue,
            isGenerator: false,
            value: "20|-3",
            displayState: 3
        )

        #expect(root.gameController.applyGameValueEntryUpdate(update))

        let entry = try #require(
            root.gameController.gameEntry(
                characterId: characterId,
                entryId: entryId
            )
        )
        #expect(entry.name == "Health")
        #expect(entry.value == "20|-3")
        #expect(entry.displayState == 3)
        #expect(entry.diceId == diceId)
        #expect(entry.valueId == nestedValueId)
        #expect(
            root.itemController.itemSync(
                for: characterId,
                noGame: true
            )?.entries.first?.value == "20"
        )
        #expect(
            root.gameController.gameEntryDisplayValue(
                characterId: characterId,
                entryId: entryId
            ) == "17"
        )
    }

    /// See CODE_AUDIT_Game §6.1: `sender.characterId` is otherwise
    /// self-declared, untrusted network input — every peer already sees
    /// every pin's `characterId`, so without this binding any admitted
    /// player could claim another player's Character id and have
    /// `handleValue` apply value updates (including HP) against it.
    @Test("Character ownership binding rejects a claim on another sender's Character")
    func characterOwnershipBindingRejectsHijack() {
        let model = MasterControllerModel()
        let ownerId = UUID()
        let attackerId = UUID()
        let characterId = UUID()

        // The legitimate owner's join handshake binds first.
        #expect(model.bindCharacterOwnership(senderId: ownerId, characterId: characterId))
        #expect(model.isCharacterOwnershipAuthorized(senderId: ownerId, characterId: characterId))

        // A different sender claiming the same Character id is rejected
        // outright, and the owner's own binding is unaffected.
        #expect(!model.bindCharacterOwnership(senderId: attackerId, characterId: characterId))
        #expect(!model.isCharacterOwnershipAuthorized(senderId: attackerId, characterId: characterId))
        #expect(model.isCharacterOwnershipAuthorized(senderId: ownerId, characterId: characterId))

        // The owner re-claiming their own Character (e.g. a reconnect) is fine...
        #expect(model.bindCharacterOwnership(senderId: ownerId, characterId: characterId))
        // ...but the owner can't later switch to claiming a different Character id.
        #expect(!model.bindCharacterOwnership(senderId: ownerId, characterId: UUID()))

        model.resetCharacterOwnership()
        #expect(!model.isCharacterOwnershipAuthorized(senderId: ownerId, characterId: characterId))
    }

    @Test("Update ledger rejects stale/duplicate counters and far-future timestamps")
    func updateLedgerRejectsStaleUpdates() {
        let root = GameRootModel()
        let senderId = UUID()
        let characterId = UUID()
        let entryId = UUID()
        let timestamp = Date.now.timeIntervalSince1970 - 1

        // First update at counter 5 is accepted and recorded.
        #expect(
            root.canApplyValueUpdate(
                senderId: senderId,
                characterId: characterId,
                entryId: entryId,
                timestamp: timestamp,
                counter: 5
            )
        )
        root.recordValueUpdate(
            senderId: senderId,
            characterId: characterId,
            entryId: entryId,
            counter: 5
        )

        // A retry at the exact same counter is a duplicate and rejected,
        // even with a later timestamp — two legitimate back-to-back edits
        // can share (or regress) a wall-clock timestamp, so ordering must
        // not depend on it. See CODE_AUDIT_Network §5.17.
        #expect(
            !root.canApplyValueUpdate(
                senderId: senderId,
                characterId: characterId,
                entryId: entryId,
                timestamp: timestamp,
                counter: 5
            )
        )
        #expect(
            !root.canApplyValueUpdate(
                senderId: senderId,
                characterId: characterId,
                entryId: entryId,
                timestamp: timestamp + 10,
                counter: 5
            )
        )

        // A lower counter is stale and rejected.
        #expect(
            !root.canApplyValueUpdate(
                senderId: senderId,
                characterId: characterId,
                entryId: entryId,
                timestamp: timestamp,
                counter: 4
            )
        )

        // A higher counter is accepted, even with an identical or
        // non-increasing timestamp.
        #expect(
            root.canApplyValueUpdate(
                senderId: senderId,
                characterId: characterId,
                entryId: entryId,
                timestamp: timestamp,
                counter: 6
            )
        )

        // A far-future timestamp is rejected regardless of counter — the
        // sanity bound is independent of ordering.
        #expect(
            !root.canApplyValueUpdate(
                senderId: senderId,
                characterId: characterId,
                entryId: entryId,
                timestamp: Date.now.timeIntervalSince1970
                    + GameNetworkModel.maximumFutureEventTimestampSkew
                    + 1,
                counter: 100
            )
        )
    }
}
#endif
