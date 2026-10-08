// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// Regression tests for CODE_AUDIT_21 §5 findings in GameRPG.
@MainActor
@Suite("CODE_AUDIT_21 §5 — game")
struct CodeAudit21BugFixTests {
    private func message(
        counter: Int,
        senderId: UUID,
        type: NetworkModules = .dice,
        data: Data? = nil
    ) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: UUID(),
            sender: GameSenderModel(id: senderId, role: .player, name: "Player", characterId: nil),
            data: NetworkCodableDataType(id: UUID(), type: type, version: 0, data: data)
        )
    }

    // MARK: - §5.5

    @Test("A rejected Character is retried with a growing delay and then no longer sent")
    func characterRejectionsAreBounded() {
        let model = PlayerControllerModel()
        model.reset(lostMaster: false)
        let start = ContinuousClock.now
        #expect(model.canSendCharacter)

        model.reset(sendPlayer: true)
        #expect(!model.recordCharacterRejection(version: 7, now: start))
        // Not sent again before the retry delay is over.
        #expect(!model.canSendCharacter)
        #expect(PlayerControllerModel.characterRetryDelay(afterRejection: 1) == .seconds(5))
        #expect(PlayerControllerModel.characterRetryDelay(afterRejection: 2) == .seconds(20))

        #expect(!model.recordCharacterRejection(version: 7, now: start))
        // The last allowed rejection is the one the player is told about, once.
        #expect(model.recordCharacterRejection(version: 7, now: start))
        #expect(!model.recordCharacterRejection(version: 7, now: start))
        #expect(!model.mayAnnounceCharacter(version: 7, now: start))

        // An edited Character has a new version and gets new attempts.
        #expect(model.mayAnnounceCharacter(version: 8, now: start))
        #expect(model.characterRejections == 0)
    }

    @Test("A new connection forgets earlier Character rejections")
    func lostConnectionResetsRejections() {
        let model = PlayerControllerModel()
        for _ in 0..<PlayerControllerModel.maximumCharacterRejections {
            _ = model.recordCharacterRejection(version: 1)
        }
        #expect(!model.mayAnnounceCharacter(version: 1))

        model.resetForLostConnection(preservingSharePlayRebind: false)

        #expect(model.characterRejections == 0)
        #expect(model.mayAnnounceCharacter(version: 1))
    }

    @Test("A note is a log row of its own with its text as the title")
    func logNote() {
        let gameModel = GameRootModel()
        let log = LogGameController(root: nil, gameModel: gameModel)
        log.addMessage(counter: 1, type: .reveal, subType: .show, module: .map, itemId: UUID())

        log.addNote("The Character was not accepted.")
        log.addNote("Second note")

        #expect(gameModel.logs == [1, -1, -2])
        let rows = log.logRows
        #expect(rows.map(\.title).prefix(2) == ["Second note", "The Character was not accepted."])
        #expect(rows.first?.playerNames == "")
        #expect(rows.first?.deliveryState == .notTracked)
    }

    // MARK: - §5.6

    @Test("Deferred events of two senders with one counter are both kept")
    func deferredEventsAreKeyedBySender() {
        let sessionId = UUID()
        var queue = SharePlayDeferredDeliveryQueue()
        let first = message(counter: 1, senderId: UUID())
        let second = message(counter: 1, senderId: UUID())

        #expect(queue.enqueue(first, sessionId: sessionId, participantId: nil) == .enqueued)
        #expect(queue.enqueue(second, sessionId: sessionId, participantId: nil) == .enqueued)
        // The same sender's message again is the same event.
        #expect(queue.enqueue(first, sessionId: sessionId, participantId: nil) == .replaced)

        #expect(queue.count == 2)
    }

    @Test("Chunked retries back off")
    func chunkedRetryBackoff() {
        #expect(RPGSharePlayController.maxChunkedDeliveryAttempts == 4)
        #expect(RPGSharePlayController.chunkedRetryDelay(forAttempt: 1) == .seconds(1))
        #expect(RPGSharePlayController.chunkedRetryDelay(forAttempt: 2) == .seconds(2))
        #expect(RPGSharePlayController.chunkedRetryDelay(forAttempt: 3) == .seconds(4))
    }

    // MARK: - §5.9

    @Test("Value updates held before the handshake are kept per entry and replayed in counter order")
    func pendingValueUpdatesPerEntry() throws {
        let model = MasterControllerModel()
        let senderId = UUID()
        let characterId = UUID()
        let hitPoints = UUID()
        let mana = UUID()
        func update(entryId: UUID, value: String, counter: Int) -> GameNetworkModel {
            let payload = GameValueEntryUpdate(
                characterId: characterId,
                entryId: entryId,
                name: "Value",
                typeRawValue: 0,
                isGenerator: false,
                value: value,
                displayState: 0
            )
            return message(counter: counter, senderId: senderId, type: .value, data: payload.encodeData())
        }

        model.deferValueUpdateAwaitingOwnership(update(entryId: hitPoints, value: "10", counter: 3))
        model.deferValueUpdateAwaitingOwnership(update(entryId: mana, value: "4", counter: 5))
        // A newer value of an entry that is already held replaces it.
        model.deferValueUpdateAwaitingOwnership(update(entryId: hitPoints, value: "8", counter: 4))

        let replayed = model.takePendingValueUpdates(senderId: senderId)
        #expect(replayed.map(\.counter) == [4, 5])
        let values = replayed.compactMap { GameValueEntryUpdate.decodeData(of: $0.data.data)?.value }
        #expect(values == ["8", "4"])
        #expect(model.takePendingValueUpdates(senderId: senderId).isEmpty)
    }

    @Test("The buffer of held value updates is bounded per sender")
    func pendingValueUpdatesAreBounded() {
        let model = MasterControllerModel()
        let senderId = UUID()
        let characterId = UUID()
        let limit = MasterControllerModel.maximumPendingValueUpdatesPerSender
        for counter in 1...(limit + 5) {
            let payload = GameValueEntryUpdate(
                characterId: characterId,
                entryId: UUID(),
                name: "Value",
                typeRawValue: 0,
                isGenerator: false,
                value: "\(counter)",
                displayState: 0
            )
            model.deferValueUpdateAwaitingOwnership(
                message(counter: counter, senderId: senderId, type: .value, data: payload.encodeData())
            )
        }

        let replayed = model.takePendingValueUpdates(senderId: senderId)
        #expect(replayed.count == limit)
        #expect(replayed.first?.counter == 6)
    }
}
#endif
