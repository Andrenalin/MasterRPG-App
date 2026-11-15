// @copyright André Trettin

import Foundation
import Observation
import os
import Testing

@testable import CoreRPG

@MainActor
@Suite("Scenes manager state")
struct ScenesManagerObservationTests {
    @Test("An untracked scene is closed, and a set state is read back")
    func stateRoundTrip() {
        let sut = ScenesManager()

        #expect(sut.getSceneState(for: .battleRound) == .closed)
        sut.setSceneState(.opened, for: .battleRound)
        #expect(sut.getSceneState(for: .battleRound) == .opened)
        #expect(sut.getSceneState(for: .mapEditor) == .closed)
    }

    @Test("A scene's state change reaches only that scene's observers")
    func observationIsPerScene() {
        let sut = ScenesManager()
        // `onChange` runs synchronously inside the mutation that triggers it.
        let editorInvalidated = OSAllocatedUnfairLock(initialState: false)
        let battleInvalidated = OSAllocatedUnfairLock(initialState: false)

        // A view that shows the Map Editor window's state, and one for Battle Round.
        withObservationTracking {
            _ = sut.getSceneState(for: .mapEditor)
        } onChange: {
            editorInvalidated.withLock { $0 = true }
        }
        withObservationTracking {
            _ = sut.getSceneState(for: .battleRound)
        } onChange: {
            battleInvalidated.withLock { $0 = true }
        }

        sut.setSceneState(.opened, for: .battleRound)

        #expect(battleInvalidated.withLock { $0 })
        #expect(!editorInvalidated.withLock { $0 })
    }

    @Test("Setting the state a scene already has notifies nobody")
    func unchangedStateDoesNotNotify() {
        let sut = ScenesManager()
        sut.setSceneState(.opened, for: .battleRound)
        let invalidated = OSAllocatedUnfairLock(initialState: false)

        withObservationTracking {
            _ = sut.getSceneState(for: .battleRound)
        } onChange: {
            invalidated.withLock { $0 = true }
        }
        sut.setSceneState(.opened, for: .battleRound)

        #expect(!invalidated.withLock { $0 })
    }

    @Test("Closing one of two viewer windows keeps the scene opened until the last one is gone (CODE_AUDIT_26 §5.12)")
    func sceneStaysOpenedWhileAWindowIsActive() {
        let sut = ScenesManager()
        let first = UUID()
        let second = UUID()

        sut.windowBecameActive(first, for: .battleRound)
        sut.windowBecameActive(second, for: .battleRound)
        #expect(sut.activeWindowCount(for: .battleRound) == 2)

        #expect(!sut.windowEnded(first, for: .battleRound))
        #expect(sut.getSceneState(for: .battleRound) == .opened)

        #expect(sut.windowEnded(second, for: .battleRound))
        #expect(sut.getSceneState(for: .battleRound) == .closed)
        #expect(sut.activeWindowCount(for: .battleRound) == 0)
    }

    @Test("A window that ends twice, or that never became active, does not close another one")
    func endingIsIdempotentPerWindow() {
        let sut = ScenesManager()
        let open = UUID()
        sut.windowBecameActive(open, for: .battleRound)

        // `onDisappear` after the `.background` change reports the same window again.
        #expect(!sut.windowEnded(UUID(), for: .battleRound))
        #expect(sut.getSceneState(for: .battleRound) == .opened)
        #expect(sut.windowEnded(open, for: .battleRound))
        #expect(sut.windowEnded(open, for: .battleRound), "ending an already closed scene stays closed")
        #expect(sut.getSceneState(for: .battleRound) == .closed)
    }

    @Test("A scene dismissed while a second window stays open is opened again, not closing")
    func closingStateIsRepairedByRemainingWindow() {
        let sut = ScenesManager()
        let first = UUID()
        let second = UUID()
        sut.windowBecameActive(first, for: .battleRound)
        sut.windowBecameActive(second, for: .battleRound)
        sut.setSceneState(.closing, for: .battleRound)

        sut.windowEnded(first, for: .battleRound)

        #expect(sut.getSceneState(for: .battleRound) == .opened)
    }
}
