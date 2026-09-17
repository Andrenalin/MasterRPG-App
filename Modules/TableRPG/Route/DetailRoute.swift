// @copyright André Trettin

import CoreRPG

import SwiftUI

#Preview(traits: .mockData) {
    ViewerRouteDestinationView(itemId: TableModel.previewId)
}

enum DetailRoute: Equatable, Hashable, Codable {
    case viewer(UUID)
}

extension DetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .viewer(let id): TaggedIdRoute.rawValue(token: "viewer", id: id)
        }
    }

    public init?(rawValue: String) {
        guard let route = TaggedIdRoute.parse(rawValue, resolve: { token, id -> Self? in
            switch token {
            case "viewer": return .viewer(id)
            default: return nil
            }
        }) else { return nil }
        self = route
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
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    
    var body: some View {
        root.viewController.viewer(root: root, itemId: itemId, configuration: ViewerConfiguration(closeButton: appSizeModel.mode == .compact))
            .moduleTint(root.configurable.module)
    }
}
