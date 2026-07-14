// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG
@testable import GameRPG

@Suite("SharePlay package transport")
@MainActor
struct SharePlayPackageTransportTests {

    @Test("sender reports the correct total for exact-size chunks")
    func senderReportsCorrectTotalForExactSizeChunks() async {
        let data = Data("abcdefgh".utf8)
        let collector = PackageCollector()
        let sender = SharePlaySingleQueuePackageSender(packageSize: 4) { package in
            await collector.append(package)
        }

        await sender.send(data: data)

        let packages = await collector.values
        #expect(sender.packageCount(for: data) == 2)
        #expect(packages.count == 2)
        #expect(packages.map(\.count) == [1, 2])
        #expect(packages.map(\.total) == [2, 2])
        #expect(packages.compactMap(\.data).reduce(Data(), +) == data)
    }

    @Test("receiver reassembles packages by package number")
    func receiverReassemblesPackagesByPackageNumber() {
        let id = UUID()
        let receiver = SharePlayPackageReceiver()
        let first = PackageMessage(uuid: id, count: 1, total: 2, data: Data("abcd".utf8))
        let second = PackageMessage(uuid: id, count: 2, total: 2, data: Data("efgh".utf8))

        #expect(receiver.received(package: second) == nil)
        let result = receiver.received(package: first)

        #expect(result?.data == Data("abcdefgh".utf8))
    }

    @Test("master journals file-backed reveal and store payloads only when bytes are present")
    func masterJournalsFileBackedRevealAndStorePayloadsOnlyWithData() {
        for type in Self.journaledMessageTypes {
            for module in Self.fileBackedModules {
                let withData = Self.message(type: type, module: module, data: Data(module.token.utf8))
                let idOnly = Self.message(type: type, module: module, data: nil)

                #expect(MasterController.usesFileJournal(for: withData), "\(type) \(module) with bytes should use the file journal")
                #expect(!MasterController.usesFileJournal(for: idOnly), "\(type) \(module) without bytes should stay on the normal message path")
            }
        }
    }

    @Test("player send policy journals the same file-backed reveal and store payloads")
    func playerSendPolicyJournalsFileBackedRevealAndStorePayloadsOnlyWithData() {
        for type in Self.journaledMessageTypes {
            for module in Self.fileBackedModules {
                let withData = Self.message(type: type, module: module, data: Data(module.token.utf8))
                let idOnly = Self.message(type: type, module: module, data: nil)

                #expect(PlayerController.usesFileJournal(for: withData), "\(type) \(module) with bytes should use the file journal")
                #expect(!PlayerController.usesFileJournal(for: idOnly), "\(type) \(module) without bytes should stay on the normal message path")
            }
        }
    }

    @Test("targeted audio journal payload becomes a broadcast store")
    func targetedAudioJournalPayloadBecomesBroadcastStore() {
        let targetId = UUID()
        let audioId = UUID()
        let masterId = UUID()
        let payload = GameNetworkModel(
            counter: 7,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: masterId,
            sender: GameSenderModel(id: masterId, role: .master, name: "Master", characterId: nil),
            targetId: targetId,
            data: NetworkCodableDataType(id: audioId, type: .audio, version: 3, data: Data("audio".utf8))
        )

        let metadata = RPGSharePlayController.journalMetadata(for: payload)

        #expect(metadata.type == .store)
        #expect(metadata.subType == .show)
        #expect(metadata.targetId == nil)
        #expect(metadata.data.id == audioId)
        #expect(metadata.data.type == .audio)
        #expect(metadata.data.version == 3)
        #expect(metadata.data.data == nil)
    }

    @Test("journal carries broadcasts and audio; targeted answers use packages")
    func journalTransportSelection() {
        let broadcastPhoto = Self.message(type: .reveal, module: .photo, data: Data("photo".utf8))
        #expect(RPGSharePlayController.usesJournalTransport(for: broadcastPhoto, fileJournal: true, journalAvailable: true))
        #expect(!RPGSharePlayController.usesJournalTransport(for: broadcastPhoto, fileJournal: true, journalAvailable: false))
        #expect(!RPGSharePlayController.usesJournalTransport(for: broadcastPhoto, fileJournal: false, journalAvailable: true))

        let reference = Self.message(type: .reveal, module: .map, data: nil)
        #expect(!RPGSharePlayController.usesJournalTransport(for: reference, fileJournal: true, journalAvailable: true))

        // A targeted map answer must never replace the broadcast attachment
        // that other participants are still downloading.
        var targetedMap = Self.message(type: .reveal, module: .map, data: Data("map".utf8))
        targetedMap.targetId = UUID()
        #expect(!RPGSharePlayController.usesJournalTransport(for: targetedMap, fileJournal: true, journalAvailable: true))

        // Audio repairs stay on the journal — their metadata is morphed into
        // an untargeted store that every participant saves.
        var targetedAudio = Self.message(type: .store, module: .audio, data: Data("audio".utf8))
        targetedAudio.targetId = UUID()
        #expect(RPGSharePlayController.usesJournalTransport(for: targetedAudio, fileJournal: true, journalAvailable: true))
    }

    @Test("session configuration waits for join to be requested and joined")
    func sessionConfigurationWaitsForJoinRequestAndJoinedState() {
        let sessionId = UUID()
        var lifecycle = SharePlaySessionLifecycle()
        lifecycle.prepare(sessionId: sessionId)

        let configuredBeforeJoin = lifecycle.didEnterJoinedState(sessionId: sessionId)
        #expect(!configuredBeforeJoin)

        lifecycle.didRequestJoin(sessionId: sessionId)

        let configuredAfterJoin = lifecycle.didEnterJoinedState(sessionId: sessionId)
        let configuredTwice = lifecycle.didEnterJoinedState(sessionId: sessionId)
        #expect(configuredAfterJoin)
        #expect(!configuredTwice)
    }

    @Test("events from an old SharePlay session cannot configure a replacement session")
    func oldSessionEventsCannotConfigureReplacementSession() {
        let oldSessionId = UUID()
        let currentSessionId = UUID()
        var lifecycle = SharePlaySessionLifecycle()
        lifecycle.prepare(sessionId: oldSessionId)
        lifecycle.didRequestJoin(sessionId: oldSessionId)
        lifecycle.prepare(sessionId: currentSessionId)

        #expect(!lifecycle.isCurrent(sessionId: oldSessionId))
        #expect(lifecycle.isCurrent(sessionId: currentSessionId))
        let oldSessionConfigured = lifecycle.didEnterJoinedState(sessionId: oldSessionId)
        #expect(!oldSessionConfigured)

        lifecycle.didRequestJoin(sessionId: currentSessionId)

        let currentSessionConfigured = lifecycle.didEnterJoinedState(sessionId: currentSessionId)
        #expect(currentSessionConfigured)
    }

    @Test("removed journal publication becomes publishable again")
    func removedJournalPublicationBecomesPublishableAgain() {
        let itemId = UUID()
        let attachmentId = UUID()
        var tracker = SharePlayJournalTracker()

        #expect(tracker.shouldPublish(module: .photo, itemId: itemId, version: 2))

        tracker.didPublish(module: .photo, itemId: itemId, version: 2, attachmentId: attachmentId)
        tracker.reconcile(attachmentIds: [attachmentId])

        #expect(!tracker.shouldPublish(module: .photo, itemId: itemId, version: 2))

        tracker.didRemove(attachmentId: attachmentId)

        #expect(tracker.shouldPublish(module: .photo, itemId: itemId, version: 2))
    }

    @Test("replacement journal snapshot invalidates the local publication cache")
    func replacementJournalSnapshotInvalidatesLocalPublicationCache() {
        let itemId = UUID()
        let localAttachmentId = UUID()
        let replacementAttachmentId = UUID()
        var tracker = SharePlayJournalTracker()
        tracker.didPublish(module: .pdf, itemId: itemId, version: 4, attachmentId: localAttachmentId)
        tracker.reconcile(attachmentIds: [localAttachmentId])

        #expect(!tracker.shouldPublish(module: .pdf, itemId: itemId, version: 4))

        tracker.reconcile(attachmentIds: [replacementAttachmentId])

        #expect(tracker.shouldPublish(module: .pdf, itemId: itemId, version: 4))
    }

    @Test("journal attachment IDs are processed once per current snapshot lifetime")
    func journalAttachmentIdsAreProcessedOncePerSnapshotLifetime() {
        let attachmentId = UUID()
        var tracker = SharePlayJournalTracker()
        tracker.reconcile(attachmentIds: [attachmentId])

        let processedFirstTime = tracker.shouldProcess(attachmentId: attachmentId)
        let processedSecondTime = tracker.shouldProcess(attachmentId: attachmentId)
        #expect(processedFirstTime)
        #expect(!processedSecondTime)

        tracker.reconcile(attachmentIds: [])
        tracker.reconcile(attachmentIds: [attachmentId])

        let processedAfterRemoval = tracker.shouldProcess(attachmentId: attachmentId)
        #expect(processedAfterRemoval)
    }
}

private extension SharePlayPackageTransportTests {
    static let fileBackedModules: [NetworkModules] = [.pdf, .audio, .space, .photo, .map]
    static let journaledMessageTypes: [RPGMessageType] = [.reveal, .store]

    static func message(type: RPGMessageType, module: NetworkModules, data: Data?) -> GameNetworkModel {
        GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: type,
            subType: type == .store ? .store : .show,
            gameConfig: GameConfigModel(id: UUID(), state: .started, master: .empty),
            data: NetworkCodableDataType(id: UUID(), type: module, version: 1, data: data)
        )
    }

}

private actor PackageCollector {
    private var storage: [PackageMessage] = []

    var values: [PackageMessage] {
        storage
    }

    func append(_ package: PackageMessage) {
        storage.append(package)
    }
}
#endif
