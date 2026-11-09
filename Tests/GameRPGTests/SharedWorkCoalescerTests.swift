// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §3.6: the shared audio export is de-duplicated by run identity and
/// stops when nobody waits for it.
@Suite("Shared work coalescer")
@MainActor
struct SharedWorkCoalescerTests {

    @Test("callers that ask while the work runs share one run")
    func callersShareOneRun() async throws {
        let coalescer = SharedWorkCoalescer<Int, String>()
        let gate = WorkGate()
        let runs = RunCounter()
        let work: @Sendable () async throws -> String = {
            await runs.increment()
            await gate.wait()
            return "package"
        }

        let first = Task { try await coalescer.value(for: 1, work: work) }
        let second = Task { try await coalescer.value(for: 1, work: work) }
        let third = Task { try await coalescer.value(for: 1, work: work) }
        #expect(await Self.eventually { await gate.entered == 1 && coalescer.activeRunCount == 1 })
        await gate.open()

        #expect(try await first.value == "package")
        #expect(try await second.value == "package")
        #expect(try await third.value == "package")
        #expect(await runs.value == 1)
        #expect(coalescer.activeRunCount == 0)
    }

    @Test("a run that finishes late does not remove the entry of the newer run")
    func lateRunDoesNotRemoveNewerEntry() async throws {
        // The audit's interleaving: the first run is abandoned but its work ignores cancellation
        // and finishes only later; meanwhile a second run for the key has started.
        let coalescer = SharedWorkCoalescer<Int, String>()
        let firstGate = WorkGate()
        let secondGate = WorkGate()
        let runs = RunCounter()
        let firstWork: @Sendable () async throws -> String = {
            await runs.increment()
            await firstGate.wait()
            return "first"
        }
        let secondWork: @Sendable () async throws -> String = {
            await runs.increment()
            await secondGate.wait()
            return "second"
        }
        let abandoned = Task { try await coalescer.value(for: 1, work: firstWork) }
        #expect(await Self.eventually { await firstGate.entered == 1 })
        abandoned.cancel()
        _ = await abandoned.result
        let second = Task { try await coalescer.value(for: 1, work: secondWork) }
        #expect(await Self.eventually { await secondGate.entered == 1 })

        // When - the first run finishes now, then a further caller asks.
        await firstGate.open()
        for _ in 0 ..< 10 { await Task.yield() }
        let joiner = Task { try await coalescer.value(for: 1, work: secondWork) }
        for _ in 0 ..< 10 { await Task.yield() }
        await secondGate.open()

        // Then - the joiner shared the second run instead of starting a third.
        #expect(try await second.value == "second")
        #expect(try await joiner.value == "second")
        #expect(await runs.value == 2)
    }

    @Test("when the last waiter leaves, the work is cancelled and the caller returns at once")
    func lastWaiterCancelsTheWork() async {
        let coalescer = SharedWorkCoalescer<Int, String>()
        let observed = CancellationProbe()
        let caller = Task {
            try await coalescer.value(for: 1) {
                await observed.started()
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    await observed.sawCancellation()
                    throw error
                }
                return "never"
            }
        }
        #expect(await Self.eventually { await observed.isStarted })

        caller.cancel()
        let result = await caller.result

        if case .success = result { Issue.record("Expected the cancelled caller to throw") }
        #expect(await Self.eventually { await observed.wasCancelled })
        #expect(coalescer.activeRunCount == 0)
    }

    @Test("a waiter that leaves does not cancel the work the others wait for")
    func otherWaitersKeepTheWorkAlive() async throws {
        let coalescer = SharedWorkCoalescer<Int, String>()
        let gate = WorkGate()
        let work: @Sendable () async throws -> String = {
            await gate.wait()
            return Task.isCancelled ? "cancelled" : "package"
        }
        let leaving = Task { try await coalescer.value(for: 1, work: work) }
        let staying = Task { try await coalescer.value(for: 1, work: work) }
        #expect(await Self.eventually { await gate.entered == 1 })
        for _ in 0 ..< 10 { await Task.yield() }

        leaving.cancel()
        _ = await leaving.result
        await gate.open()

        #expect(try await staying.value == "package")
    }

    @Test("a failure reaches every waiter and frees the key")
    func failureFreesTheKey() async throws {
        struct Failure: Error {}
        let coalescer = SharedWorkCoalescer<Int, String>()
        let gate = WorkGate()
        let failing: @Sendable () async throws -> String = {
            await gate.wait()
            throw Failure()
        }
        let first = Task { try await coalescer.value(for: 1, work: failing) }
        let second = Task { try await coalescer.value(for: 1, work: failing) }
        #expect(await Self.eventually { await gate.entered == 1 })
        for _ in 0 ..< 10 { await Task.yield() }
        await gate.open()

        #expect((await first.result).isFailure)
        #expect((await second.result).isFailure)
        #expect(coalescer.activeRunCount == 0)
        #expect(try await coalescer.value(for: 1) { "again" } == "again")
    }

    private static func eventually(_ condition: @escaping @MainActor () async -> Bool) async -> Bool {
        for _ in 0 ..< 200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

/// Work that ignores cancellation: it stays suspended until the gate opens.
private actor WorkGate {
    private(set) var entered = 0
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private actor RunCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor CancellationProbe {
    private(set) var isStarted = false
    private(set) var wasCancelled = false
    func started() { isStarted = true }
    func sawCancellation() { wasCancelled = true }
}
#endif
