// @copyright André Trettin

import CoreRPG
import SwiftUI

enum RuleViewerRoute: Equatable, Hashable, Codable {
    case viewer(UUID)
}

extension RuleViewerRoute: RawRepresentable {
    var rawValue: String {
        switch self {
        case .viewer(let id): "viewer/\(id.uuidString)"
        }
    }

    init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard values.first == "viewer",
              let value = values.last,
              let id = UUID(uuidString: String(value)) else { return nil }
        self = .viewer(id)
    }
}

extension RuleViewerRoute: NavigationDestination {
    var body: some View {
        switch self {
        case .viewer(let itemId): RuleViewerRouteDestinationView(itemId: itemId)
        }
    }
}

private struct RuleViewerRouteDestinationView: View {
    let itemId: UUID
    @Environment(RuleRootModel.self) private var root
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    var body: some View {
        root.viewController.viewer(
            root: root,
            itemId: itemId,
            configuration: ViewerConfiguration(closeButton: appSizeModel.mode == .compact)
        )
        .tint(NetworkModules.rule.tint)
    }
}
