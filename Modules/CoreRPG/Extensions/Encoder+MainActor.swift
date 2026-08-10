// @copyright André Trettin

import Foundation

public extension Encoder {
    /// Runs `body`, assuming the caller is already Main-Actor-isolated.
    ///
    /// `Encodable.encode(to:)` is a `nonisolated` protocol requirement, but every domain
    /// model in this app is `@MainActor`-isolated, and `Encoder` isn't `Sendable`. Crossing
    /// that gap needs a `nonisolated(unsafe)` escape hatch somewhere — this is the single,
    /// audited place that does it, instead of each model hand-rolling its own copy of
    /// `nonisolated(unsafe) let encoder = encoder; MainActor.assumeIsolated { ... }`.
    ///
    /// Safe only because every real call site pre-hops to `MainActor` before invoking
    /// `encode(to:)` on one of these models (verified — see CODE_AUDIT §3.8); otherwise
    /// `MainActor.assumeIsolated` traps.
    nonisolated func encodeOnMainActor(_ body: @MainActor (Encoder) throws -> Void) throws {
        nonisolated(unsafe) let encoder = self
        try MainActor.assumeIsolated {
            try body(encoder)
        }
    }
}
