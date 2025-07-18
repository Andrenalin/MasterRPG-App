// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

enum SpaceRoute: Equatable, Codable {
    case photo(UUID)
}

extension SpaceRoute: NavigationDestination {
    var body: some View {
        switch self {
        case .photo(let itemId):
            SpaceRouteDestinationView(itemId: itemId)
        }
    }
}

struct SpaceRouteDestinationView: View {
    init(itemId: UUID) {
        self.itemId = itemId
        self._photos = Query(filter: #Predicate<SpaceDataModel>{ $0.id == itemId })
    }
    
    let itemId: UUID

    @Query private var photos: [SpaceDataModel]
    
    var body: some View {
        if let photo = photos.first {
            DetailView(model: photo)
        }
    }
}
