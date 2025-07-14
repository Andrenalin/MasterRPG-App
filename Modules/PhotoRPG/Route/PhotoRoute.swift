// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

enum PhotoRoute: Equatable, Codable {
    case photo(UUID)
}

extension PhotoRoute: NavigationDestination {
    var body: some View {
        switch self {
        case .photo(let itemId):
            PhotoRouteDestinationView(itemId: itemId)
        }
    }
}

struct PhotoRouteDestinationView: View {
    init(itemId: UUID) {
        self.itemId = itemId
        self._photos = Query(filter: #Predicate<PhotoDataModel>{ $0.id == itemId })
    }
    
    let itemId: UUID

    @Query private var photos: [PhotoDataModel]
    
    var body: some View {
        if let photo = photos.first {
            DetailView(model: photo)
        }
    }
}
