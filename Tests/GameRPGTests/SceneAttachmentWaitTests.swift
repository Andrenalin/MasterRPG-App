// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_28 §5.16: the table joined SharePlay when its RealityView scene was not attached
/// yet, because the wait for the first frame returned at once without a scene.
@MainActor
@Suite("Scene attachment wait")
struct SceneAttachmentWaitTests {
    @Test("Waits until the scene is attached")
    func waitsForAttachment() async {
        var polls = 0
        let attached = await SceneAttachmentWait.wait(timeout: .seconds(120), interval: .milliseconds(1)) {
            polls += 1
            return polls > 3
        }

        #expect(attached)
        #expect(polls == 4)
    }

    @Test("Gives up after the timeout")
    func timesOut() async {
        let attached = await SceneAttachmentWait.wait(timeout: .milliseconds(30), interval: .milliseconds(5)) { false }

        #expect(!attached)
    }

    @Test("A scene that is already attached needs no wait")
    func alreadyAttached() async {
        let attached = await SceneAttachmentWait.wait { true }

        #expect(attached)
    }

    @Test("Cancellation ends the wait without attachment")
    func cancellation() async {
        let task = Task { @MainActor in
            await SceneAttachmentWait.wait(timeout: .seconds(30), interval: .milliseconds(5)) { false }
        }
        task.cancel()

        #expect(await task.value == false)
    }
}
#endif
