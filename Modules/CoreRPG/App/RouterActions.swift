// @copyright André Trettin

import SwiftUI

public struct RouteActions: Sendable, Equatable {
    /// `id` should be stable across the writer's re-renders (e.g. the owning
    /// root model's `ObjectIdentifier`) so SwiftUI's environment diffing can
    /// skip invalidating readers when the same root writes the same
    /// functional closure again.
    public init(id: EnvironmentActionIdentity = .fresh(), routePage: @MainActor @escaping (NetworkModules, UUID?, UUID?) -> Void) {
        self.id = id
        self.routePage = routePage
    }

    let id: EnvironmentActionIdentity
    public let routePage: @MainActor (NetworkModules, UUID?, UUID?) -> Void

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

public extension EnvironmentValues {
    // Explicitly passes the stable `.unconfigured` identity rather than
    // relying on `init`'s `.fresh()` default — `@Entry`'s generated default
    // is re-evaluated on every environment read that hasn't been overridden
    // by a real writer, so a fresh token here would make every such read
    // compare unequal to the last, defeating SwiftUI's diffing before any
    // writer even exists. Real writers elsewhere still get `.fresh()`'s
    // always-distinct behavior by omitting `id`, unaffected by this change.
    // See CODE_AUDIT §8.1.
    @Entry var routeActions: RouteActions = RouteActions(id: .unconfigured) { _, _, _ in }
}
