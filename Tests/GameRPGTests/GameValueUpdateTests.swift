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

    @Test("Timestamp ledger rejects stale, duplicate, and far-future updates")
    func timestampLedgerRejectsStaleUpdates() {
        let root = GameRootModel()
        let senderId = UUID()
        let characterId = UUID()
        let entryId = UUID()
        let timestamp = Date.now.timeIntervalSince1970 - 1

        #expect(
            root.canApplyValueUpdate(
                senderId: senderId,
                characterId: characterId,
                entryId: entryId,
                timestamp: timestamp
            )
        )
        root.recordValueUpdate(
            senderId: senderId,
            characterId: characterId,
            entryId: entryId,
            timestamp: timestamp
        )

        #expect(
            !root.canApplyValueUpdate(
                senderId: senderId,
                characterId: characterId,
                entryId: entryId,
                timestamp: timestamp
            )
        )
        #expect(
            !root.canApplyValueUpdate(
                senderId: senderId,
                characterId: characterId,
                entryId: entryId,
                timestamp: timestamp - 1
            )
        )
        #expect(
            root.canApplyValueUpdate(
                senderId: senderId,
                characterId: characterId,
                entryId: entryId,
                timestamp: timestamp + 0.5
            )
        )
        #expect(
            !root.canApplyValueUpdate(
                senderId: senderId,
                characterId: characterId,
                entryId: entryId,
                timestamp: Date.now.timeIntervalSince1970
                    + GameNetworkModel.maximumFutureEventTimestampSkew
                    + 1
            )
        )
    }
}
#endif
