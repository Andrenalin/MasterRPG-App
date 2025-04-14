// @copyright André Trettin

import SwiftUI

public struct MapActions {
    public init(quickMap: @escaping (String, UUID) async -> UUID?) {
        self.quickMap = quickMap
    }

    public let quickMap: (String, UUID) async -> UUID?
}

public extension EnvironmentValues {
    var mapActions: MapActions {
        get { self[MapActionsKey.self] }
        set { self[MapActionsKey.self] = newValue }
    }
}

struct MapActionsKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: MapActions = MapActions { _, _ in nil }
}
