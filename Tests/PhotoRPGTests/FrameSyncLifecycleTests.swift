// @copyright André Trettin

import Testing

@testable import PhotoRPG

@Suite("Frame sync lifecycle")
struct FrameSyncLifecycleTests {
    @Test("A sync started by make needs no restart while visible")
    func runningSyncNeedsNoRestart() {
        var lifecycle = FrameSyncLifecycle()
        lifecycle.started()
        lifecycle.appeared()

        #expect(!lifecycle.needsRestart)
    }

    @Test("Disappear then appear without a new make asks for a restart")
    func reappearNeedsRestart() {
        var lifecycle = FrameSyncLifecycle()
        lifecycle.started()
        lifecycle.appeared()
        lifecycle.disappeared()
        #expect(!lifecycle.needsRestart)

        lifecycle.appeared()
        #expect(lifecycle.needsRestart)

        lifecycle.started()
        #expect(!lifecycle.needsRestart)
    }

    @Test("A hidden view is never restarted")
    func hiddenViewStaysStopped() {
        var lifecycle = FrameSyncLifecycle()
        lifecycle.started()
        lifecycle.disappeared()

        #expect(!lifecycle.needsRestart)
    }
}
