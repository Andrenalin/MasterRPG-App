// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// The idle timer is one app-wide flag; each owner holds its own claim. See CODE_AUDIT §3.2.
@MainActor
@Suite("Keep awake")
struct KeepAwakeModelTests {
    private final class Recorder {
        var calls: [Bool] = []
    }

    private func makeModel() -> (KeepAwakeModel, Recorder) {
        let recorder = Recorder()
        return (KeepAwakeModel(apply: { recorder.calls.append($0) }), recorder)
    }

    @Test("The first owner turns it on and the last one turns it off")
    func firstAndLastOwner() {
        let (model, recorder) = makeModel()

        model.acquire(.game)
        #expect(model.isKeepingAwake)
        model.release(.game)

        #expect(!model.isKeepingAwake)
        #expect(recorder.calls == [true, false])
    }

    @Test("Leaving a capture screen keeps the screen awake for a running game")
    func captureLeavingKeepsGameAwake() {
        let (model, recorder) = makeModel()
        model.acquire(.game)
        model.acquire(.capture)

        model.release(.capture)

        #expect(model.isKeepingAwake)
        #expect(recorder.calls == [true])
    }

    @Test("Stopping a game keeps the screen awake for a running capture")
    func stoppingGameKeepsCaptureAwake() {
        let (model, recorder) = makeModel()
        model.acquire(.capture)
        model.acquire(.game)

        model.release(.game)

        #expect(model.isKeepingAwake)
        #expect(recorder.calls == [true])
    }

    @Test("Acquiring twice is one claim, and releasing something never held does nothing")
    func claimsAreIdempotent() {
        let (model, recorder) = makeModel()

        model.release(.reconstruction)
        model.acquire(.game)
        model.acquire(.game)
        model.release(.game)

        #expect(!model.isKeepingAwake)
        #expect(recorder.calls == [true, false])
    }
}
