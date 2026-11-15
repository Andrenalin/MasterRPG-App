// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §10.2: the lock and task bookkeeping of an import review, which writes the
/// person's library.
@MainActor
@Suite("Import mutation session")
struct ImportMutationSessionTests {
    @MainActor
    private final class Probe {
        var events: [String] = []
        var allowBegin = true
    }

    private func makeSession(_ probe: Probe) -> ImportMutationSession {
        ImportMutationSession(handlers: .init(
            beginDataMutation: {
                probe.events.append("begin")
                return probe.allowBegin
            },
            endDataMutation: { probe.events.append("end") },
            beginSaveDeferral: {
                probe.events.append("defer")
                return UUID()
            },
            endSaveDeferral: { _ in probe.events.append("undefer") }
        ))
    }

    @Test("A refused lock leaves the session inactive and defers nothing")
    func refusedLock() {
        let probe = Probe()
        probe.allowBegin = false
        let session = makeSession(probe)

        #expect(!session.beginDataMutation())
        #expect(!session.isActive)
        #expect(probe.events == ["begin"])
    }

    @Test("Beginning twice takes the lock once; release ends the deferral before the lock, once")
    func beginAndReleaseOnce() async {
        let probe = Probe()
        let session = makeSession(probe)

        #expect(session.beginDataMutation())
        #expect(session.beginDataMutation())
        #expect(session.isActive)
        await session.release(cancelImport: false)
        await session.release(cancelImport: false)

        #expect(probe.events == ["begin", "defer", "undefer", "end"])
        #expect(!session.isActive)
    }

    @Test("Releasing a session that never began does nothing")
    func releaseWithoutBegin() async {
        let probe = Probe()
        let session = makeSession(probe)

        await session.release(cancelImport: true)

        #expect(probe.events.isEmpty)
    }

    @Test("Cancel while parsing waits for the parser to stop before the lock is released")
    func cancelWhileParsing() async {
        let probe = Probe()
        let session = makeSession(probe)
        #expect(session.beginDataMutation())
        let parser = Task<Void, any Error> { @MainActor in
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                probe.events.append("parser stopped")
                throw error
            }
        }
        #expect(session.trackImportTask(parser))
        await Task.yield()

        await session.release(cancelImport: true)

        #expect(probe.events == ["begin", "defer", "parser stopped", "undefer", "end"])
        #expect(session.canStartImport)
    }

    @Test("A second parse cannot be tracked while one runs")
    func secondParseRefused() async {
        let probe = Probe()
        let session = makeSession(probe)
        let first = Task<Void, any Error> { try await Task.sleep(for: .seconds(60)) }
        let second = Task<Void, any Error> { }

        #expect(session.trackImportTask(first))
        #expect(!session.trackImportTask(second))
        #expect(!session.canStartImport)

        first.cancel()
        _ = await first.result
    }

    @Test("Cancel while applying waits for the apply before the final release")
    func cancelWhileApplying() async {
        let probe = Probe()
        let session = makeSession(probe)
        #expect(session.beginDataMutation())
        var resumeApply: CheckedContinuation<Void, Never>?
        let applying = Task { @MainActor in
            await session.runApply {
                probe.events.append("apply start")
                await withCheckedContinuation { resumeApply = $0 }
                probe.events.append("apply end")
            }
        }
        while resumeApply == nil { await Task.yield() }

        let releasing = Task { @MainActor in await session.release(cancelImport: true) }
        for _ in 0..<20 { await Task.yield() }
        #expect(!probe.events.contains("end"), "the lock is held while the apply runs")

        resumeApply?.resume()
        await applying.value
        await releasing.value

        #expect(probe.events == ["begin", "defer", "apply start", "apply end", "undefer", "end"])
    }
}
