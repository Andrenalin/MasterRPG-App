// @copyright André Trettin

import Foundation
import os.log

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
    /// `encode(to:)` on one of these models (personally verified); otherwise
    /// `MainActor.assumeIsolated` traps. `file`/`line` default to the caller's `encode(to:)`
    /// so a future violation's trap/log points at the model that broke the invariant instead
    /// of this shared wrapper. See CODE_AUDIT.md §3.6.
    nonisolated func encodeOnMainActor(
        file: StaticString = #fileID,
        line: UInt = #line,
        _ body: @MainActor (Encoder) throws -> Void
    ) throws {
        nonisolated(unsafe) let encoder = self
        if !Thread.isMainThread {
            // Not a substitute for the `assumeIsolated` trap below (a custom executor could in
            // principle make this thread check imprecise) — just gives a diagnosable trace
            // naming the actual offending call site before the trap fires.
            Logger.codable.fault("encodeOnMainActor called off the main thread from \(file, privacy: .public):\(line, privacy: .public) — every Encodable model in this app is @MainActor; this call site needs to hop to MainActor before encoding.")
        }
        try MainActor.assumeIsolated({ try body(encoder) }, file: file, line: line)
    }
}
