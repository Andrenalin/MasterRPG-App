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
}
