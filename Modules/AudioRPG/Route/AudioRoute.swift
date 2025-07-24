// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

public enum AudioRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension AudioRoute: RawRepresentable {
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

extension AudioRoute: NavigationDestination {
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
        self._items = Query(filter: #Predicate<AudioDataModel>{ $0.id == itemId })
    }
    
    let itemId: UUID

    @Query private var items: [AudioDataModel]
    
    var body: some View {
        let _ = Self._printChanges()
        
        if let item = items.first {
            DetailView(model: item)
        }
    }
}
