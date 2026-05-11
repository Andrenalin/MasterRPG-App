// @copyright André Trettin

import CoreRPG

import SwiftUI

public enum MapRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension MapRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
            case .detail(let id): "detail/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
            case "detail": self = .detail(uuid)
            default: return nil
        }
    }
}

extension MapRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            MapRouteDestinationView(itemId: itemId)
                .navigationAutoReceive(MapDetailRoute.self)
        }
    }
}

extension MapRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        MapRoute.detail(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .detail(let id): return id
        }
    }
}

struct MapRouteDestinationView: View {
    let itemId: UUID

    @Environment(MapRootModel.self) private var root

    var body: some View {
        // Fetch model once to avoid repeated lookups
        if let model = root.itemController.itemSync(for: itemId) {
            DetailRootViewWrapper(root: root, model: model)
        }
    }
}

// Separate wrapper to isolate observable dependencies
private struct DetailRootViewWrapper: View {
    let root: MapRootModel
    let model: MapModel

    var body: some View {
        DetailRootView(root: root, model: model)
            .equatable()  // Only recreate if model.id changes
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
    }
}
