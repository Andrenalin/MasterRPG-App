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
    func senderReportsCorrectTotalForExactSizeChunks() async throws {
        let data = Data("abcdefgh".utf8)
        let collector = PackageCollector()
        let sender = SharePlaySingleQueuePackageSender(packageSize: 4) { package in
            await collector.append(package)
        }

        try await sender.send(data: data)

        let packages = await collector.values
        #expect(sender.packageCount(for: data) == 2)
        #expect(packages.count == 2)
        #expect(packages.map(\.count) == [1, 2])
        #expect(packages.map(\.total) == [2, 2])
        #expect(packages.compactMap(\.data).reduce(Data(), +) == data)
    }

    @Test("default chunks remain below the encoded messenger limit")
    func defaultChunksRemainBelowEncodedMessengerLimit() async throws {
        let data = Data(repeating: 0xFF, count: SharePlaySingleQueuePackageSender.packageSize)
        let collector = PackageCollector()
        let sender = SharePlaySingleQueuePackageSender { package in
            await collector.append(package)
        }

        try await sender.send(data: data)

        let packages = await collector.values
        let package = try #require(packages.first)
        let encodedSize = try JSONEncoder().encode(package).count
        #expect(packages.count == 1)
        #expect(encodedSize < SharePlaySingleQueuePackageSender.encodedMessageSizeLimit)
    }

    @Test("sender retries a transient package failure")
    func senderRetriesTransientPackageFailure() async throws {
        let probe = PackageSendRetryProbe(failuresRemaining: 2)
        let sender = SharePlaySingleQueuePackageSender(
            packageSize: 4,
            retryDelays: [.zero, .zero]
        ) { package in
            try await probe.send(package)
        }

        try await sender.send(data: Data("abcd".utf8))

        #expect(await probe.attemptCount == 3)
        #expect(await probe.sentPackageCount == 1)
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

        // A mapState-introduced pin image is requested without bytes. Even an
        // explicit journal preference must therefore use ordered packages.
        let pinImageRequest = Self.message(type: .store, module: .photo, data: nil)
        #expect(!RPGSharePlayController.usesJournalTransport(for: pinImageRequest, fileJournal: true, journalAvailable: true))

        var pinImageResponse = Self.message(type: .store, module: .photo, data: Data("pin".utf8))
        pinImageResponse.targetId = UUID()
        #expect(!RPGSharePlayController.usesJournalTransport(for: pinImageResponse, fileJournal: true, journalAvailable: true))

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

    @Test("three SharePlay players produce one chunked repair per unique photo")
    func sharePlayPhotoRepairsAreBroadcastAndCoalesced() throws {
        let photoA = UUID()
        let photoB = UUID()
        let player1 = UUID()
        let player2 = UUID()
        let player3 = UUID()
        var tracker = SharePlayPhotoRepairTracker()
        let responses = [
            Self.masterPhotoRepair(counter: 10, photoId: photoA, targetId: player1),
            Self.masterPhotoRepair(counter: 11, photoId: photoB, targetId: player2),
            Self.masterPhotoRepair(counter: 12, photoId: photoA, targetId: player3),
            Self.masterPhotoRepair(counter: 13, photoId: photoB, targetId: player3)
        ]
        var preparedResponses: [(model: GameNetworkModel, usesJournalTransport: Bool)] = []

        for response in responses {
            if let prepared = RPGSharePlayController.prepareForTransport(
                response,
                fileJournal: true,
                journalAvailable: true,
                photoRepairTracker: &tracker
            ) {
                preparedResponses.append(prepared)
            }
        }

        #expect(preparedResponses.count == 2)
        #expect(preparedResponses.map(\.model.data.id) == [photoA, photoB])
        #expect(preparedResponses.allSatisfy { $0.model.targetId == nil })
        #expect(preparedResponses.allSatisfy { $0.model.type == .store && $0.model.subType == .store })
        #expect(preparedResponses.allSatisfy { !$0.usesJournalTransport })

        // Transport is intentionally chosen before target normalization. The
        // normalized full stores would otherwise qualify for the journal.
        let first = try #require(preparedResponses.first)
        #expect(RPGSharePlayController.usesJournalTransport(
            for: first.model,
            fileJournal: true,
            journalAvailable: true
        ))
    }

    @Test("photo repair coalescing resets for a changed participant set")
    func sharePlayPhotoRepairCoalescingCanReset() {
        let photoId = UUID()
        let targetId = UUID()
        var tracker = SharePlayPhotoRepairTracker()
        let version1 = Self.masterPhotoRepair(counter: 20, photoId: photoId, version: 1, targetId: targetId)
        let version2 = Self.masterPhotoRepair(counter: 22, photoId: photoId, version: 2, targetId: targetId)

        #expect(RPGSharePlayController.prepareForTransport(
            version1,
            fileJournal: true,
            journalAvailable: true,
            photoRepairTracker: &tracker
        ) != nil)
        #expect(RPGSharePlayController.prepareForTransport(
            version1,
            fileJournal: true,
            journalAvailable: true,
            photoRepairTracker: &tracker
        ) == nil)
        #expect(RPGSharePlayController.prepareForTransport(
            version2,
            fileJournal: true,
            journalAvailable: true,
            photoRepairTracker: &tracker
        ) != nil)

        tracker.reset()

        #expect(RPGSharePlayController.prepareForTransport(
            version2,
            fileJournal: true,
            journalAvailable: true,
            photoRepairTracker: &tracker
        ) != nil)
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

        tracker.retryProcessing(attachmentId: attachmentId)
        let retriedAfterFailure = tracker.shouldProcess(attachmentId: attachmentId)
        let processedAfterRetry = tracker.shouldProcess(attachmentId: attachmentId)
        #expect(retriedAfterFailure)
        #expect(!processedAfterRetry)

        tracker.reconcile(attachmentIds: [])
        tracker.reconcile(attachmentIds: [attachmentId])

        let processedAfterRemoval = tracker.shouldProcess(attachmentId: attachmentId)
        #expect(processedAfterRemoval)
    }

    @Test("journal attachment load retries while its CloudAsset upload finishes")
    func journalAttachmentLoadRetriesTransientUploadFailure() async throws {
        let probe = AttachmentLoadRetryProbe(failuresRemaining: 2)
        let retryDelays: [Duration] = [.milliseconds(1), .milliseconds(2)]

        let data = try await SharePlayAttachmentLoadRetry.load(
            retryDelays: retryDelays,
            sleep: { delay in
                await probe.recordSleep(delay)
            },
            operation: {
                try await probe.load()
            }
        )

        #expect(data == Data("map".utf8))
        #expect(await probe.attemptCount == 3)
        #expect(await probe.recordedDelays == retryDelays)
    }

    @Test("journal attachment load does not retry cancellation")
    func journalAttachmentLoadDoesNotRetryCancellation() async {
        let probe = AttachmentLoadRetryProbe(failuresRemaining: 0, cancels: true)

        await #expect(throws: CancellationError.self) {
            try await SharePlayAttachmentLoadRetry.load(
                retryDelays: [.milliseconds(1)],
                sleep: { delay in
                    await probe.recordSleep(delay)
                },
                operation: {
                    try await probe.load()
                }
            )
        }

        #expect(await probe.attemptCount == 1)
        #expect(await probe.recordedDelays.isEmpty)
    }

    @Test("journal attachment load does not start when already cancelled")
    func journalAttachmentLoadDoesNotStartWhenAlreadyCancelled() async {
        let probe = AttachmentLoadRetryProbe(failuresRemaining: 0)
        let startGate = AttachmentRetryStartGate()
        let task = Task {
            await startGate.wait()
            return try await SharePlayAttachmentLoadRetry.load(
                retryDelays: [.milliseconds(1)],
                sleep: { _ in },
                operation: {
                    try await probe.load()
                }
            )
        }
        task.cancel()
        await startGate.open()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await probe.attemptCount == 0)
    }

    @Test("journal attachment load stops when cancelled during retry delay")
    func journalAttachmentLoadStopsWhenCancelledDuringRetryDelay() async {
        let probe = AttachmentLoadRetryProbe(failuresRemaining: 10)
        let sleepGate = AttachmentRetrySleepGate()
        let task = Task {
            try await SharePlayAttachmentLoadRetry.load(
                retryDelays: [.milliseconds(1), .milliseconds(2)],
                sleep: { delay in
                    await sleepGate.sleep(for: delay)
                },
                operation: {
                    try await probe.load()
                }
            )
        }
        await sleepGate.waitUntilSleeping()
        task.cancel()
        await sleepGate.resume()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await probe.attemptCount == 1)
    }

    @Test("journal attachment load exhausts its bounded retry policy")
    func journalAttachmentLoadExhaustsBoundedRetryPolicy() async {
        let probe = AttachmentLoadRetryProbe(failuresRemaining: 10)
        let retryDelays: [Duration] = [.milliseconds(1), .milliseconds(2)]

        await #expect(throws: AttachmentLoadProbeError.self) {
            try await SharePlayAttachmentLoadRetry.load(
                retryDelays: retryDelays,
                sleep: { delay in
                    await probe.recordSleep(delay)
                },
                operation: {
                    try await probe.load()
                }
            )
        }

        #expect(await probe.attemptCount == retryDelays.count + 1)
        #expect(await probe.recordedDelays == retryDelays)
    }

    @Test("new journal maps publish while removal of the previous map is suspended")
    func newJournalMapsPublishWhilePreviousRemovalIsSuspended() async {
        let queue = SharePlayJournalPublicationQueue<TestJournalAttachment>()
        let removalGate = JournalRemovalGate()
        let recorder = JournalPublicationRecorder()
        let firstMap = TestJournalAttachment(id: UUID())
        let secondMap = TestJournalAttachment(id: UUID())
        let thirdMap = TestJournalAttachment(id: UUID())

        let firstPublication = queue.enqueue(for: .map) {
            recorder.record(firstMap)
            return firstMap
        } remove: { attachment in
            await removalGate.suspendRemoval(of: attachment.id)
        }
        await firstPublication.value

        let secondPublication = queue.enqueue(for: .map) {
            recorder.record(secondMap)
            return secondMap
        } remove: { attachment in
            await removalGate.suspendRemoval(of: attachment.id)
        }
        await secondPublication.value
        await removalGate.waitUntilRemovalStarts(for: firstMap.id)

        // Map one is still being removed. Publishing map three must only wait
        // for map two's add/commit, not for that cleanup operation.
        let thirdPublication = queue.enqueue(for: .map) {
            recorder.record(thirdMap)
            return thirdMap
        } remove: { attachment in
            await removalGate.suspendRemoval(of: attachment.id)
        }
        await thirdPublication.value

        #expect(recorder.attachmentIds == [firstMap.id, secondMap.id, thirdMap.id])
        #expect(queue.currentAttachment(for: .map)?.id == thirdMap.id)

        await removalGate.releaseAll()
        await Task.yield()
        queue.cancelAll()
    }

    @Test("overlapping journal maps are processed with the newest map last")
    func overlappingJournalMapsAreProcessedWithNewestMapLast() {
        let oldAttachmentId = UUID()
        let newAttachmentId = UUID()
        let masterId = UUID()
        var oldMap = Self.message(type: .reveal, module: .map, data: nil)
        oldMap.counter = 41
        oldMap.masterId = masterId
        oldMap.sender = GameSenderModel(
            id: masterId,
            role: .master,
            name: "Master",
            characterId: nil
        )
        var newMap = oldMap
        newMap.counter = 42
        newMap.data = NetworkCodableDataType(
            id: UUID(),
            type: .map,
            version: oldMap.data.version + 1,
            data: nil
        )
        var reversedSnapshot = [
            JournalMetadataFixture(attachmentId: newAttachmentId, metadata: newMap),
            JournalMetadataFixture(attachmentId: oldAttachmentId, metadata: oldMap)
        ]
        let latestPresentation = RPGSharePlayController.latestJournalPresentationAttachmentId(
            in: reversedSnapshot.map { (attachmentId: $0.attachmentId, metadata: $0.metadata) }
        )

        reversedSnapshot.sort {
            RPGSharePlayController.journalEntryComesBefore(
                metadata: $0.metadata,
                attachmentId: $0.attachmentId,
                metadata: $1.metadata,
                attachmentId: $1.attachmentId
            )
        }

        #expect(reversedSnapshot.map(\.metadata.counter) == [41, 42])
        #expect(reversedSnapshot.last?.metadata.data.id == newMap.data.id)
        #expect(latestPresentation == newAttachmentId)
        #expect(latestPresentation != oldAttachmentId)
    }

    @Test("presentation intent rejects stale payloads and stale targeted repairs")
    func presentationIntentRejectsStalePayloadsAndTargetedRepairs() {
        let model = PlayerControllerModel()
        let masterId = UUID()
        let mapA = UUID()
        let mapB = UUID()

        #expect(model.shouldProcessPresentation(
            from: masterId,
            module: .map,
            itemId: mapB,
            version: 1,
            counter: 42,
            isRepair: false
        ))
        #expect(model.shouldProcessPresentation(
            from: masterId,
            module: .map,
            itemId: mapA,
            version: 1,
            counter: 43,
            isRepair: false
        ))

        // Map B's journal load completed after the newer map A reference.
        #expect(!model.shouldProcessPresentation(
            from: masterId,
            module: .map,
            itemId: mapB,
            version: 1,
            counter: 42,
            isRepair: false
        ))
        // A repair gets a fresh counter, but must not revive B either.
        #expect(!model.shouldProcessPresentation(
            from: masterId,
            module: .map,
            itemId: mapB,
            version: 1,
            counter: 44,
            isRepair: true
        ))
        // Delayed bytes for the desired map remain useful.
        #expect(model.shouldProcessPresentation(
            from: masterId,
            module: .map,
            itemId: mapA,
            version: 1,
            counter: 41,
            isRepair: false
        ))
        #expect(!model.shouldProcessPresentation(
            from: masterId,
            module: .map,
            itemId: mapA,
            version: 0,
            counter: 40,
            isRepair: false
        ))
        // Older masters sent the targeted mapState companion with version zero.
        // It is allowed only as state for the already intended map.
        #expect(model.shouldProcessPresentation(
            from: masterId,
            module: .map,
            itemId: mapA,
            version: 0,
            counter: 44,
            isRepair: true,
            allowsUnversionedStateRepair: true
        ))
        #expect(!model.shouldProcessPresentation(
            from: masterId,
            module: .map,
            itemId: mapB,
            version: 0,
            counter: 45,
            isRepair: true,
            allowsUnversionedStateRepair: true
        ))
        #expect(!model.shouldProcessPresentation(
            from: masterId,
            module: .map,
            itemId: mapA,
            version: 2,
            counter: 40,
            isRepair: false
        ))

        let crossModuleModel = PlayerControllerModel()
        #expect(crossModuleModel.shouldProcessPresentation(
            from: masterId,
            module: .photo,
            itemId: UUID(),
            version: 1,
            counter: 43,
            isRepair: false
        ))
        #expect(!crossModuleModel.shouldProcessPresentation(
            from: masterId,
            module: .map,
            itemId: mapB,
            version: 1,
            counter: 42,
            isRepair: false
        ))

        var newerPhoto = Self.message(type: .reveal, module: .photo, data: nil)
        newerPhoto.counter = 43
        newerPhoto.masterId = masterId
        newerPhoto.sender = GameSenderModel(
            id: masterId,
            role: .master,
            name: "Master",
            characterId: nil
        )
        var olderMap = newerPhoto
        olderMap.counter = 42
        olderMap.data = NetworkCodableDataType(id: mapB, type: .map, version: 1)
        let olderMapAttachmentId = UUID()
        let newerPhotoAttachmentId = UUID()
        let latestCrossModuleAttachment = RPGSharePlayController.latestJournalPresentationAttachmentId(
            in: [
                (attachmentId: olderMapAttachmentId, metadata: olderMap),
                (attachmentId: newerPhotoAttachmentId, metadata: newerPhoto)
            ]
        )
        #expect(latestCrossModuleAttachment == newerPhotoAttachmentId)
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

    static func masterPhotoRepair(
        counter: Int,
        photoId: UUID,
        version: Int = 1,
        targetId: UUID
    ) -> GameNetworkModel {
        let masterId = UUID()
        return GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            masterId: masterId,
            sender: GameSenderModel(
                id: masterId,
                role: .master,
                name: "Master",
                characterId: nil
            ),
            targetId: targetId,
            data: NetworkCodableDataType(
                id: photoId,
                type: .photo,
                version: version,
                data: Data("photo-\(version)".utf8)
            )
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

private actor PackageSendRetryProbe {
    private var failuresRemaining: Int
    private(set) var attemptCount = 0
    private(set) var sentPackageCount = 0

    init(failuresRemaining: Int) {
        self.failuresRemaining = failuresRemaining
    }

    func send(_: PackageMessage) throws {
        attemptCount += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw PackageSendProbeError.transient
        }
        sentPackageCount += 1
    }
}

private enum PackageSendProbeError: Error {
    case transient
}

private actor AttachmentLoadRetryProbe {
    private var failuresRemaining: Int
    private let cancels: Bool
    private(set) var attemptCount = 0
    private(set) var recordedDelays: [Duration] = []

    init(failuresRemaining: Int, cancels: Bool = false) {
        self.failuresRemaining = failuresRemaining
        self.cancels = cancels
    }

    func load() throws -> Data {
        attemptCount += 1
        if cancels {
            throw CancellationError()
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw AttachmentLoadProbeError.uploadInProgress
        }
        return Data("map".utf8)
    }

    func recordSleep(_ delay: Duration) {
        recordedDelays.append(delay)
    }
}

private actor AttachmentRetryStartGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let currentWaiters = waiters
        waiters = []
        currentWaiters.forEach { $0.resume() }
    }
}

private actor AttachmentRetrySleepGate {
    private var isSleeping = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var sleepWaiter: CheckedContinuation<Void, Never>?

    func sleep(for _: Duration) async {
        isSleeping = true
        let currentStartWaiters = startWaiters
        startWaiters = []
        currentStartWaiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            sleepWaiter = continuation
        }
    }

    func waitUntilSleeping() async {
        guard !isSleeping else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume() {
        sleepWaiter?.resume()
        sleepWaiter = nil
    }
}

private enum AttachmentLoadProbeError: Error {
    case uploadInProgress
}

private struct TestJournalAttachment: Identifiable, Sendable {
    let id: UUID
}

private struct JournalMetadataFixture {
    let attachmentId: UUID
    let metadata: GameNetworkModel
}

@MainActor
private final class JournalPublicationRecorder {
    private(set) var attachmentIds: [UUID] = []

    func record(_ attachment: TestJournalAttachment) {
        attachmentIds.append(attachment.id)
    }
}

private actor JournalRemovalGate {
    private var startedAttachmentIds: Set<UUID> = []
    private var startWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private var removalWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func suspendRemoval(of attachmentId: UUID) async {
        startedAttachmentIds.insert(attachmentId)
        startWaiters.removeValue(forKey: attachmentId)?.forEach { $0.resume() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            removalWaiters.append(continuation)
        }
    }

    func waitUntilRemovalStarts(for attachmentId: UUID) async {
        guard !startedAttachmentIds.contains(attachmentId) else { return }
        await withCheckedContinuation { continuation in
            startWaiters[attachmentId, default: []].append(continuation)
        }
    }

    func releaseAll() {
        isReleased = true
        let waiters = removalWaiters
        removalWaiters = []
        waiters.forEach { $0.resume() }
    }
}
#endif
