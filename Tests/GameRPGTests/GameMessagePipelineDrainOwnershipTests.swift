// @copyright André Trettin

import CoreRPG
import Foundation
import Synchronization
import Testing

@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §3.1: the queue is drained by a worker the pipeline owns, not by
/// whichever peer's receive task enqueued first.
@Suite("GameMessagePipeline drain ownership")
struct GameMessagePipelineDrainOwnershipTests {

    @Test("submit returns once the message was handled")
    func submitReturnsAfterHandling() async {
        let pipeline = GameMessagePipeline()
        let recorder = Recorder()

        await pipeline.submit(Self.event(counter: 1), prefix: "Test", drain: Self.drain(pipeline, recorder: recorder))

        #expect(await recorder.finished == [1])
        #expect(await pipeline.hasQueuedMessages == false)
    }

    @Test("cancelling the peer whose task enqueued first does not cancel the handling of its message or drop another peer's")
    func cancellingTheFirstSubmitterKeepsTheDrainAlive() async throws {
        let pipeline = GameMessagePipeline()
        let recorder = Recorder()
        let gate = Gate()
        let drain = Self.drain(pipeline, recorder: recorder) { event in
            if event.model.counter == 1 { await gate.wait() }
        }

        // Peer A's receive task starts the drain; its handler is still running.
        let peerA = Task { await pipeline.submit(Self.event(counter: 1), prefix: "Test", drain: drain) }
        try #require(await Self.eventually { await recorder.began.contains(1) })
        // Peer B's message waits behind it.
        let peerB = Task { await pipeline.submit(Self.event(counter: 2), prefix: "Test", drain: drain) }
        try #require(await Self.eventually { await pipeline.hasQueuedMessages })

        // Peer A disconnects: its receive task is cancelled and stops waiting at once.
        peerA.cancel()
        #expect(await Self.finishes(within: .seconds(5)) { await peerA.value })

        // A's handler was not cancelled with it, and B's message is still served.
        await gate.open()
        #expect(await Self.finishes(within: .seconds(5)) { await peerB.value })
        #expect(await recorder.finished == [1, 2])
        #expect(await recorder.cancelledDuringHandling.isEmpty)
    }

    @Test("cancelAll releases waiting submitters and cancels the worker")
    func cancelAllReleasesWaiters() async throws {
        let pipeline = GameMessagePipeline()
        let recorder = Recorder()
        let gate = Gate()
        let drain = Self.drain(pipeline, recorder: recorder) { _ in await gate.wait() }

        let peer = Task { await pipeline.submit(Self.event(counter: 1), prefix: "Test", drain: drain) }
        try #require(await Self.eventually { await recorder.began.contains(1) })

        await pipeline.cancelAll()

        #expect(await Self.finishes(within: .seconds(5)) { await peer.value })
        await gate.open()
        try #require(await Self.eventually { await recorder.finished.contains(1) })
        #expect(await recorder.cancelledDuringHandling == [1])
    }

    @Test("reset releases waiting submitters without cancelling the handler in hand")
    func resetReleasesWaiters() async throws {
        let pipeline = GameMessagePipeline()
        let recorder = Recorder()
        let gate = Gate()
        let drain = Self.drain(pipeline, recorder: recorder) { _ in await gate.wait() }

        let peer = Task { await pipeline.submit(Self.event(counter: 1), prefix: "Test", drain: drain) }
        try #require(await Self.eventually { await recorder.began.contains(1) })

        await pipeline.reset()

        #expect(await Self.finishes(within: .seconds(5)) { await peer.value })
        await gate.open()
        try #require(await Self.eventually { await recorder.finished.contains(1) })
        #expect(await recorder.cancelledDuringHandling.isEmpty)
    }

    @Test("a handler that submits to its own pipeline does not wait for its own worker")
    func nestedSubmitDoesNotDeadlock() async {
        let pipeline = GameMessagePipeline()
        let recorder = Recorder()
        let holder = DrainHolder()
        let drain = Self.drain(pipeline, recorder: recorder) { event in
            guard event.model.counter == 1 else { return }
            await pipeline.submit(Self.event(counter: 2), prefix: "Test", drain: holder.drain)
        }
        holder.drain = drain

        let completed = await Self.finishes(within: .seconds(5)) {
            await pipeline.submit(Self.event(counter: 1), prefix: "Test", drain: drain)
        }

        #expect(completed)
        #expect(await Self.eventually { await recorder.finished == [1, 2] })
    }

    @Test("a worker that leaves its loop early hands the backlog to a new worker")
    func backlogIsTakenOverWhenAWorkerLeavesEarly() async {
        let pipeline = GameMessagePipeline()
        let recorder = Recorder()
        let runs = Counter()
        let normal = Self.drain(pipeline, recorder: recorder)
        let drain: @Sendable () async -> Void = {
            // The first worker leaves without handling anything, like a handler that threw
            // `CancellationError` and ended the loop with messages left.
            if await runs.increment() == 1 { return }
            await normal()
        }

        let completed = await Self.finishes(within: .seconds(5)) {
            await pipeline.submit(Self.event(counter: 1), prefix: "Test", drain: drain)
        }

        #expect(completed)
        #expect(await recorder.finished == [1])
        #expect(await runs.value == 2)
    }

    @Test("a duplicate returns at once")
    func duplicateReturnsAtOnce() async {
        let pipeline = GameMessagePipeline()
        let recorder = Recorder()
        let drain = Self.drain(pipeline, recorder: recorder)

        let event = Self.event(counter: 1)
        await pipeline.submit(event, prefix: "Test", drain: drain)
        let completed = await Self.finishes(within: .seconds(5)) {
            await pipeline.submit(event, prefix: "Test", drain: drain)
        }

        #expect(completed)
        #expect(await recorder.finished == [1])
    }

    // MARK: - Helpers

    private static func event(counter: Int, senderId: UUID = UUID()) -> GameMessageEvent {
        let gameConfig = GameConfigModel(
            id: senderId,
            state: .started,
            master: MasterGameModel(id: UUID(), type: .master, name: "Master")
        )
        let data = NetworkCodableDataType(id: UUID(), type: .photo, version: 1, data: nil)
        let model = GameNetworkModel(counter: counter, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: gameConfig, data: data)
        return GameMessageEvent(model: model, origin: .direct(UUID()))
    }

    /// The loop a controller runs: take events with `next()` until there are none.
    private static func drain(
        _ pipeline: GameMessagePipeline,
        recorder: Recorder,
        handler: @escaping @Sendable (GameMessageEvent) async -> Void = { _ in }
    ) -> @Sendable () async -> Void {
        {
            while let event = await pipeline.next() {
                let counter = event.model.counter
                await recorder.recordBegan(counter)
                await handler(event)
                await recorder.recordFinished(counter, wasCancelled: Task.isCancelled)
                await pipeline.processed(success: true)
            }
        }
    }

    private static func eventually(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
        for _ in 0 ..< 500 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    /// Whether `body` returns within `limit`; a hang fails the test instead of blocking the run.
    private static func finishes(within limit: Duration, _ body: @escaping @Sendable () async -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await body()
                return true
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}

private actor Recorder {
    private(set) var began: [Int] = []
    private(set) var finished: [Int] = []
    private(set) var cancelledDuringHandling: [Int] = []

    func recordBegan(_ counter: Int) {
        began.append(counter)
    }

    func recordFinished(_ counter: Int, wasCancelled: Bool) {
        finished.append(counter)
        if wasCancelled { cancelledDuringHandling.append(counter) }
    }
}

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor Counter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

private final class DrainHolder: Sendable {
    private let stored = Mutex<@Sendable () async -> Void>({})

    var drain: @Sendable () async -> Void {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }
}
