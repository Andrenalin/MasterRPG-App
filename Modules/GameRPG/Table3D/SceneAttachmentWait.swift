// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation

/// Waits until a RealityView scene is attached, with a deadline. Pure, so it is tested on iOS even
/// though its only caller is the visionOS table.
///
/// The SharePlay coordination of the table must start after the RealityView was made: an early
/// join crashes with "Could not find static equipment". A renderer root without a scene means
/// `make` has not run yet, which the caller must not take for "ready". See CODE_AUDIT_28 §5.16.
enum SceneAttachmentWait {
    /// - Returns: `true` when `isAttached` became true before the timeout; `false` on timeout or
    ///   cancellation.
    @MainActor
    static func wait(
        timeout: Duration = .seconds(10),
        interval: Duration = .milliseconds(20),
        isAttached: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !isAttached() {
            guard !Task.isCancelled, clock.now < deadline else { return false }
            try? await Task.sleep(for: interval)
        }
        return true
    }
}
#endif
