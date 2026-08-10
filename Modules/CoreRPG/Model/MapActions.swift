// @copyright André Trettin

import SwiftUI

public struct MapActions: Equatable, Sendable {
    /// `id` should be stable across the writer's re-renders (e.g. the owning
    /// root model's `ObjectIdentifier`) so SwiftUI's environment diffing can
    /// skip invalidating readers when the same root writes the same
    /// functional closure again. See CODE_AUDIT §8.8.
    public init(id: EnvironmentActionIdentity = .fresh(), quickMap: @MainActor @escaping @Sendable (String, UUID) async -> UUID?) {
        self.id = id
        self.quickMap = quickMap
    }

    let id: EnvironmentActionIdentity
    public let quickMap: @MainActor @Sendable (String, UUID) async -> UUID?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

public extension EnvironmentValues {
    var mapActions: MapActions {
        get { self[MapActionsKey.self] }
        set { self[MapActionsKey.self] = newValue }
    }
}

struct MapActionsKey: EnvironmentKey {
    static let defaultValue: MapActions = MapActions { _, _ in nil }
}
