// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

public enum PhotoRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension PhotoRoute: RawRepresentable {
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

extension PhotoRoute: NavigationDestination {
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
        self._items = Query(filter: #Predicate<PhotoDataModel>{ $0.id == itemId })
    }
    
    let itemId: UUID

    @Query private var items: [PhotoDataModel]
    
    var body: some View {
        if let item = items.first {
            DetailView(model: item)
        }
    }
}
