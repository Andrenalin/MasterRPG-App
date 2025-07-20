// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

public enum SpaceRoute: Equatable, Codable {
    case detail(UUID)
}

extension SpaceRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId)
        }
    }
}

struct DetailRouteDestinationView: View {
    init(itemId: UUID) {
        self.itemId = itemId
        self._items = Query(filter: #Predicate<SpaceDataModel>{ $0.id == itemId })
    }
    
    let itemId: UUID

    @Query private var items: [SpaceDataModel]
    
    var body: some View {
        if let item = items.first {
            DetailView(model: item)
        }
    }
}
