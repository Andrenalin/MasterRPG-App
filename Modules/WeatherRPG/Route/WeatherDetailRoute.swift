// @copyright André Trettin

import CoreRPG
import CoreExternalRPG
import SwiftUI

public enum WeatherDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
}

extension WeatherDetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .folder(let id): "folder/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "folder": self = .folder(uuid)
        default: return nil
        }
    }
}

extension WeatherDetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .folder(let itemId):
            WeatherDetailRouteDestinationView(itemId: itemId)
        }
    }
}

extension WeatherDetailRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        WeatherDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
        }
    }
}

struct WeatherDetailRouteDestinationView: View {
    let itemId: UUID

    @Environment(WeatherRootModel.self) private var root
    
    var body: some View {
        DetailListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.folderListController.detailInspectorModel)
            .environment(root.rootController)
    }
}
