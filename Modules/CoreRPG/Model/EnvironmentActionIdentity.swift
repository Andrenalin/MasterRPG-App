// @copyright André Trettin

import Foundation

/// A `Sendable`, `Hashable` identity token for closure-carrying environment
/// values (e.g. `MapActions`, `RouteActions`) whose sole purpose is letting
/// SwiftUI's environment diffing tell an unchanged writer apart from a
/// genuinely different one. Environment values that conform to `Equatable`
/// let SwiftUI skip invalidating readers when a re-render writes the same
/// value again — closures themselves are never `Equatable`, so these structs
/// compare this identity instead. `AnyHashable` can't be used for the token
/// since it isn't unconditionally `Sendable`.
public enum EnvironmentActionIdentity: Hashable, Sendable {
    /// Ties the identity to a stable, long-lived owning reference type (a
    /// root model), so repeated writes from that same owner compare equal.
    case object(ObjectIdentifier)
    /// Ties the identity to a specific module, for owners that aren't a
    /// single reference type (e.g. an `any` existential parameter).
    case module(NetworkModules)
    /// A one-off token for call sites with no natural stable identity —
    /// behaves like the old always-fresh default (no diffing benefit, but no
    /// worse than before).
    case token(UUID)

    /// A genuinely fresh, always-distinct token — the right choice whenever
    /// a real writer is being constructed with no natural stable identity of
    /// its own. Do **not** use this as the default for an `@Entry`
    /// environment value itself: `@Entry`'s generated default is
    /// re-evaluated on every environment read that hasn't been overridden by
    /// a real writer, so a fresh token here would make every such read
    /// compare unequal to the last — defeating SwiftUI's diffing before any
    /// writer even exists. Use `.unconfigured` for that case instead. See
    /// CODE_AUDIT §8.1.
    public static func fresh() -> Self { .token(UUID()) }

    /// A fixed identity reserved for `@Entry` environment defaults with no
    /// writer configured yet. Unlike `.fresh()`, this value must never
    /// change across evaluations — see the warning on `.fresh()` above.
    public static let unconfigured: Self = .token(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
}
