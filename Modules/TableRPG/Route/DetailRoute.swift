// @copyright André Trettin

import CoreRPG

import SwiftUI

enum DetailRoute: Equatable, Hashable, Codable {
    case viewer(UUID)
}

extension DetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .viewer(let id): "viewer/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "viewer": self = .viewer(uuid)
        default: return nil
        }
    }
}

extension DetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .viewer(let itemId):
            ViewerRouteDestinationView(itemId: itemId)
        }
    }
}

struct ViewerRouteDestinationView: View {
    init(itemId: UUID) {
        self.itemId = itemId
    }
    
    let itemId: UUID

    @Environment(TableRootModel.self) private var root
    @Environment(\.appSizeMode) private var appSizeMode
    
    var body: some View {
        root.viewController.viewer(root: root, itemId: itemId, configuration: ViewerConfiguration(closeButton: appSizeMode == .compact))
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
    }
}
