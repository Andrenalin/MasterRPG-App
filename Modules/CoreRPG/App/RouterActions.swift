// @copyright André Trettin

import SwiftUI

public struct RouteActions: Sendable, Equatable {
    public static let tabId: UUID = UUID(uuidString: "C352A849-80F9-48B3-9010-8E1B49367192")!

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
    @Entry var routeActions: RouteActions = RouteActions { _, _, _ in }
}
