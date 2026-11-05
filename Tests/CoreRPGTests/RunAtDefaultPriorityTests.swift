// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// ImageIO decodes on Default-QoS threads and blocks until they finish, so a decode must not
/// run at the User-initiated priority it inherits from a view's `.task` — the Thread Performance
/// Checker reported that as a priority inversion in `ImageDownsampler.downsampledImage`.
@Suite("Run at default priority")
struct RunAtDefaultPriorityTests {
    @Test("Work runs at medium priority even for a User-initiated caller that waits for it")
    func notEscalatedByCaller() async {
        let priority = await Task(priority: .userInitiated) {
            await runAtDefaultPriority { Task.currentPriority }
        }.value

        #expect(priority == .medium)
    }

    @Test("The caller's cancellation reaches the work")
    func cancellationPropagates() async {
        let started = AsyncStream<Void>.makeStream()
        let caller = Task {
            await runAtDefaultPriority {
                started.continuation.yield()
                while !Task.isCancelled {
                    await Task.yield()
                }
                return Task.isCancelled
            }
        }
        for await _ in started.stream { break }
        caller.cancel()

        #expect(await caller.value)
    }
}
