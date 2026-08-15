// @copyright André Trettin

import Foundation

/// Centralized escape hatch for `nonisolated` protocol conformances (`Comparable`,
/// `ItemDiffComparable`, `ItemDuplicatable`) on `@MainActor @Observable` domain models.
///
/// These conformances are declared `nonisolated` so their requirements are callable from
/// non-isolated contexts (e.g. `Array.sorted()`, `Set`/`Dictionary` hashing, `Codable`
/// machinery), but their bodies need to read `@MainActor`-isolated stored properties.
/// `MainActor.assumeIsolated` is a *runtime* assertion, not a compile-time guarantee — it
/// traps instead of failing to compile if the assumption is ever wrong (e.g. a future caller
/// invokes `<`, `merge`, `isSame`, or `duplicate` from a genuinely non-Main-Actor context).
///
/// Route `nonisolated` conformance bodies through this helper rather than hand-rolling
/// `MainActor.assumeIsolated { ... }` inline, so there's exactly one place to find, audit, or
/// harden (e.g. with tracing/assertions) every site relying on this contract. See CODE_AUDIT §3.2.
@inline(__always)
public func assumeMainActorIsolated<T: Sendable>(_ body: @MainActor () -> T) -> T {
    MainActor.assumeIsolated(body)
}
