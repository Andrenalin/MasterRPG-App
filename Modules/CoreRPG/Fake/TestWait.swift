// @copyright André Trettin

import Foundation

#if DEBUG
/// Waits until `condition` holds, polling briefly, and gives up after `timeout`. For tests that
/// await an observation-driven or asynchronous update: a fixed sleep is flaky under load (TSan
/// batches) and needlessly slow otherwise. Returns whether the condition held.
/// See CODE_AUDIT_19 §9.26.
@MainActor
public func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}
#endif
