// @copyright André Trettin

import Foundation

/// Waits for a condition instead of sleeping for a guessed time (CODE_AUDIT_TestGaps §3.4).
///
/// A fixed `Task.sleep` before an assertion is too short on a loaded runner (a flake) and too
/// long everywhere else (a slow suite). These helpers poll the condition on the caller's
/// isolation, so a main-actor test can read main-actor state in the closure.
///
/// Shared by the unit-test targets through the `Tests/TestSupport` folder. Not for snapshot tests.

/// Polls `condition` until it is true. Returns `false` when `timeout` passes first or the
/// calling task is cancelled, so the caller states the expectation (`#expect(await ...)`).
///
/// The default timeout is long on purpose: a wait that succeeds returns at once, so only a
/// failing test pays for it, while a short one flakes when a full parallel run starves the
/// main actor for seconds.
func awaitCondition(
    timeout: Duration = .seconds(30),
    pollInterval: Duration = .milliseconds(2),
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !(await condition()) {
        if Task.isCancelled || ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: pollInterval)
    }
    return true
}

/// Checks that `condition` stays true for the whole `window`, and fails as soon as it breaks.
///
/// For "nothing happens" assertions, which no event can signal. The window is only the time
/// the test gives a wrong implementation to show itself; a correct one never waits on it.
func conditionHolds(
    for window: Duration = .milliseconds(50),
    pollInterval: Duration = .milliseconds(5),
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + window
    while await condition() {
        if ContinuousClock.now >= deadline { return true }
        try? await Task.sleep(for: pollInterval)
    }
    return false
}
