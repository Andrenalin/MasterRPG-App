// @copyright André Trettin

import SwiftUI

public struct RouteActions: Sendable {
    public static let tabId: UUID = UUID(uuidString: "C352A849-80F9-48B3-9010-8E1B49367192")!

    public init(routePage: @MainActor @escaping (NetworkModules, UUID?, UUID?) -> Void) {
        self.routePage = routePage
    }

    public let routePage: @MainActor (NetworkModules, UUID?, UUID?) -> Void
}

public extension EnvironmentValues {
    @Entry var routeActions: RouteActions = RouteActions { _, _, _ in }
}
