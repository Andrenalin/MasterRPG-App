// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels
import Testing

@testable import GeneratorRPG

/// CODE_AUDIT_26 §10.18: the transcript window, the one-shot gate and the bounded task wait.
@Suite("Generator transcript window")
struct TranscriptWindowTests {
    // 90 characters estimate to 20 tokens (4.5 characters per token).
    private func text(_ marker: String) -> String {
        marker + String(repeating: "x", count: 90 - marker.count)
    }

    private func prompt(_ marker: String) -> Transcript.Entry {
        .prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: text(marker)))]))
    }

    private func response(_ marker: String) -> Transcript.Entry {
        .response(Transcript.Response(assetIDs: [], segments: [.text(Transcript.TextSegment(content: text(marker)))]))
    }

    private func instructions() -> Transcript.Entry {
        .instructions(Transcript.Instructions(segments: [.text(Transcript.TextSegment(content: text("I")))], toolDefinitions: []))
    }

    private func isPrompt(_ entry: Transcript.Entry) -> Bool {
        if case .prompt = entry { return true }
        return false
    }

    @Test("Leading responses without their prompt are dropped")
    func orphanedLeadingEntriesAreDropped() {
        let entries = [response("r0"), prompt("p1"), response("r1")]

        let kept = Transcript.droppingLeadingNonPrompts(entries)

        #expect(kept.count == 2)
        #expect(kept.first.map(isPrompt) == true)
    }

    @Test("A window that starts with a prompt is kept whole and one without any prompt is empty")
    func droppingEdgeCases() {
        let whole = [prompt("p1"), response("r1")]
        #expect(Transcript.droppingLeadingNonPrompts(whole).count == 2)
        #expect(Transcript.droppingLeadingNonPrompts([response("r1"), response("r2")]).isEmpty)
        #expect(Transcript.droppingLeadingNonPrompts([Transcript.Entry]()).isEmpty)
    }

    @Test("The window keeps the instructions and the newest turns that fit")
    func windowKeepsNewestTurns() {
        let transcript = Transcript(entries: [])
        let conversation = [prompt("p1"), response("r1"), prompt("p2"), response("r2")]

        // Instructions 20 + p2 20 + r2 20 = 60 tokens; r1 would be the 80th.
        let window = transcript.foundationLabEstimatedTokenBudgetWindow(instructions: instructions(), conversation: conversation, budget: 60)

        #expect(window.count == 3)
        #expect(window.first.map { if case .instructions = $0 { true } else { false } } == true)
        #expect(isPrompt(window[1]))
    }

    @Test("A budget that only fits the last response drops that orphan too")
    func orphanedNewestResponseIsDropped() {
        let transcript = Transcript(entries: [])
        let conversation = [prompt("p1"), response("r1"), prompt("p2"), response("r2")]

        // Instructions 20 + r2 20 = 40 fits, p2 does not: r2 alone would be an orphan.
        let window = transcript.foundationLabEstimatedTokenBudgetWindow(instructions: instructions(), conversation: conversation, budget: 40)

        #expect(window.count == 1)
    }

    @Test("A generous budget keeps everything")
    func generousBudgetKeepsAll() {
        let transcript = Transcript(entries: [])
        let conversation = [prompt("p1"), response("r1"), prompt("p2"), response("r2")]

        let window = transcript.foundationLabEstimatedTokenBudgetWindow(instructions: instructions(), conversation: conversation, budget: 10_000)

        #expect(window.count == 5)
    }
}

@Suite("One-shot gate and task wait")
struct OneShotGateTests {
    @Test("Waiting on a gate that is already open returns at once", .timeLimit(.minutes(1)))
    func openBeforeWait() async {
        let gate = OneShotGate()
        gate.open()

        await gate.wait()
    }

    @Test("Opening twice resumes the waiter once and does not trap", .timeLimit(.minutes(1)))
    func doubleOpen() async {
        let gate = OneShotGate()
        let waiter = Task { await gate.wait() }
        try? await Task.sleep(for: .milliseconds(50))

        gate.open()
        gate.open()
        await waiter.value
        await gate.wait()
    }

    @Test("Waiting for a task that never ends stops at the timeout", .timeLimit(.minutes(1)))
    func timeoutEndsTheWait() async {
        let stuck = Task<Void, Never> { try? await Task.sleep(for: .seconds(300)) }
        defer { stuck.cancel() }
        let clock = ContinuousClock()
        let started = clock.now

        await GeneratorTaskWait.end(of: stuck, timeout: .milliseconds(150))

        #expect(started.duration(to: clock.now) < .seconds(30))
    }

    @Test("A task that ends first ends the wait before the timeout", .timeLimit(.minutes(1)))
    func finishedTaskEndsTheWait() async {
        let quick = Task<Void, Never> { try? await Task.sleep(for: .milliseconds(20)) }
        let clock = ContinuousClock()
        let started = clock.now

        await GeneratorTaskWait.end(of: quick, timeout: .seconds(120))

        #expect(started.duration(to: clock.now) < .seconds(30))
    }

    @Test("A cancelled waiter stops waiting at once", .timeLimit(.minutes(1)))
    func cancelledWaiterStops() async {
        let stuck = Task<Void, Never> { try? await Task.sleep(for: .seconds(300)) }
        defer { stuck.cancel() }
        let waiter = Task { await GeneratorTaskWait.end(of: stuck, timeout: .seconds(300)) }
        try? await Task.sleep(for: .milliseconds(50))

        waiter.cancel()
        await waiter.value
    }
}

#endif
