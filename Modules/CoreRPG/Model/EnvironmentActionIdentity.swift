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

    public static func fresh() -> Self { .token(UUID()) }
}
