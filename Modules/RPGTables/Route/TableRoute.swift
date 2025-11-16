// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

public enum TableRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension TableRoute: RawRepresentable {
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

extension TableRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId)
        }
    }
}

struct DetailRouteDestinationView: View {
    let itemId: UUID
    @Environment(TableRootModel.self) private var root
    
    var body: some View {
        RootExtendedDetail(itemRowTreeModel: ItemRowTreeModel(itemId: itemId, typeId: .table), tabId: KnownRoutes.mainTabId)
        //DetailRootView(selectedId: itemId)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
//            .environment(root.rootController)
    }
}
