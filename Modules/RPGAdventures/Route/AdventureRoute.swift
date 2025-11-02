// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

public enum AdventureRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension AdventureRoute: RawRepresentable {
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

extension AdventureRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId)
        }
    }
}

struct DetailRouteDestinationView: View {
    let itemId: UUID
    @Environment(AdventureRoot.self) private var root
    
    var body: some View {
        //DetailRootView(selectedId: itemId)
        RootExtendedDetail(itemRowTreeModel: ItemRowTreeModel(itemId: itemId, typeId: .adventure), tabId: KnownRoutes.mainTabId)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            //.environment(root.rootController)
    }
}
